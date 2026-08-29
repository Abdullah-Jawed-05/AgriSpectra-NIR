import 'dart:typed_data';

import 'package:flutter/foundation.dart' show compute;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../core/constants/app_constants.dart';
import '../core/utils/result.dart';
import '../domain/entities/nir_device_info.dart';
import '../domain/entities/scan.dart';
import '../domain/entities/seed_result.dart';
import '../domain/entities/spectral_measurement.dart';
import '../ml/vision_pipeline.dart';
import '../nir/fusion_engine.dart';
import '../nir/no_nir_device.dart';
import '../nir/spectral_device.dart';

/// Progress events emitted while [ScanOrchestrator.analyze] runs, so the
/// "Analyzing" screen can show something more informative than a spinner.
/// [analyzingImage] covers the whole vision pipeline (quality gate through
/// classification) — that work runs as one unit on a background isolate
/// (see ml/vision_pipeline.dart), so there's no meaningful finer-grained
/// progress to report for it without a more complex isolate protocol than
/// `compute()` gives us.
enum AnalysisStage { analyzingImage, readingNir, fusing, saving, done }

/// Runs the full pipeline (§5 of the architecture doc): quality gate →
/// detection/segmentation → feature extraction → classification → batch
/// aggregation → optional NIR fusion → persistence. This is the one place
/// all of those modules are wired together, so cross-module data-shape
/// mismatches (§77 of the build spec) show up here first.
class ScanOrchestrator {
  ScanOrchestrator({FusionEngine? fusionEngine}) : _fusionEngine = fusionEngine ?? const FusionEngine();

  final FusionEngine _fusionEngine;

  static const _uuid = Uuid();

  Future<Result<Scan>> analyze({
    required Uint8List imageBytes,
    required String crop,
    required SpectralDevice nirDevice,
    required Map<String, Object?> cameraMetadata,
    void Function(AnalysisStage stage)? onProgress,
  }) async {
    onProgress?.call(AnalysisStage.analyzingImage);
    // Runs on a background isolate — see runVisionPipeline's doc comment
    // for why this must not run synchronously on the UI isolate.
    final vision = await compute(runVisionPipeline, imageBytes);

    if (vision.errorMessage != null || vision.processedSeeds == null || vision.batchStatistics == null) {
      return Result.err(vision.errorMessage ?? 'Analysis failed.');
    }

    final processed = vision.processedSeeds!;
    final batchStats = vision.batchStatistics!;

    onProgress?.call(AnalysisStage.readingNir);
    SpectralMeasurement? spectral;
    final scanId = _uuid.v4();
    if (nirDevice is! NoNIRDevice) {
      try {
        final status = await nirDevice.getStatus();
        if (status.status == NirConnectionStatus.connected) {
          await nirDevice.startScan();
          spectral = await nirDevice.getMeasurement(scanId);
        }
      } catch (_) {
        // NIR unavailable/disconnected mid-scan must never abort the
        // camera-only result (§36, §58) — fall through with spectral=null.
        spectral = null;
      }
    }

    onProgress?.call(AnalysisStage.fusing);
    final fusionResult = _fusionEngine.fuse(crop: crop, visualStats: batchStats, spectral: spectral);

    onProgress?.call(AnalysisStage.saving);

    final results = processed.map((p) {
      // Every ProcessedSeed the vision pipeline built was given a
      // prediction, so this is always non-null here.
      final prediction = p.prediction!;
      return SeedResult(
        seedId: p.seedId,
        scanId: scanId,
        cropPng: p.cropPng,
        segmentation: {
          'bounding_box': {
            'x': p.boundingBox.left,
            'y': p.boundingBox.top,
            'width': p.boundingBox.width,
            'height': p.boundingBox.height,
          },
          'center': {'x': p.center.dx, 'y': p.center.dy},
          'orientation_radians': p.orientationRadians,
          'contour': p.contour.map((o) => [o.dx, o.dy]).toList(),
        },
        visualFeatures: p.features,
        prediction: prediction,
        confidence: prediction.confidence,
        anomalies: prediction.anomalies,
      );
    }).toList();

    final scan = Scan(
      scanId: scanId,
      timestamp: DateTime.now(),
      crop: crop,
      cameraMetadata: cameraMetadata,
      imageQuality: vision.quality,
      numberOfSeeds: vision.seedsDetected,
      batchScore: fusionResult.combinedScore,
      confidence: fusionResult.confidence,
      visionModelVersion: AppVersions.visionModelVersion,
      analysisVersion: AppVersions.analysisVersion,
      nirAvailable: spectral != null,
      nirDeviceId: spectral?.deviceId,
      batchStatistics: batchStats,
      fusionResult: fusionResult,
      results: results,
    );

    onProgress?.call(AnalysisStage.done);
    return Result.ok(scan);
  }
}

final scanOrchestratorProvider = Provider<ScanOrchestrator>((ref) => ScanOrchestrator());

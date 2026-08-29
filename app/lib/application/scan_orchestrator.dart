import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image/image.dart' as img;
import 'package:uuid/uuid.dart';

import '../core/constants/app_constants.dart';
import '../core/utils/result.dart';
import '../domain/entities/nir_device_info.dart';
import '../domain/entities/processed_seed.dart';
import '../domain/entities/scan.dart';
import '../domain/entities/seed_result.dart';
import '../domain/entities/spectral_measurement.dart';
import '../ml/batch_engine.dart';
import '../ml/feature_extractor.dart';
import '../ml/image_quality_gate.dart';
import '../ml/rule_classifier.dart';
import '../ml/seed_finder.dart';
import '../nir/fusion_engine.dart';
import '../nir/no_nir_device.dart';
import '../nir/spectral_device.dart';

/// Progress events emitted while [ScanOrchestrator.analyze] runs, so the
/// "Analyzing" screen can show something more informative than a spinner.
enum AnalysisStage {
  checkingQuality,
  detectingSeeds,
  extractingFeatures,
  classifying,
  readingNir,
  fusing,
  saving,
  done,
}

/// Runs the full pipeline (§5 of the architecture doc): quality gate →
/// detection/segmentation → feature extraction → classification → batch
/// aggregation → optional NIR fusion → persistence. This is the one place
/// all of those modules are wired together, so cross-module data-shape
/// mismatches (§77 of the build spec) show up here first.
class ScanOrchestrator {
  ScanOrchestrator({
    SeedFinder? seedFinder,
    FeatureExtractor? featureExtractor,
    RuleBasedClassifier? classifier,
    BatchEngine? batchEngine,
    FusionEngine? fusionEngine,
    ImageQualityGate? qualityGate,
  })  : _seedFinder = seedFinder ?? ClassicalCVSeedFinder(),
        _featureExtractor = featureExtractor ?? const FeatureExtractor(),
        _classifier = classifier ?? const RuleBasedClassifier(),
        _batchEngine = batchEngine ?? const BatchEngine(),
        _fusionEngine = fusionEngine ?? const FusionEngine(),
        _qualityGate = qualityGate ?? const ImageQualityGate();

  final SeedFinder _seedFinder;
  final FeatureExtractor _featureExtractor;
  final RuleBasedClassifier _classifier;
  final BatchEngine _batchEngine;
  final FusionEngine _fusionEngine;
  final ImageQualityGate _qualityGate;

  static const _uuid = Uuid();

  Future<Result<Scan>> analyze({
    required img.Image image,
    required String crop,
    required SpectralDevice nirDevice,
    required Map<String, Object?> cameraMetadata,
    void Function(AnalysisStage stage)? onProgress,
  }) async {
    onProgress?.call(AnalysisStage.checkingQuality);
    final quality = _qualityGate.evaluate(image);
    if (!quality.usable) {
      return Result.err(
        quality.warnings.isNotEmpty
            ? quality.warnings.join(' ')
            : 'Image quality is too low for reliable analysis.',
      );
    }

    onProgress?.call(AnalysisStage.detectingSeeds);
    final segmented = _seedFinder.find(image);
    if (segmented.isEmpty) {
      return const Result.err(
        'No seeds detected. Make sure seeds are spread out, in focus, and contrast '
        'clearly against the background, then try again.',
      );
    }

    onProgress?.call(AnalysisStage.extractingFeatures);
    onProgress?.call(AnalysisStage.classifying);

    final processed = <ProcessedSeed>[];
    for (final seed in segmented) {
      final features = _featureExtractor.extract(seed);
      final prediction = _classifier.classify(features);
      processed.add(ProcessedSeed(
        seedId: seed.seedId,
        cropPng: img.encodePng(seed.crop),
        mask: seed.mask,
        maskWidth: seed.crop.width,
        maskHeight: seed.crop.height,
        boundingBox: seed.boundingBox,
        contour: seed.contour,
        center: seed.center,
        orientationRadians: seed.orientationRadians,
        features: features,
        prediction: prediction,
      ));
    }

    final seedFinder = _seedFinder;
    final rejectedCount = seedFinder is ClassicalCVSeedFinder ? seedFinder.lastRejectedCandidates : 0;

    final batchStats = _batchEngine.aggregate(
      seedsDetected: segmented.length,
      accepted: processed,
      seedsRejected: rejectedCount,
    );

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
      // Every ProcessedSeed built above was given a prediction from
      // _classifier.classify(...), so this is always non-null here.
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
      imageQuality: quality,
      numberOfSeeds: segmented.length,
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

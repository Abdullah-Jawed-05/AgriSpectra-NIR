// Dev-only diagnostic: build a real Scan from a real barley photo (running
// the actual on-device pipeline, not fixtures) and render ScanReportPdf to
// a file for visual inspection. Not a *_test.dart file, so bare
// `flutter test` won't pick it up.
//
// Usage: flutter test test/tool/pdf_preview_dev.dart --dart-define=IMAGE_PATH=<path> --dart-define=OUT_PATH=<path>
import 'dart:io';

import 'package:agrispectra/domain/entities/fusion_result.dart';
import 'package:agrispectra/domain/entities/scan.dart';
import 'package:agrispectra/domain/entities/seed_result.dart';
import 'package:agrispectra/domain/entities/spectral_measurement.dart';
import 'package:agrispectra/export/scan_report_pdf.dart';
import 'package:agrispectra/ml/vision_pipeline.dart';

const _imagePath = String.fromEnvironment('IMAGE_PATH');
const _outPath = String.fromEnvironment('OUT_PATH');

void main() async {
  if (_imagePath.isEmpty || _outPath.isEmpty) {
    stderr.writeln('Pass --dart-define=IMAGE_PATH=... --dart-define=OUT_PATH=...');
    exit(1);
  }

  final bytes = File(_imagePath).readAsBytesSync();
  final vision = runVisionPipeline(bytes);
  if (vision.processedSeeds == null || vision.batchStatistics == null) {
    stderr.writeln('Pipeline failed: ${vision.errorMessage}');
    exit(1);
  }

  final results = vision.processedSeeds!.map((p) {
    final prediction = p.prediction!;
    return SeedResult(
      seedId: p.seedId,
      scanId: 'scan_preview',
      cropPng: p.cropPng,
      segmentation: const {},
      visualFeatures: p.features,
      prediction: prediction,
      confidence: prediction.confidence,
      anomalies: prediction.anomalies,
    );
  }).toList();

  final fusion = FusionResult(
    assessmentId: 'assess_preview',
    mode: AssessmentMode.multimodal,
    crop: 'barley',
    visualScore: vision.batchStatistics!.averageScore,
    nirScore: 88,
    combinedScore: (vision.batchStatistics!.averageScore + 88) / 2,
    confidence: 0.82,
    seedCount: vision.batchStatistics!.seedsAccepted,
    anomalies: vision.batchStatistics!.anomalyCount,
    modelVersions: const {'vision': 'agrivision-v0.2-rule-engine', 'nir': 'agrinir-v0-simulated', 'fusion': 'agrifusion-v0-weighted'},
  );

  final scan = Scan(
    scanId: 'scan_preview',
    timestamp: DateTime(2026, 9, 5, 14, 30),
    crop: 'barley',
    cameraMetadata: const {},
    imageQuality: vision.quality,
    numberOfSeeds: vision.seedsDetected,
    batchScore: fusion.combinedScore,
    confidence: fusion.confidence,
    visionModelVersion: 'agrivision-v0.2-rule-engine',
    analysisVersion: '0.2.0',
    nirAvailable: true,
    nirDeviceId: 'AgriSpectra-NIR-SIM',
    batchStatistics: vision.batchStatistics!,
    fusionResult: fusion,
    results: results,
  );

  final rng = List.generate(18, (i) => 0.3 + 0.5 * (i / 18) + (i.isEven ? 0.05 : -0.03));
  final spectral = SpectralMeasurement(
    scanId: 'scan_preview',
    deviceId: 'AgriSpectra-NIR-SIM',
    timestamp: scan.timestamp,
    wavelengthsNm: List.generate(18, (i) => 410.0 + i * 30),
    rawValues: rng,
    darkReference: List.filled(18, 0.02),
    whiteReference: List.filled(18, 0.95),
    reflectance: rng,
    integrationTimeMs: 100,
    temperatureC: 24.5,
    humidityPercent: 41,
    isSimulated: true,
    calibrationStatus: 'valid',
  );

  final pdfBytes = await ScanReportPdf.build(scan: scan, spectral: spectral);
  File(_outPath).writeAsBytesSync(pdfBytes);
  // ignore: avoid_print
  print('Wrote ${pdfBytes.length} bytes to $_outPath (${results.length} seeds, quality=${vision.quality.usable})');
}

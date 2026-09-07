import 'package:agrispectra/domain/entities/batch_statistics.dart';
import 'package:agrispectra/domain/entities/spectral_measurement.dart';

/// A plausible [BatchStatistics] with the score/confidence overridable —
/// those two are all the fusion engine reads.
BatchStatistics batchStats({
  double averageScore = 80,
  double confidence = 0.7,
  int seedsAccepted = 12,
  int anomalyCount = 1,
  int impurityCount = 0,
}) {
  return BatchStatistics(
    seedsDetected: seedsAccepted + impurityCount,
    seedsAccepted: seedsAccepted,
    seedsRejected: 0,
    averageScore: averageScore,
    uniformity: 0.8,
    anomalyCount: anomalyCount,
    confidence: confidence,
    scoreHistogram: List<int>.filled(10, 0),
    qualityClassCounts: {'GOOD': seedsAccepted},
    impurityCount: impurityCount,
    purityRatio: seedsAccepted / (seedsAccepted + impurityCount),
  );
}

/// A [SpectralMeasurement]. Defaults describe a healthy, well-calibrated
/// reading; override to exercise the failure paths.
SpectralMeasurement spectral({
  String scanId = 'scan_1',
  String calibrationStatus = 'valid',
  List<double>? rawValues,
  List<double>? reflectance = const [0.30, 0.32, 0.31, 0.33, 0.34, 0.33],
  bool isSimulated = true,
}) {
  return SpectralMeasurement(
    scanId: scanId,
    deviceId: 'dev_test',
    timestamp: DateTime(2026, 9, 7),
    wavelengthsNm: const [610, 680, 730, 760, 810, 860],
    rawValues: rawValues ?? const [12000, 12500, 12300, 12800, 13000, 12900],
    darkReference: const [100, 100, 100, 100, 100, 100],
    whiteReference: const [40000, 40000, 40000, 40000, 40000, 40000],
    reflectance: reflectance,
    integrationTimeMs: 50,
    temperatureC: 24,
    humidityPercent: 45,
    isSimulated: isSimulated,
    calibrationStatus: calibrationStatus,
  );
}

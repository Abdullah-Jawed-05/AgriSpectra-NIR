import 'dart:math';

import '../core/constants/app_constants.dart';
import '../domain/entities/batch_statistics.dart';
import '../domain/entities/fusion_result.dart';
import '../domain/entities/spectral_measurement.dart';
import 'nir_quality.dart';

/// Late-fusion combiner (§35, §71): runs after the vision pipeline and the
/// NIR pipeline have each produced an independent score, and combines them
/// weighted by *how reliable each sensor's reading currently is* — not a
/// blind average. A poor camera image with excellent NIR should not fall
/// back to a camera-dominated result, and excellent imagery with a bad
/// NIR calibration should not let a noisy NIR reading damage the result
/// (§71 examples, verbatim).
///
/// This is Model V0 of fusion: a confidence-weighted linear combination.
/// A learned fusion model (logistic regression / LightGBM / small NN, per
/// §71) requires paired ground-truth data this project does not have yet
/// — see docs/ML_PIPELINE.md Model V5.
class FusionEngine {
  const FusionEngine();

  FusionResult fuse({
    required String crop,
    required BatchStatistics visualStats,
    required SpectralMeasurement? spectral,
  }) {
    final assessmentId = _generateId();

    if (spectral == null) {
      return FusionResult(
        assessmentId: assessmentId,
        mode: AssessmentMode.cameraOnly,
        crop: crop,
        visualScore: visualStats.averageScore,
        nirScore: null,
        combinedScore: visualStats.averageScore,
        confidence: visualStats.confidence,
        seedCount: visualStats.seedsAccepted,
        anomalies: visualStats.anomalyCount,
        modelVersions: const {'vision': AppVersions.visionModelVersion},
      );
    }

    final nirQuality = const NirQualityScorer().score(spectral);
    final nirScore = _spectralQualityScore(spectral);

    final visualConfidence = visualStats.confidence;
    final nirConfidence = nirQuality.overallConfidence;

    final totalWeight = visualConfidence + nirConfidence;
    final combinedScore = totalWeight > 0
        ? (visualStats.averageScore * visualConfidence + nirScore * nirConfidence) / totalWeight
        : visualStats.averageScore;

    final combinedConfidence =
        (visualConfidence + nirConfidence) / 2 * (0.85 + 0.15 * min(visualConfidence, nirConfidence));

    return FusionResult(
      assessmentId: assessmentId,
      mode: AssessmentMode.multimodal,
      crop: crop,
      visualScore: visualStats.averageScore,
      nirScore: nirScore,
      combinedScore: combinedScore,
      confidence: combinedConfidence.clamp(0.0, 1.0),
      seedCount: visualStats.seedsAccepted,
      anomalies: visualStats.anomalyCount,
      modelVersions: const {
        'vision': AppVersions.visionModelVersion,
        'nir': AppVersions.nirModelVersion,
        'fusion': AppVersions.fusionModelVersion,
      },
    );
  }

  /// Maps mean reflectance to a 0..100 "NIR enhancement" score. This is a
  /// deliberately simple placeholder mapping — §73 forbids inventing a
  /// correction equation, so this is presented as a screening signal, not
  /// a calibrated physical measurement, until validated against real
  /// paired data.
  double _spectralQualityScore(SpectralMeasurement m) {
    final reflectance = m.reflectance;
    if (reflectance == null || reflectance.isEmpty) return 50;
    final mean = reflectance.reduce((a, b) => a + b) / reflectance.length;
    return (mean * 100).clamp(0.0, 100.0);
  }

  String _generateId() =>
      'assess_${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}';
}

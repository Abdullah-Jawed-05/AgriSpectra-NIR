import 'dart:math' as math;

import '../domain/entities/batch_statistics.dart';
import '../domain/entities/processed_seed.dart';
import '../domain/value_objects/confidence_level.dart';
import '../domain/value_objects/quality_class.dart';

/// Aggregates per-seed predictions into batch-level statistics (§21).
///
/// Objects the pipeline classified as [QualityClass.impurities] are foreign
/// matter, not seeds — they're pulled out here and reported as a separate
/// batch-purity figure ([BatchStatistics.impurityCount] /
/// [BatchStatistics.purityRatio]). Every other statistic
/// (score, uniformity, histogram, anomaly count, class counts) is computed
/// over the seeds only.
class BatchEngine {
  const BatchEngine();

  BatchStatistics aggregate({
    required int seedsDetected,
    required List<ProcessedSeed> accepted,
    required int seedsRejected,
  }) {
    final scored = accepted.where((s) => s.prediction != null).toList();

    final impurities = scored
        .where((s) => s.prediction!.qualityClass == QualityClass.impurities)
        .toList();
    final seeds = scored
        .where((s) => s.prediction!.qualityClass != QualityClass.impurities)
        .toList();

    final detectedObjects = seeds.length + impurities.length;
    final purityRatio = detectedObjects == 0 ? 1.0 : seeds.length / detectedObjects;

    if (seeds.isEmpty) {
      return BatchStatistics(
        seedsDetected: seedsDetected,
        seedsAccepted: 0,
        seedsRejected: seedsRejected,
        averageScore: 0,
        uniformity: 0,
        anomalyCount: 0,
        confidence: 0,
        scoreHistogram: List.filled(10, 0),
        qualityClassCounts: const {},
        impurityCount: impurities.length,
        purityRatio: purityRatio,
      );
    }

    final scores = seeds.map((s) => s.prediction!.score).toList();
    final averageScore = scores.reduce((a, b) => a + b) / scores.length;

    final variance =
        scores.map((s) => (s - averageScore) * (s - averageScore)).reduce((a, b) => a + b) /
            scores.length;
    final stdDev = variance <= 0 ? 0.0 : math.sqrt(variance);
    // Uniformity: 100 = identical scores across the batch, decaying as
    // spread increases. A std-dev of 30+ points is treated as "not
    // uniform at all".
    final uniformity = (1 - (stdDev / 30)).clamp(0.0, 1.0);

    final anomalyCount = seeds.where((s) => s.prediction!.anomalies.isNotEmpty).length;

    final confidences = seeds.map((s) => s.prediction!.confidence).toList();
    final avgConfidence = confidences.reduce((a, b) => a + b) / confidences.length;

    final histogram = List<int>.filled(10, 0);
    for (final score in scores) {
      final bucket = (score / 10).floor().clamp(0, 9);
      histogram[bucket]++;
    }

    final classCounts = <String, int>{};
    for (final seed in seeds) {
      final key = seed.prediction!.qualityClass.storageKey;
      classCounts[key] = (classCounts[key] ?? 0) + 1;
    }

    return BatchStatistics(
      seedsDetected: seedsDetected,
      seedsAccepted: seeds.length,
      seedsRejected: seedsRejected,
      averageScore: averageScore,
      uniformity: uniformity,
      anomalyCount: anomalyCount,
      confidence: avgConfidence,
      scoreHistogram: histogram,
      qualityClassCounts: classCounts,
      impurityCount: impurities.length,
      purityRatio: purityRatio,
    );
  }

  ConfidenceLevel confidenceLevel(BatchStatistics stats) => confidenceLevelFrom(stats.confidence);
}

import '../value_objects/germination_reference.dart';

/// Batch-level aggregation (§21) produced by the batch engine from a list
/// of per-seed predictions.
class BatchStatistics {
  final int seedsDetected;
  final int seedsAccepted;
  final int seedsRejected;
  final double averageScore;

  /// 0..1. Higher = more consistent quality across the batch.
  final double uniformity;
  final int anomalyCount;
  final double confidence;

  /// Histogram bucket counts for the score distribution chart, fixed at
  /// 10 buckets of width 10 (0-10, 10-20, ..., 90-100).
  final List<int> scoreHistogram;

  final Map<String, int> qualityClassCounts;

  /// Detected objects classified as foreign matter rather than seeds. These
  /// are excluded from every per-seed quality figure above and reported
  /// separately (a batch-purity concern, not a seed-quality one).
  final int impurityCount;

  /// 0..1. seeds / (seeds + impurities) — the fraction of detected objects
  /// that were actual seeds. 1.0 when nothing was detected.
  final double purityRatio;

  /// 0..1 expected germination of the batch, from the barley growth-test
  /// rate of each seed's quality class (see [GerminationReference]).
  /// Derived from [qualityClassCounts], so older stored scans get it too.
  /// `null` when no seed has a class with a measured rate.
  double? get expectedGermination => GerminationReference.expectedRate(qualityClassCounts);

  /// True when the batch has seeds and every one of them is in a class that
  /// never germinated (all broken / shriveled).
  bool get isNonViable => expectedGermination == 0.0;

  const BatchStatistics({
    required this.seedsDetected,
    required this.seedsAccepted,
    required this.seedsRejected,
    required this.averageScore,
    required this.uniformity,
    required this.anomalyCount,
    required this.confidence,
    required this.scoreHistogram,
    required this.qualityClassCounts,
    required this.impurityCount,
    required this.purityRatio,
  });
}

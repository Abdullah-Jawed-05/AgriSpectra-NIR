import 'quality_class.dart';

/// Barley germination ground truth: the fraction of seeds in each visual
/// quality class that germinated in the team's growth test of the barley
/// reference set (see docs/VALIDATION.md).
///
/// | Class     | Germinated |
/// |-----------|------------|
/// | Good      | ~75%       |
/// | Damaged   | 45%        |
/// | Broken    | 0%         |
/// | Shriveled | 0%         |
///
/// [QualityClass.impurities] and [QualityClass.unknown] are not seeds with
/// a measured outcome, so they have no rate and are left out of every
/// germination figure.
class GerminationReference {
  GerminationReference._();

  static const Map<QualityClass, double> barley = {
    QualityClass.good: 0.75,
    QualityClass.damaged: 0.45,
    QualityClass.broken: 0.0,
    QualityClass.shriveled: 0.0,
  };

  /// Observed germination rate for [qualityClass], or `null` when the
  /// class has no growth-test outcome.
  static double? rateFor(QualityClass qualityClass) => barley[qualityClass];

  /// True for classes where no seed germinated in the growth test.
  static bool isNonViable(QualityClass qualityClass) => rateFor(qualityClass) == 0.0;

  /// Expected germination (0..1) of a batch given its per-class seed
  /// counts (keyed by [QualityClassLabel.storageKey], the shape
  /// [BatchStatistics.qualityClassCounts] uses). `null` when no counted
  /// seed belongs to a class with a measured rate.
  static double? expectedRate(Map<String, int> classCounts) {
    var seeds = 0;
    var germinating = 0.0;
    for (final entry in classCounts.entries) {
      final rate = rateFor(QualityClassLabel.fromStorageKey(entry.key));
      if (rate == null) continue;
      seeds += entry.value;
      germinating += rate * entry.value;
    }
    return seeds == 0 ? null : germinating / seeds;
  }
}

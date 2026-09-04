import 'dart:math' as math;

import '../domain/entities/processed_seed.dart';
import '../domain/entities/quality_prediction.dart';
import '../domain/value_objects/quality_class.dart';

/// Model V0 impurity screening: flags detected objects whose size or shape
/// makes them outliers versus the rest of the batch as
/// [QualityClass.impurities] (foreign matter — stones, chaff, stems,
/// other-crop seeds).
///
/// This is deliberately a batch-relative heuristic, not a per-seed rule: a
/// roughly seed-sized object can only be judged "foreign" relative to the
/// population it was photographed with. It runs after [RuleBasedClassifier]
/// and overrides the class of anything it flags.
///
/// Like the rest of Model V0 (see rule_classifier.dart), the constants here
/// are engineering judgement calibrated against the barley reference set —
/// not a statistically validated cutoff. Model V1, trained on the labelled
/// dataset that includes an IMPURITIES folder, is what should actually learn
/// this (docs/ML_PIPELINE.md; §43/§66 of the build spec).
class ImpurityDetector {
  const ImpurityDetector();

  /// Below this many detections the batch distribution is too small to call
  /// anything an outlier — nothing is flagged.
  static const int minSampleForOutlierTest = 5;

  /// A detection is treated as foreign matter when its area or aspect ratio
  /// is more than this many MADs (median absolute deviations) from the batch
  /// median.
  static const double outlierMadMultiplier = 4.0;

  /// Floor for the MAD, as a fraction of the median, so a very uniform batch
  /// (MAD ~ 0) doesn't make every small deviation read as a huge outlier.
  static const double minRelativeMad = 0.05;

  List<ProcessedSeed> flag(List<ProcessedSeed> seeds) {
    final scored = seeds.where((s) => s.prediction != null).toList();
    if (scored.length < minSampleForOutlierTest) return seeds;

    final areas = scored.map((s) => s.features.geometry.areaPx).toList();
    final aspects = scored.map((s) => s.features.geometry.aspectRatio).toList();

    final areaMedian = _median(areas);
    final aspectMedian = _median(aspects);
    final areaMad =
        math.max(_mad(areas, areaMedian), minRelativeMad * areaMedian.abs());
    final aspectMad =
        math.max(_mad(aspects, aspectMedian), minRelativeMad * aspectMedian.abs());

    return seeds.map((seed) {
      final prediction = seed.prediction;
      if (prediction == null) return seed;

      final area = seed.features.geometry.areaPx;
      final aspect = seed.features.geometry.aspectRatio;
      final areaDev = areaMad > 0 ? (area - areaMedian).abs() / areaMad : 0.0;
      final aspectDev = aspectMad > 0 ? (aspect - aspectMedian).abs() / aspectMad : 0.0;

      if (areaDev <= outlierMadMultiplier && aspectDev <= outlierMadMultiplier) {
        return seed;
      }

      final reason = areaDev >= aspectDev
          ? 'markedly ${area > areaMedian ? 'larger' : 'smaller'} than the rest of the batch'
          : 'a different shape from the rest of the batch';

      return seed.copyWith(
        prediction: QualityPrediction(
          qualityClass: QualityClass.impurities,
          score: prediction.score,
          confidence: prediction.confidence,
          evidence: [
            EvidenceFactor(
              description: 'Size/shape inconsistent with the batch ($reason) — '
                  'likely foreign matter rather than a seed',
              supportsGoodQuality: false,
              weight: 1,
            ),
            ...prediction.evidence,
          ],
          anomalies: ['foreign_object_suspected', ...prediction.anomalies],
          modelVersion: prediction.modelVersion,
        ),
      );
    }).toList();
  }

  double _median(List<double> xs) {
    if (xs.isEmpty) return 0;
    final s = [...xs]..sort();
    final n = s.length;
    return n.isOdd ? s[n ~/ 2] : (s[n ~/ 2 - 1] + s[n ~/ 2]) / 2;
  }

  double _mad(List<double> xs, double median) =>
      _median(xs.map((x) => (x - median).abs()).toList());
}

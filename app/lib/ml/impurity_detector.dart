import 'dart:math' as math;

import '../domain/entities/processed_seed.dart';
import '../domain/entities/quality_prediction.dart';
import '../domain/value_objects/quality_class.dart';

/// Model V0 impurity screening: flags detected objects that are foreign
/// matter (stones, chaff, stems, other-crop seeds) as
/// [QualityClass.impurities].
///
/// A blob is foreign matter only if it is **both** a size/shape outlier
/// **and** a colour outlier versus the rest of the batch. Requiring the
/// colour signal is what stops an unusually large, small or bent *barley*
/// grain — or a segmentation fragment — from being mislabelled foreign:
/// chaff is pale, a stone is grey, another crop's seed is a different hue,
/// but a deformed barley grain is still barley-coloured. A very strong
/// colour outlier alone is enough.
///
/// This is deliberately a batch-relative heuristic, not a per-seed rule. It
/// runs after [RuleBasedClassifier] and overrides the class of anything it
/// flags. Like the rest of Model V0 the constants are engineering
/// judgement, not a validated cutoff — Model V1's trained IMPURITIES class
/// is the real answer (docs/ML_PIPELINE.md; §43/§66).
class ImpurityDetector {
  const ImpurityDetector();

  /// Below this many detections the batch distribution is too small to call
  /// anything an outlier — nothing is flagged.
  static const int minSampleForOutlierTest = 5;

  /// A detection is a size/shape outlier when its area or aspect ratio is
  /// more than this many MADs from the batch median.
  static const double shapeOutlierMads = 4.0;

  /// A detection is a colour outlier when its (Lab a*, Lab b*) is more than
  /// this many MADs from the batch median in that plane.
  static const double colourOutlierMads = 3.5;

  /// A colour outlier this extreme is foreign matter on its own, no
  /// size/shape outlier required.
  static const double strongColourOutlierMads = 7.0;

  /// Floor for a MAD, as a fraction of the median, so a very uniform batch
  /// (MAD ~ 0) doesn't make every small deviation read as a huge outlier.
  static const double minRelativeMad = 0.05;

  List<ProcessedSeed> flag(List<ProcessedSeed> seeds) {
    final scored = seeds.where((s) => s.prediction != null).toList();
    if (scored.length < minSampleForOutlierTest) return seeds;

    final areas = scored.map((s) => s.features.geometry.areaPx).toList();
    final aspects = scored.map((s) => s.features.geometry.aspectRatio).toList();
    final labA = scored.map((s) => s.features.color.meanLabA).toList();
    final labB = scored.map((s) => s.features.color.meanLabB).toList();

    final areaMedian = _median(areas);
    final aspectMedian = _median(aspects);
    final labAMedian = _median(labA);
    final labBMedian = _median(labB);

    final areaMad = math.max(_mad(areas, areaMedian), minRelativeMad * areaMedian.abs());
    final aspectMad = math.max(_mad(aspects, aspectMedian), minRelativeMad * aspectMedian.abs());
    // MAD of the colour distance from the batch-median colour.
    final colourDistances = [
      for (var i = 0; i < scored.length; i++)
        _dist(labA[i], labB[i], labAMedian, labBMedian),
    ];
    final colourMad = math.max(_median(colourDistances.map((d) => (d - _median(colourDistances)).abs()).toList()), 0.5);

    return seeds.map((seed) {
      final prediction = seed.prediction;
      if (prediction == null) return seed;

      final area = seed.features.geometry.areaPx;
      final aspect = seed.features.geometry.aspectRatio;
      final areaDev = areaMad > 0 ? (area - areaMedian).abs() / areaMad : 0.0;
      final aspectDev = aspectMad > 0 ? (aspect - aspectMedian).abs() / aspectMad : 0.0;
      final colourDev = _dist(seed.features.color.meanLabA, seed.features.color.meanLabB,
              labAMedian, labBMedian) /
          colourMad;

      final shapeOutlier = areaDev > shapeOutlierMads || aspectDev > shapeOutlierMads;
      final colourOutlier = colourDev > colourOutlierMads;
      final isImpurity = (shapeOutlier && colourOutlier) || colourDev > strongColourOutlierMads;
      if (!isImpurity) return seed;

      final reason = colourDev >= math.max(areaDev, aspectDev)
          ? 'a different colour from the rest of the batch'
          : areaDev >= aspectDev
              ? 'a different colour and markedly ${area > areaMedian ? 'larger' : 'smaller'} than the batch'
              : 'a different colour and shape from the rest of the batch';

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

  double _median(Iterable<double> xs) {
    final s = [...xs]..sort();
    if (s.isEmpty) return 0;
    final n = s.length;
    return n.isOdd ? s[n ~/ 2] : (s[n ~/ 2 - 1] + s[n ~/ 2]) / 2;
  }

  double _mad(List<double> xs, double median) =>
      _median(xs.map((x) => (x - median).abs()).toList());

  double _dist(double a1, double b1, double a2, double b2) =>
      math.sqrt((a1 - a2) * (a1 - a2) + (b1 - b2) * (b1 - b2));
}

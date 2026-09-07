import 'package:agrispectra/domain/entities/seed_features.dart';
import 'package:agrispectra/domain/value_objects/quality_class.dart';
import 'package:agrispectra/ml/rule_classifier.dart';
import 'package:flutter_test/flutter_test.dart';

/// A sound-barley [SeedFeatures] with a few fields overridable — the rule
/// engine only looks at `damage.darkRegionRatio` and
/// `damage.crackLikeEdgeRatio`, but the geometry/colour overrides let the
/// regression tests prove the *removed* rules stay removed.
SeedFeatures seed({
  double darkRegionRatio = 0.03,
  double crackLikeEdgeRatio = 0.02,
  double holeRatio = 0.0,
  double discolorationRatio = 0.05,
  double circularity = 0.2,
  double eccentricity = 0.9,
  double aspectRatio = 2.6,
}) {
  return SeedFeatures(
    geometry: GeometryFeatures(
      areaPx: 8000,
      perimeterPx: 400,
      widthPx: 30,
      lengthPx: 78,
      aspectRatio: aspectRatio,
      circularity: circularity,
      eccentricity: eccentricity,
      convexity: 0.8,
    ),
    color: ColorFeatures(
      meanR: 150,
      meanG: 120,
      meanB: 80,
      meanHue: 35,
      meanSaturation: 0.2,
      meanValue: 0.5,
      meanLabL: 55,
      meanLabA: 6,
      meanLabB: 28,
      colorVarianceRgb: 120,
      discolorationRatio: discolorationRatio,
    ),
    texture: const TextureFeatures(
      edgeDensity: 0.1,
      entropy: 0.5,
      surfaceIrregularity: 0.1,
      localContrast: 0.08,
    ),
    damage: DamageIndicators(
      darkRegionRatio: darkRegionRatio,
      crackLikeEdgeRatio: crackLikeEdgeRatio,
      holeRatio: holeRatio,
      abnormalPigmentationScore: 0.1,
    ),
  );
}

void main() {
  const classifier = RuleBasedClassifier();

  test('a clean seed reads as good with a high score', () {
    final p = classifier.classify(seed());
    expect(p.qualityClass, QualityClass.good);
    expect(p.score, greaterThan(90));
    expect(p.anomalies, isEmpty);
  });

  test('heavy surface darkening routes to damaged', () {
    final p = classifier.classify(seed(darkRegionRatio: 0.45));
    expect(p.qualityClass, QualityClass.damaged);
    expect(p.score, lessThan(85));
    expect(p.anomalies, contains('dark_surface_regions'));
  });

  test('crack-like edge density routes to damaged', () {
    final p = classifier.classify(seed(crackLikeEdgeRatio: 0.6));
    expect(p.qualityClass, QualityClass.damaged);
    expect(p.anomalies, contains('possible_surface_cracking'));
  });

  test('barley-shaped geometry alone is NOT penalised (regression: the old '
      'shape rule flagged every elongated grain as shriveled)', () {
    final p = classifier.classify(seed(circularity: 0.17, eccentricity: 0.92, aspectRatio: 3.5));
    expect(p.qualityClass, QualityClass.good);
    expect(p.anomalies, isEmpty);
  });

  test('natural husk colour variation alone is NOT penalised (regression: the '
      'old discoloration rule was backwards for barley)', () {
    final p = classifier.classify(seed(discolorationRatio: 0.5));
    expect(p.qualityClass, QualityClass.good);
  });

  test('V0 never emits shriveled / broken / impurities', () {
    for (final f in [
      seed(darkRegionRatio: 0.9),
      seed(crackLikeEdgeRatio: 0.9),
      seed(circularity: 0.02, eccentricity: 0.99),
      seed(holeRatio: 0.5),
    ]) {
      expect(
        classifier.classify(f).qualityClass,
        anyOf(QualityClass.good, QualityClass.damaged),
      );
    }
  });
}

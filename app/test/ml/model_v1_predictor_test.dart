import 'package:agrispectra/domain/entities/seed_features.dart';
import 'package:agrispectra/domain/value_objects/quality_class.dart';
import 'package:agrispectra/ml/agrispectra_model_v1_adapter.dart';
import 'package:agrispectra/ml/model_v1_predictor.dart';
import 'package:flutter_test/flutter_test.dart';

SeedFeatures _features() => const SeedFeatures(
      geometry: GeometryFeatures(
        areaPx: 8000,
        perimeterPx: 400,
        widthPx: 30,
        lengthPx: 78,
        aspectRatio: 2.6,
        circularity: 0.72,
        eccentricity: 0.6,
        convexity: 0.9,
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
        discolorationRatio: 0.05,
      ),
      texture: TextureFeatures(
        edgeDensity: 0.1,
        entropy: 0.5,
        surfaceIrregularity: 0.1,
        localContrast: 0.08,
      ),
      damage: DamageIndicators(
        darkRegionRatio: 0.03,
        crackLikeEdgeRatio: 0.02,
        holeRatio: 0.0,
        abnormalPigmentationScore: 0.1,
      ),
    );

void main() {
  test('useModelV1 is off by default (never wire an unvalidated model in automatically)', () {
    expect(useModelV1, isFalse);
  });

  test('tryModelV1 returns null while V1 is unavailable/disabled, never throws', () {
    expect(() => tryModelV1(_features()), returnsNormally);
    expect(tryModelV1(_features()), isNull);
  });

  group('predictionFromModelV1Result (the actual label/confidence mapping)', () {
    test('decodes the highest-scoring class and a confidence from the raw scores', () {
      final result = const ModelV1Prediction('DAMAGED', [0.1, 0.7, 0.1, 0.1]);
      final prediction = predictionFromModelV1Result(result);

      expect(prediction.qualityClass, QualityClass.damaged);
      expect(prediction.confidence, closeTo(0.7, 1e-9));
      expect(prediction.score, closeTo(70, 1e-6));
      expect(prediction.anomalies, contains('model_v1_flagged'));
      expect(prediction.evidence.single.supportsGoodQuality, isFalse);
    });

    test('a good verdict carries no anomalies and positive evidence', () {
      final result = const ModelV1Prediction('GOOD', [0.9, 0.05, 0.05]);
      final prediction = predictionFromModelV1Result(result);

      expect(prediction.qualityClass, QualityClass.good);
      expect(prediction.anomalies, isEmpty);
      expect(prediction.evidence.single.supportsGoodQuality, isTrue);
    });

    test('an unrecognised label degrades to unknown rather than throwing', () {
      final result = const ModelV1Prediction('SOME_FUTURE_LABEL', [1.0]);
      final prediction = predictionFromModelV1Result(result);
      expect(prediction.qualityClass, QualityClass.unknown);
    });

    test('all-zero scores produce a defined (zero) confidence, not NaN/division-by-zero', () {
      final result = const ModelV1Prediction('GOOD', [0.0, 0.0]);
      final prediction = predictionFromModelV1Result(result);
      expect(prediction.confidence, 0.0);
      expect(prediction.score, 0.0);
    });

    test('a confident broken or shriveled call scores 0 (never germinated in growth tests)', () {
      for (final label in ['BROKEN', 'SHRIVELED']) {
        final prediction = predictionFromModelV1Result(ModelV1Prediction(label, const [0.05, 0.9, 0.05]));
        expect(prediction.score, 0, reason: label);
        expect(prediction.confidence, closeTo(0.9, 1e-9), reason: label);
      }
    });
  });
}

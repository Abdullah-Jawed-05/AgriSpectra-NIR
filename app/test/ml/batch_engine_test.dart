import 'package:agrispectra/domain/value_objects/quality_class.dart';
import 'package:agrispectra/ml/batch_engine.dart';
import 'package:flutter_test/flutter_test.dart';

import '_seed_fixtures.dart';

void main() {
  const engine = BatchEngine();

  test('impurities are excluded from every per-seed quality figure', () {
    final seeds = [
      makeSeed(id: 's1', score: 90, qualityClass: QualityClass.good),
      makeSeed(id: 's2', score: 80, qualityClass: QualityClass.good),
      makeSeed(id: 's3', score: 10, qualityClass: QualityClass.impurities, anomalies: ['foreign_object_suspected']),
    ];

    final stats = engine.aggregate(seedsDetected: 3, accepted: seeds, seedsRejected: 0);

    expect(stats.seedsAccepted, 2, reason: 'only real seeds count as accepted');
    expect(stats.averageScore, 85, reason: 'impurity score of 10 must not drag the average');
    expect(stats.anomalyCount, 0, reason: 'the impurity carried the only anomaly');
    expect(stats.qualityClassCounts.containsKey('IMPURITIES'), isFalse);
    expect(stats.qualityClassCounts['GOOD'], 2);
  });

  test('purityRatio and impurityCount reflect the foreign-matter split', () {
    final seeds = [
      for (var i = 0; i < 8; i++) makeSeed(id: 'seed$i', qualityClass: QualityClass.good),
      makeSeed(id: 'imp1', qualityClass: QualityClass.impurities),
      makeSeed(id: 'imp2', qualityClass: QualityClass.impurities),
    ];

    final stats = engine.aggregate(seedsDetected: 10, accepted: seeds, seedsRejected: 0);

    expect(stats.impurityCount, 2);
    expect(stats.purityRatio, closeTo(8 / 10, 1e-9));
  });

  test('a batch that is all impurities produces zeroed quality stats but a real purity figure', () {
    final seeds = [
      makeSeed(id: 'imp1', qualityClass: QualityClass.impurities),
      makeSeed(id: 'imp2', qualityClass: QualityClass.impurities),
    ];

    final stats = engine.aggregate(seedsDetected: 2, accepted: seeds, seedsRejected: 0);

    expect(stats.seedsAccepted, 0);
    expect(stats.averageScore, 0);
    expect(stats.impurityCount, 2);
    expect(stats.purityRatio, 0);
  });

  test('empty batch is safe and reads as fully pure', () {
    final stats = engine.aggregate(seedsDetected: 0, accepted: const [], seedsRejected: 4);

    expect(stats.seedsAccepted, 0);
    expect(stats.impurityCount, 0);
    expect(stats.purityRatio, 1.0);
    expect(stats.scoreHistogram, List.filled(10, 0));
  });

  test('a batch of only broken and shriveled seeds scores 0 with 0 confidence and 0% germination', () {
    final seeds = [
      makeSeed(id: 'b1', score: 92, confidence: 0.9, qualityClass: QualityClass.broken),
      makeSeed(id: 'b2', score: 88, confidence: 0.9, qualityClass: QualityClass.broken),
      makeSeed(id: 's1', score: 75, confidence: 0.8, qualityClass: QualityClass.shriveled),
    ];

    final stats = engine.aggregate(seedsDetected: 3, accepted: seeds, seedsRejected: 0);

    expect(stats.averageScore, 0);
    expect(stats.confidence, 0);
    expect(stats.expectedGermination, 0);
    expect(stats.isNonViable, isTrue);
    expect(stats.scoreHistogram[0], 3);
  });

  test('expected germination follows the growth-test rate of each class', () {
    final seeds = [
      for (var i = 0; i < 6; i++) makeSeed(id: 'g$i', qualityClass: QualityClass.good),
      for (var i = 0; i < 2; i++) makeSeed(id: 'd$i', qualityClass: QualityClass.damaged),
      makeSeed(id: 'b1', qualityClass: QualityClass.broken),
      makeSeed(id: 's1', qualityClass: QualityClass.shriveled),
      makeSeed(id: 'imp', qualityClass: QualityClass.impurities),
    ];

    final stats = engine.aggregate(seedsDetected: 11, accepted: seeds, seedsRejected: 0);

    // (6 * 0.90 + 2 * 0.65 + 0 + 0) / 10 seeds; the impurity is not a seed.
    expect(stats.expectedGermination, closeTo(0.67, 1e-9));
    expect(stats.isNonViable, isFalse);
    expect(stats.confidence, greaterThan(0));
  });

  test('broken and shriveled seeds count as 0 in a mixed batch average', () {
    final seeds = [
      makeSeed(id: 'g1', score: 90, qualityClass: QualityClass.good),
      makeSeed(id: 'b1', score: 90, qualityClass: QualityClass.broken),
    ];

    final stats = engine.aggregate(seedsDetected: 2, accepted: seeds, seedsRejected: 0);

    expect(stats.averageScore, 45);
  });
}

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
}

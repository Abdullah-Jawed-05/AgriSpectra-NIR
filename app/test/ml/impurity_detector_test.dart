import 'package:agrispectra/domain/entities/processed_seed.dart';
import 'package:agrispectra/domain/value_objects/quality_class.dart';
import 'package:agrispectra/ml/impurity_detector.dart';
import 'package:flutter_test/flutter_test.dart';

import '_seed_fixtures.dart';

void main() {
  const detector = ImpurityDetector();

  // A batch of uniform barley grains: same size, shape and (Lab a*, b*).
  List<ProcessedSeed> barleyBatch(int n) => [
        for (var i = 0; i < n; i++)
          makeSeed(id: 'seed$i', areaPx: 1000 + i * 5.0, aspectRatio: 2.0, labA: 5, labB: 30),
      ];

  test('a stone — different colour AND bigger — is flagged as impurities', () {
    final seeds = [
      ...barleyBatch(9),
      makeSeed(id: 'stone', areaPx: 6000, aspectRatio: 1.2, labA: 0, labB: 2), // grey, large, stubby
    ];

    final flagged = detector.flag(seeds);
    final stone = flagged.firstWhere((s) => s.seedId == 'stone');
    expect(stone.prediction!.qualityClass, QualityClass.impurities);
    expect(stone.prediction!.anomalies, contains('foreign_object_suspected'));
    for (final s in flagged.where((s) => s.seedId != 'stone')) {
      expect(s.prediction!.qualityClass, isNot(QualityClass.impurities));
    }
  });

  test('a large but barley-COLOURED grain is NOT flagged (regression: the '
      'user saw big/bent grains and shadows called impurities)', () {
    final seeds = [
      ...barleyBatch(9),
      makeSeed(id: 'big_grain', areaPx: 6000, aspectRatio: 2.0, labA: 5, labB: 30),
    ];

    final flagged = detector.flag(seeds);
    expect(
      flagged.firstWhere((s) => s.seedId == 'big_grain').prediction!.qualityClass,
      isNot(QualityClass.impurities),
    );
  });

  test('a strong colour outlier alone is enough (a clearly foreign object)', () {
    final seeds = [
      ...barleyBatch(9),
      makeSeed(id: 'red_thing', areaPx: 1000, aspectRatio: 2.0, labA: 45, labB: 30),
    ];

    final flagged = detector.flag(seeds);
    expect(
      flagged.firstWhere((s) => s.seedId == 'red_thing').prediction!.qualityClass,
      QualityClass.impurities,
    );
  });

  test('a uniform batch flags nothing', () {
    final flagged = detector.flag([...barleyBatch(12)]);
    expect(flagged.any((s) => s.prediction!.qualityClass == QualityClass.impurities), isFalse);
  });

  test('below the minimum sample size nothing is flagged', () {
    final seeds = [
      makeSeed(id: 's1'),
      makeSeed(id: 's2'),
      makeSeed(id: 's3'),
      makeSeed(id: 'huge', areaPx: 50000, labA: 0, labB: 0),
    ];
    expect(detector.flag(seeds), same(seeds));
  });
}

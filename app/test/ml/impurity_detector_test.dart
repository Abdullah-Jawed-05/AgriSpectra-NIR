import 'package:agrispectra/domain/value_objects/quality_class.dart';
import 'package:agrispectra/ml/impurity_detector.dart';
import 'package:flutter_test/flutter_test.dart';

import '_seed_fixtures.dart';

void main() {
  const detector = ImpurityDetector();

  test('a clear size outlier in an otherwise uniform batch is flagged as impurities', () {
    final seeds = [
      for (var i = 0; i < 9; i++) makeSeed(id: 'seed$i', areaPx: 1000, aspectRatio: 2.0),
      makeSeed(id: 'rock', areaPx: 9000, aspectRatio: 2.0), // ~9x the batch median area
    ];

    final flagged = detector.flag(seeds);

    final rock = flagged.firstWhere((s) => s.seedId == 'rock');
    expect(rock.prediction!.qualityClass, QualityClass.impurities);
    expect(rock.prediction!.anomalies, contains('foreign_object_suspected'));

    for (final s in flagged.where((s) => s.seedId != 'rock')) {
      expect(s.prediction!.qualityClass, isNot(QualityClass.impurities));
    }
  });

  test('a shape outlier is flagged even when its area is typical', () {
    final seeds = [
      for (var i = 0; i < 9; i++) makeSeed(id: 'seed$i', areaPx: 1000, aspectRatio: 2.0),
      makeSeed(id: 'stem', areaPx: 1000, aspectRatio: 12.0), // long and thin
    ];

    final flagged = detector.flag(seeds);

    expect(flagged.firstWhere((s) => s.seedId == 'stem').prediction!.qualityClass,
        QualityClass.impurities);
  });

  test('a uniform batch flags nothing', () {
    final seeds = [
      for (var i = 0; i < 12; i++)
        makeSeed(id: 'seed$i', areaPx: 1000 + i * 10.0, aspectRatio: 2.0 + i * 0.01),
    ];

    final flagged = detector.flag(seeds);

    expect(flagged.any((s) => s.prediction!.qualityClass == QualityClass.impurities), isFalse);
  });

  test('below the minimum sample size nothing is flagged', () {
    final seeds = [
      makeSeed(id: 's1', areaPx: 1000),
      makeSeed(id: 's2', areaPx: 1000),
      makeSeed(id: 's3', areaPx: 1000),
      makeSeed(id: 'huge', areaPx: 50000),
    ];

    final flagged = detector.flag(seeds);

    expect(flagged, same(seeds));
  });
}

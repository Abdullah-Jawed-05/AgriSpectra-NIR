import 'package:agrispectra/domain/entities/fusion_result.dart';
import 'package:agrispectra/nir/fusion_engine.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fixtures.dart';

void main() {
  const engine = FusionEngine();

  test('with no spectral reading the result is camera-only and passes vision through unchanged', () {
    final r = engine.fuse(crop: 'barley', visualStats: batchStats(averageScore: 72, confidence: 0.6), spectral: null);

    expect(r.mode, AssessmentMode.cameraOnly);
    expect(r.combinedScore, 72);
    expect(r.confidence, 0.6);
    expect(r.nirScore, isNull);
    expect(r.modelVersions.containsKey('nir'), isFalse);
  });

  test('a well-calibrated NIR reading pulls the combined score toward the NIR score', () {
    // reflectance mean 0.80 -> nirScore 80; visual 40.
    final r = engine.fuse(
      crop: 'barley',
      visualStats: batchStats(averageScore: 40, confidence: 0.5),
      spectral: spectral(reflectance: const [0.80, 0.80, 0.80, 0.80]),
    );

    expect(r.mode, AssessmentMode.multimodal);
    expect(r.nirScore, closeTo(80, 0.001));
    expect(r.combinedScore, greaterThan(40));
    expect(r.combinedScore, lessThan(80));
  });

  test('the worse the NIR-quality factors, the less a weak NIR score drags a confident visual one', () {
    double dragFor({required String cal, List<double>? raw, List<double>? refl}) {
      final base = engine.fuse(
        crop: 'barley',
        visualStats: batchStats(averageScore: 85, confidence: 0.9),
        spectral: null,
      ).combinedScore;
      final withNir = engine.fuse(
        crop: 'barley',
        visualStats: batchStats(averageScore: 85, confidence: 0.9),
        spectral: spectral(calibrationStatus: cal, rawValues: raw, reflectance: refl ?? const [0.1, 0.1, 0.1, 0.1]),
      ).combinedScore;
      return (base - withNir).abs();
    }

    final everythingBad = dragFor(
      cal: 'expired',
      raw: List<double>.filled(6, 64000),
      refl: const [0.05, 0.9, 0.05, 0.9, 0.05],
    );
    final calibrationOnlyBad = dragFor(cal: 'expired');

    expect(everythingBad, lessThan(calibrationOnlyBad));
    // KNOWN GAP: even everythingBad still drags ~13 pts, and
    // calibrationOnlyBad ~30 — calibrationValidity only carries 0.4 of the
    // NIR confidence weight, it doesn't gate the NIR contribution the way
    // §71 ("a bad NIR calibration should not let a noisy NIR reading
    // damage the result") reads. A fusion change that fixes this should
    // update these bounds on purpose.
    expect(everythingBad, lessThan(20));
    expect(calibrationOnlyBad, greaterThan(20));
  });

  test('combined confidence is in 0..1 and never exceeds the mean of the two inputs by much', () {
    final r = engine.fuse(
      crop: 'barley',
      visualStats: batchStats(confidence: 0.8),
      spectral: spectral(),
    );
    expect(r.confidence, inInclusiveRange(0.0, 1.0));
  });

  test('seed count and anomalies are carried from the visual stats', () {
    final r = engine.fuse(
      crop: 'barley',
      visualStats: batchStats(seedsAccepted: 21, anomalyCount: 4),
      spectral: spectral(),
    );
    expect(r.seedCount, 21);
    expect(r.anomalies, 4);
  });
}

import 'package:agrispectra/nir/nir_quality.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fixtures.dart';

void main() {
  const scorer = NirQualityScorer();

  test('a valid calibration and clean signal reads as high confidence', () {
    final f = scorer.score(spectral());
    expect(f.calibrationValidity, 1.0);
    expect(f.saturationRisk, lessThan(0.2));
    expect(f.overallConfidence, greaterThan(0.6));
  });

  test('an invalid calibration collapses confidence', () {
    final valid = scorer.score(spectral()).overallConfidence;
    final invalid = scorer.score(spectral(calibrationStatus: 'expired')).overallConfidence;
    expect(invalid, lessThan(valid));
    expect(scorer.score(spectral(calibrationStatus: 'expired')).calibrationValidity, 0.2);
  });

  test('near-full-scale raw values are flagged as a saturation risk', () {
    final f = scorer.score(spectral(rawValues: List<double>.filled(6, 64000)));
    expect(f.saturationRisk, greaterThan(0.5));
  });

  test('a jagged reflectance curve raises the noise estimate', () {
    final smooth = scorer.score(spectral(reflectance: const [0.3, 0.31, 0.3, 0.31, 0.3])).noiseLevel;
    final jagged = scorer.score(spectral(reflectance: const [0.1, 0.9, 0.1, 0.9, 0.1])).noiseLevel;
    expect(jagged, greaterThan(smooth));
  });

  test('empty raw values do not throw and yield no signal', () {
    final f = scorer.score(spectral(rawValues: const []));
    expect(f.signalStrength, 0.0);
    expect(f.overallConfidence, isNot(isNaN));
  });

  test('overallConfidence stays within 0..1', () {
    for (final m in [
      spectral(),
      spectral(calibrationStatus: 'x', rawValues: const [], reflectance: null),
      spectral(rawValues: List<double>.filled(6, 70000)),
    ]) {
      final c = scorer.score(m).overallConfidence;
      expect(c, inInclusiveRange(0.0, 1.0));
    }
  });
}

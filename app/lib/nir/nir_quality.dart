import '../domain/entities/spectral_measurement.dart';

/// Per-reading NIR sensor quality assessment (§72). Distinct from the
/// fusion engine's blend logic — this only asks "how much should we trust
/// *this specific reading*", independent of what the vision pipeline said.
class NirQualityFactors {
  final double calibrationValidity;
  final double signalStrength;
  final double noiseLevel;
  final double saturationRisk;
  final double overallConfidence;

  const NirQualityFactors({
    required this.calibrationValidity,
    required this.signalStrength,
    required this.noiseLevel,
    required this.saturationRisk,
    required this.overallConfidence,
  });
}

class NirQualityScorer {
  const NirQualityScorer();

  NirQualityFactors score(SpectralMeasurement m) {
    final calibrationValidity = m.calibrationStatus == 'valid' ? 1.0 : 0.2;

    final raw = m.rawValues;
    final avgRaw = raw.isEmpty ? 0 : raw.reduce((a, b) => a + b) / raw.length;
    // The AS7265x channels saturate near the top of their ADC range;
    // treat readings above 95% of a nominal ~65535 full-scale as a
    // saturation risk signal rather than a trustworthy peak reading.
    const nominalFullScale = 65535;
    final saturationRisk = (avgRaw / nominalFullScale).clamp(0.0, 1.0) > 0.95 ? 0.9 : 0.05;

    final signalStrength = raw.isEmpty
        ? 0.0
        : (avgRaw / (nominalFullScale * 0.2)).clamp(0.0, 1.0); // expect useful signal well below saturation

    double noiseLevel = 0.1;
    if (m.reflectance != null && m.reflectance!.length > 2) {
      final r = m.reflectance!;
      double diffSum = 0;
      for (var i = 1; i < r.length; i++) {
        diffSum += (r[i] - r[i - 1]).abs();
      }
      // High channel-to-channel jitter on a physically smooth reflectance
      // curve suggests noise rather than real spectral structure.
      noiseLevel = (diffSum / (r.length - 1)).clamp(0.0, 1.0);
    }

    final overallConfidence = (calibrationValidity * 0.4 +
            signalStrength * 0.25 +
            (1 - noiseLevel) * 0.2 +
            (1 - saturationRisk) * 0.15)
        .clamp(0.0, 1.0);

    return NirQualityFactors(
      calibrationValidity: calibrationValidity,
      signalStrength: signalStrength,
      noiseLevel: noiseLevel,
      saturationRisk: saturationRisk,
      overallConfidence: overallConfidence,
    );
  }
}

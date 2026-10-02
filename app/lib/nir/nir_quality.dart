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
    final saturationFraction = (avgRaw / nominalFullScale).clamp(0.0, 1.0);
    final saturationRisk = saturationFraction > 0.95 ? 0.9 : 0.05;

    // Signal strength ramps up with raw level, but once the channels are
    // into saturation (see saturationRisk) the reading is clipped, not
    // strong — so strength falls back off toward zero instead of pinning at
    // full-scale. §66: this is a screening signal only, not an invented
    // calibration curve.
    final signalStrength = raw.isEmpty
        ? 0.0
        : saturationFraction > 0.95
            ? (1.0 - saturationFraction).clamp(0.0, 1.0)
            : (avgRaw / (nominalFullScale * 0.2)).clamp(0.0, 1.0); // useful signal well below saturation

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

    // §71: "excellent imagery with a bad NIR calibration should not let a
    // noisy NIR reading damage the result." calibrationValidity is applied
    // *multiplicatively*, not as one term in a weighted sum — an invalid
    // (expired / unknown) calibration is 0.2 and collapses the whole NIR
    // confidence, so the fusion engine (which uses this as the NIR arm's
    // weight) all but drops the NIR contribution however clean the raw
    // signal looks. The inner weights sum to 1.0 so a valid calibration
    // with a perfect signal still reaches 1.0.
    const signalWeight = 0.42;
    const noiseWeight = 0.33;
    const saturationWeight = 0.25;
    final overallConfidence = (calibrationValidity *
            (signalStrength * signalWeight +
                (1 - noiseLevel) * noiseWeight +
                (1 - saturationRisk) * saturationWeight))
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

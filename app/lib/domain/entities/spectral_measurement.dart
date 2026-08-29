/// A raw + corrected NIR reading (§32, §33). Wavelengths/values are
/// parallel arrays of discrete channels — the AS7265x is not a continuous
/// spectrometer, so this must never be treated as a continuous curve.
///
/// Raw values, dark reference, and white reference are always retained
/// alongside the corrected reflectance (§33: "never throw away raw
/// measurements").
class SpectralMeasurement {
  final String scanId;
  final String deviceId;
  final DateTime timestamp;

  final List<double> wavelengthsNm;
  final List<double> rawValues;
  final List<double>? darkReference;
  final List<double>? whiteReference;

  /// R(λ) = (I_sample - I_dark) / (I_white - I_dark), computed only when
  /// both references are present and non-degenerate. Null otherwise —
  /// never silently fabricated.
  final List<double>? reflectance;

  final double integrationTimeMs;
  final double? temperatureC;
  final double? humidityPercent;

  final bool isSimulated;
  final String calibrationStatus;

  const SpectralMeasurement({
    required this.scanId,
    required this.deviceId,
    required this.timestamp,
    required this.wavelengthsNm,
    required this.rawValues,
    required this.darkReference,
    required this.whiteReference,
    required this.reflectance,
    required this.integrationTimeMs,
    required this.temperatureC,
    required this.humidityPercent,
    required this.isSimulated,
    required this.calibrationStatus,
  });

  Map<String, Object?> toJson() => {
        'scan_id': scanId,
        'device_id': deviceId,
        'timestamp': timestamp.toIso8601String(),
        'wavelengths': wavelengthsNm,
        'raw_values': rawValues,
        'dark': darkReference,
        'white': whiteReference,
        'reflectance': reflectance,
        'integration_time_ms': integrationTimeMs,
        'temperature_c': temperatureC,
        'humidity_percent': humidityPercent,
        'is_simulated': isSimulated,
        'calibration_status': calibrationStatus,
      };
}

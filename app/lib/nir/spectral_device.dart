import '../domain/entities/nir_device_info.dart';
import '../domain/entities/spectral_measurement.dart';

/// The seam between the app and any NIR hardware (§28, §52). Everything
/// above this interface — screens, the fusion engine, the database schema —
/// is written against `SpectralDevice` and must never assume a specific
/// implementation is active.
///
/// Implementations, in delivery order:
///  - [NoNIRDevice]        — always available; camera-only mode.
///  - `SimulatedNIRDevice` — generates clearly-labeled synthetic data so the
///                           fusion UI/model can be built pre-hardware.
///  - `BluetoothNIRDevice` — real ESP32 + AS7265x hardware over BLE GATT.
abstract class SpectralDevice {
  String get deviceId;
  String get displayName;

  /// True for any device that does not represent real hardware readings.
  /// The UI must never present [isSimulated] data as a real measurement
  /// (§30).
  bool get isSimulated;

  Stream<NirDeviceInfo> get status;

  Future<void> connect();
  Future<void> disconnect();
  Future<NirDeviceInfo> getStatus();

  /// Begins a scan session; measurements arrive via [subscribeToMeasurements].
  Future<void> startScan();
  Future<void> stopScan();

  /// Runs (or returns the cached result of) the dark/white reference
  /// calibration sequence (§33, §74). Returns null if calibration has never
  /// been performed on this device.
  Future<CalibrationState?> getCalibration();

  Future<SpectralMeasurement> getMeasurement(String scanId);

  Stream<SpectralMeasurement> subscribeToMeasurements();

  Future<void> dispose();
}

class CalibrationState {
  final DateTime calibratedAt;
  final List<double> darkReference;
  final List<double> whiteReference;
  final bool isValid;

  const CalibrationState({
    required this.calibratedAt,
    required this.darkReference,
    required this.whiteReference,
    required this.isValid,
  });
}

/// Thrown when a connected device reports a [NirDeviceInfo.protocolVersion]
/// this app doesn't understand (§34: "must gracefully reject unsupported
/// protocol versions"). Callers should catch this and fall back to
/// camera-only mode rather than crash.
class UnsupportedProtocolVersionException implements Exception {
  final int reportedVersion;
  final int supportedVersion;
  const UnsupportedProtocolVersionException(this.reportedVersion, this.supportedVersion);

  @override
  String toString() =>
      'Unsupported NIR protocol version $reportedVersion (app supports $supportedVersion)';
}

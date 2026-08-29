import '../domain/entities/nir_device_info.dart';
import '../domain/entities/spectral_measurement.dart';
import 'spectral_device.dart';

/// The default device: represents "no NIR hardware connected." Every
/// AgriSpectra install ships with this active until the user pairs a real
/// or simulated device — camera-only analysis must work with exactly this
/// implementation and nothing else (§36 graceful degradation).
class NoNIRDevice implements SpectralDevice {
  @override
  String get deviceId => 'none';

  @override
  String get displayName => 'No NIR Device';

  @override
  bool get isSimulated => false;

  @override
  Stream<NirDeviceInfo> get status => Stream.value(_info);

  NirDeviceInfo get _info => const NirDeviceInfo(
        deviceId: 'none',
        displayName: 'No NIR Device',
        status: NirConnectionStatus.disconnected,
        isSimulated: false,
      );

  @override
  Future<void> connect() async {}

  @override
  Future<void> disconnect() async {}

  @override
  Future<NirDeviceInfo> getStatus() async => _info;

  @override
  Future<void> startScan() async {
    throw StateError('No NIR device connected — cannot start a spectral scan.');
  }

  @override
  Future<void> stopScan() async {}

  @override
  Future<CalibrationState?> getCalibration() async => null;

  @override
  Future<SpectralMeasurement> getMeasurement(String scanId) {
    throw StateError('No NIR device connected — no measurement available.');
  }

  @override
  Stream<SpectralMeasurement> subscribeToMeasurements() => const Stream.empty();

  @override
  Future<void> dispose() async {}
}

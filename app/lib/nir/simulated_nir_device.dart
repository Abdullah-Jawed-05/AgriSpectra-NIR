import 'dart:async';
import 'dart:math';

import '../core/constants/app_constants.dart';
import '../domain/entities/nir_device_info.dart';
import '../domain/entities/spectral_measurement.dart';
import 'spectral_device.dart';

/// Preset spectral "personalities" the simulator can produce. These are
/// synthetic shapes chosen to be plausible and demonstrate the fusion UI —
/// they are NOT derived from real seed spectroscopy measurements and must
/// never be presented as such (§30).
enum SimulatedSeedProfile { goodSeed, agedSeed, moistureStressed, damagedSeed, unknown }

/// A software stand-in for a physical AgriSpectra NIR device (§30). It
/// exists to let the fusion architecture, UI, and result screens be built
/// and demoed before the physical ESP32 + AS7265x prototype exists.
///
/// The 18 wavelength channels below are the real AS7265x "Triad" channel
/// centers (three 6-channel sensors: AS72651 410-535nm, AS72652 560-705nm,
/// AS72653 730-940nm) — not invented values — because the discrete-channel
/// shape of this data is architecturally important even in simulation
/// (§31/§32: the app must never assume a continuous spectrum).
class SimulatedNIRDevice implements SpectralDevice {
  SimulatedNIRDevice({Random? random}) : _random = random ?? Random();

  final Random _random;
  final _statusController = StreamController<NirDeviceInfo>.broadcast();
  final _measurementController = StreamController<SpectralMeasurement>.broadcast();

  NirConnectionStatus _connectionStatus = NirConnectionStatus.disconnected;
  CalibrationState? _calibration;
  SimulatedSeedProfile profile = SimulatedSeedProfile.goodSeed;

  static const List<double> wavelengthsNm = [
    410, 435, 460, 485, 510, 535, // AS72651
    560, 585, 610, 645, 680, 705, // AS72652
    730, 760, 810, 860, 900, 940, // AS72653
  ];

  @override
  String get deviceId => 'sim-nir-001';

  @override
  String get displayName => 'AgriSpectra-NIR (Simulated)';

  @override
  bool get isSimulated => true;

  @override
  Stream<NirDeviceInfo> get status => _statusController.stream;

  NirDeviceInfo get _info => NirDeviceInfo(
        deviceId: deviceId,
        displayName: displayName,
        status: _connectionStatus,
        isSimulated: true,
        firmwareVersion: 'sim-0.1.0',
        hardwareRevision: 'simulated',
        protocolVersion: AppVersions.nirProtocolVersion,
        batteryPercent: 100,
        lastCalibrationAt: _calibration?.calibratedAt,
      );

  void _emitStatus() {
    if (!_statusController.isClosed) _statusController.add(_info);
  }

  @override
  Future<void> connect() async {
    _connectionStatus = NirConnectionStatus.connecting;
    _emitStatus();
    await Future.delayed(const Duration(milliseconds: 400));
    _connectionStatus = NirConnectionStatus.connected;
    _emitStatus();
  }

  @override
  Future<void> disconnect() async {
    _connectionStatus = NirConnectionStatus.disconnected;
    _emitStatus();
  }

  @override
  Future<NirDeviceInfo> getStatus() async => _info;

  @override
  Future<void> startScan() async {
    if (_connectionStatus != NirConnectionStatus.connected) {
      throw StateError('Simulated NIR device is not connected.');
    }
  }

  @override
  Future<void> stopScan() async {}

  @override
  Future<CalibrationState?> getCalibration() async => _calibration;

  /// Runs a synthetic dark + white reference calibration. Real hardware
  /// would require the physical steps in §74; here it's instantaneous but
  /// still stores a timestamped [CalibrationState] so downstream code
  /// (reflectance calculation, "last calibrated" UI) behaves identically
  /// to the real device.
  Future<CalibrationState> runCalibration() async {
    final dark = wavelengthsNm.map((_) => 200 + _random.nextDouble() * 20).toList();
    final white = wavelengthsNm.map((_) => 3000 + _random.nextDouble() * 200).toList();
    _calibration = CalibrationState(
      calibratedAt: DateTime.now(),
      darkReference: dark,
      whiteReference: white,
      isValid: true,
    );
    return _calibration!;
  }

  @override
  Future<SpectralMeasurement> getMeasurement(String scanId) async {
    final calibration = _calibration ?? await runCalibration();

    final raw = <double>[];
    final reflectance = <double>[];

    for (var i = 0; i < wavelengthsNm.length; i++) {
      final wavelength = wavelengthsNm[i];
      final baseReflectance = _profileReflectanceAt(wavelength, profile);
      final noisy = (baseReflectance + _gaussianNoise() * 0.02).clamp(0.01, 0.99);

      final dark = calibration.darkReference[i];
      final white = calibration.whiteReference[i];
      final signal = dark + noisy * (white - dark);

      raw.add(signal);

      final denom = white - dark;
      reflectance.add(denom.abs() < 1e-6 ? 0 : ((signal - dark) / denom).clamp(0.0, 1.0));
    }

    final measurement = SpectralMeasurement(
      scanId: scanId,
      deviceId: deviceId,
      timestamp: DateTime.now(),
      wavelengthsNm: wavelengthsNm,
      rawValues: raw,
      darkReference: calibration.darkReference,
      whiteReference: calibration.whiteReference,
      reflectance: reflectance,
      integrationTimeMs: 50,
      temperatureC: 24 + _random.nextDouble() * 4,
      humidityPercent: 40 + _random.nextDouble() * 15,
      isSimulated: true,
      calibrationStatus: calibration.isValid ? 'valid' : 'invalid',
    );

    if (!_measurementController.isClosed) _measurementController.add(measurement);
    return measurement;
  }

  @override
  Stream<SpectralMeasurement> subscribeToMeasurements() => _measurementController.stream;

  double _gaussianNoise() {
    // Box-Muller transform from two uniform samples.
    final u1 = 1 - _random.nextDouble();
    final u2 = _random.nextDouble();
    return sqrt(-2 * log(u1)) * cos(2 * pi * u2);
  }

  /// A hand-authored, plausible reflectance shape per profile. These curves
  /// are illustrative (e.g. "moisture-stressed" dips near the 900-940nm
  /// water-absorption region) and exist to make the fusion pipeline and UI
  /// demonstrable — see the class doc comment for the honesty constraint.
  double _profileReflectanceAt(double wavelengthNm, SimulatedSeedProfile profile) {
    final t = (wavelengthNm - 410) / (940 - 410); // 0..1 across the range
    switch (profile) {
      case SimulatedSeedProfile.goodSeed:
        return 0.55 + 0.15 * t;
      case SimulatedSeedProfile.agedSeed:
        return 0.5 + 0.05 * t;
      case SimulatedSeedProfile.moistureStressed:
        final waterDip = exp(-pow((wavelengthNm - 920) / 40, 2)) * 0.25;
        return (0.55 + 0.15 * t) - waterDip;
      case SimulatedSeedProfile.damagedSeed:
        return 0.35 + 0.05 * t + (_random.nextDouble() - 0.5) * 0.1;
      case SimulatedSeedProfile.unknown:
        return 0.3 + 0.3 * _random.nextDouble();
    }
  }

  @override
  Future<void> dispose() async {
    await _statusController.close();
    await _measurementController.close();
  }
}

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import '../core/constants/app_constants.dart';
import '../domain/entities/nir_device_info.dart';
import '../domain/entities/spectral_measurement.dart';
import 'simulated_nir_device.dart' show SimulatedNIRDevice;
import 'spectral_device.dart';

/// Real hardware implementation of [SpectralDevice] over BLE GATT, per
/// `nir_protocol/protocol.md`. No physical AgriSpectra NIR device exists
/// yet (see docs/ARCHITECTURE.md §10), so this class has never been
/// integration-tested against real firmware — the byte-level parsing
/// matches the protocol doc exactly and should work once hardware exists,
/// but treat it as unverified until then. It is not wired into the app's
/// default device list; `NoNIRDevice` and `SimulatedNIRDevice` are.
class BluetoothNIRDevice implements SpectralDevice {
  BluetoothNIRDevice(this._device);

  final BluetoothDevice _device;

  static final Guid serviceUuid = Guid('6e400001-b5a3-f393-e0a9-e50e24dcca9e');
  static final Guid deviceInfoCharUuid = Guid('6e400010-b5a3-f393-e0a9-e50e24dcca9e');
  static final Guid calibrationCharUuid = Guid('6e400011-b5a3-f393-e0a9-e50e24dcca9e');
  static final Guid scanControlCharUuid = Guid('6e400012-b5a3-f393-e0a9-e50e24dcca9e');
  static final Guid spectralDataCharUuid = Guid('6e400013-b5a3-f393-e0a9-e50e24dcca9e');
  static final Guid environmentalCharUuid = Guid('6e400014-b5a3-f393-e0a9-e50e24dcca9e');
  static final Guid batteryCharUuid = Guid('6e400015-b5a3-f393-e0a9-e50e24dcca9e');
  static final Guid deviceStatusCharUuid = Guid('6e400016-b5a3-f393-e0a9-e50e24dcca9e');

  static const List<double> wavelengthsNm = SimulatedNIRDevice.wavelengthsNm;

  final _statusController = StreamController<NirDeviceInfo>.broadcast();
  final _measurementController = StreamController<SpectralMeasurement>.broadcast();

  BluetoothCharacteristic? _spectralChar;
  BluetoothCharacteristic? _environmentalChar;
  BluetoothCharacteristic? _calibrationChar;
  BluetoothCharacteristic? _scanControlChar;

  StreamSubscription<List<int>>? _spectralSub;
  StreamSubscription<List<int>>? _environmentalSub;

  double? _lastTemperatureC;
  double? _lastHumidityPercent;
  CalibrationState? _calibration;

  String? _reportedFirmwareVersion;
  String? _reportedHardwareRevision;

  /// Scans for BLE peripherals advertising [serviceUuid]. Callers should
  /// present the results and let the user pick one — this does not
  /// auto-connect.
  static Stream<List<ScanResult>> discover({Duration timeout = const Duration(seconds: 8)}) {
    FlutterBluePlus.startScan(withServices: [serviceUuid], timeout: timeout);
    return FlutterBluePlus.scanResults;
  }

  static Future<void> stopDiscovery() => FlutterBluePlus.stopScan();

  @override
  String get deviceId => _device.remoteId.str;

  @override
  String get displayName => _device.platformName.isNotEmpty ? _device.platformName : 'AgriSpectra-NIR';

  @override
  bool get isSimulated => false;

  @override
  Stream<NirDeviceInfo> get status => _statusController.stream;

  void _emitStatus(NirConnectionStatus connectionStatus) {
    if (_statusController.isClosed) return;
    _statusController.add(NirDeviceInfo(
      deviceId: deviceId,
      displayName: displayName,
      status: connectionStatus,
      isSimulated: false,
      firmwareVersion: _reportedFirmwareVersion,
      hardwareRevision: _reportedHardwareRevision,
      protocolVersion: AppVersions.nirProtocolVersion,
      lastCalibrationAt: _calibration?.calibratedAt,
    ));
  }

  @override
  Future<void> connect() async {
    _emitStatus(NirConnectionStatus.connecting);
    // License.nonprofit: this is a hackathon/educational prototype, not a
    // commercial product — see the LICENSE terms in the flutter_blue_plus
    // package for what requires License.commercial instead.
    await _device.connect(license: License.nonprofit, timeout: const Duration(seconds: 10));

    final services = await _device.discoverServices();
    final service = services.firstWhere(
      (s) => s.uuid == serviceUuid,
      orElse: () => throw StateError('Device does not advertise the AgriSpectra Sensor Service.'),
    );

    for (final char in service.characteristics) {
      if (char.uuid == deviceInfoCharUuid) {
        await _readDeviceInfo(char);
      } else if (char.uuid == spectralDataCharUuid) {
        _spectralChar = char;
      } else if (char.uuid == environmentalCharUuid) {
        _environmentalChar = char;
      } else if (char.uuid == calibrationCharUuid) {
        _calibrationChar = char;
      } else if (char.uuid == scanControlCharUuid) {
        _scanControlChar = char;
      }
    }

    if (_reportedProtocolVersion != null &&
        _reportedProtocolVersion != AppVersions.nirProtocolVersion) {
      await disconnect();
      throw UnsupportedProtocolVersionException(
        _reportedProtocolVersion!,
        AppVersions.nirProtocolVersion,
      );
    }

    if (_spectralChar != null) {
      await _spectralChar!.setNotifyValue(true);
      _spectralSub = _spectralChar!.onValueReceived.listen(_onSpectralNotification);
    }
    if (_environmentalChar != null) {
      await _environmentalChar!.setNotifyValue(true);
      _environmentalSub = _environmentalChar!.onValueReceived.listen(_onEnvironmentalNotification);
    }

    _emitStatus(NirConnectionStatus.connected);
  }

  int? _reportedProtocolVersion;

  Future<void> _readDeviceInfo(BluetoothCharacteristic char) async {
    final bytes = await char.read();
    if (bytes.length < 33) return;
    _reportedProtocolVersion = bytes[0];
    _reportedFirmwareVersion = _decodePaddedUtf8(bytes.sublist(17, 25));
    _reportedHardwareRevision = _decodePaddedUtf8(bytes.sublist(25, 33));
  }

  String _decodePaddedUtf8(List<int> bytes) {
    final end = bytes.indexOf(0);
    return utf8.decode(bytes.sublist(0, end == -1 ? bytes.length : end));
  }

  @override
  Future<void> disconnect() async {
    await _spectralSub?.cancel();
    await _environmentalSub?.cancel();
    await _device.disconnect();
    _emitStatus(NirConnectionStatus.disconnected);
  }

  @override
  Future<NirDeviceInfo> getStatus() async => NirDeviceInfo(
        deviceId: deviceId,
        displayName: displayName,
        status: _device.isConnected ? NirConnectionStatus.connected : NirConnectionStatus.disconnected,
        isSimulated: false,
        firmwareVersion: _reportedFirmwareVersion,
        hardwareRevision: _reportedHardwareRevision,
        protocolVersion: AppVersions.nirProtocolVersion,
        lastCalibrationAt: _calibration?.calibratedAt,
      );

  @override
  Future<void> startScan() async {
    final char = _scanControlChar;
    if (char == null) throw StateError('Scan control characteristic not available.');
    await char.write([0x01], withoutResponse: false);
  }

  @override
  Future<void> stopScan() async {
    final char = _scanControlChar;
    if (char == null) return;
    await char.write([0x00], withoutResponse: false);
  }

  @override
  Future<CalibrationState?> getCalibration() async => _calibration;

  /// Drives the two-step dark/white reference capture (§33, §74) over the
  /// Calibration Control characteristic and waits for both reference
  /// readings to arrive as `measurement_type = 0xFF` spectral
  /// notifications.
  Future<CalibrationState> runCalibration() async {
    final char = _calibrationChar;
    if (char == null) throw StateError('Calibration characteristic not available.');

    await char.write([0x01], withoutResponse: false); // start dark capture
    final dark = await _awaitCalibrationFrame();
    await char.write([0x02], withoutResponse: false); // start white capture
    final white = await _awaitCalibrationFrame();

    _calibration = CalibrationState(
      calibratedAt: DateTime.now(),
      darkReference: dark,
      whiteReference: white,
      isValid: true,
    );
    return _calibration!;
  }

  final _calibrationFrameController = StreamController<List<double>>.broadcast();

  Future<List<double>> _awaitCalibrationFrame({Duration timeout = const Duration(seconds: 15)}) {
    return _calibrationFrameController.stream.first.timeout(timeout);
  }

  void _onSpectralNotification(List<int> raw) {
    if (raw.length < 73) return;
    final bytes = Uint8List.fromList(raw);
    final data = ByteData.sublistView(bytes);

    final measurementType = bytes[0];
    final integrationTimeMs = data.getFloat32(1, Endian.little);

    final values = <double>[];
    for (var i = 0; i < wavelengthsNm.length; i++) {
      values.add(data.getFloat32(5 + i * 4, Endian.little));
    }

    if (measurementType == 0xFF) {
      _calibrationFrameController.add(values);
      return;
    }

    final calibration = _calibration;
    List<double>? reflectance;
    if (calibration != null) {
      reflectance = List.generate(values.length, (i) {
        final denom = calibration.whiteReference[i] - calibration.darkReference[i];
        if (denom.abs() < 1e-6) return 0.0;
        return ((values[i] - calibration.darkReference[i]) / denom).clamp(0.0, 1.0);
      });
    }

    final measurement = SpectralMeasurement(
      scanId: _pendingScanId ?? 'unknown',
      deviceId: deviceId,
      timestamp: DateTime.now(),
      wavelengthsNm: wavelengthsNm,
      rawValues: values,
      darkReference: calibration?.darkReference,
      whiteReference: calibration?.whiteReference,
      reflectance: reflectance,
      integrationTimeMs: integrationTimeMs,
      temperatureC: _lastTemperatureC,
      humidityPercent: _lastHumidityPercent,
      isSimulated: false,
      calibrationStatus: calibration != null ? 'valid' : 'uncalibrated',
    );

    if (!_measurementController.isClosed) _measurementController.add(measurement);
  }

  void _onEnvironmentalNotification(List<int> raw) {
    if (raw.length < 8) return;
    final data = ByteData.sublistView(Uint8List.fromList(raw));
    _lastTemperatureC = data.getFloat32(0, Endian.little);
    _lastHumidityPercent = data.getFloat32(4, Endian.little);
  }

  String? _pendingScanId;

  @override
  Future<SpectralMeasurement> getMeasurement(String scanId) async {
    _pendingScanId = scanId;
    await startScan();
    return _measurementController.stream.first.timeout(const Duration(seconds: 20));
  }

  @override
  Stream<SpectralMeasurement> subscribeToMeasurements() => _measurementController.stream;

  @override
  Future<void> dispose() async {
    await _spectralSub?.cancel();
    await _environmentalSub?.cancel();
    await _statusController.close();
    await _measurementController.close();
    await _calibrationFrameController.close();
  }
}

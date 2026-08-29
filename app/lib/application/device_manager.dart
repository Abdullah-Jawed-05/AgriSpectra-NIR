import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/entities/nir_device_info.dart';
import '../nir/no_nir_device.dart';
import '../nir/simulated_nir_device.dart';
import '../nir/spectral_device.dart';

/// Owns the single active [SpectralDevice] for the whole app (§28/§52 —
/// screens and the analysis pipeline depend only on this interface).
/// Starts as [NoNIRDevice]; the NIR Device screen can switch it to the
/// simulator or (once paired) a real `BluetoothNIRDevice`.
class DeviceManager extends Notifier<NirDeviceInfo> {
  SpectralDevice _device = NoNIRDevice();
  StreamSubscription<NirDeviceInfo>? _statusSub;

  SpectralDevice get device => _device;

  @override
  NirDeviceInfo build() {
    ref.onDispose(() {
      _statusSub?.cancel();
      _device.dispose();
    });
    _listen();
    return const NirDeviceInfo(
      deviceId: 'none',
      displayName: 'No NIR Device',
      status: NirConnectionStatus.disconnected,
      isSimulated: false,
    );
  }

  void _listen() {
    _statusSub?.cancel();
    _statusSub = _device.status.listen((info) => state = info);
  }

  Future<void> useSimulatedDevice() async {
    await _device.dispose();
    _device = SimulatedNIRDevice();
    _listen();
    await _device.connect();
  }

  Future<void> useNoDevice() async {
    await _device.dispose();
    _device = NoNIRDevice();
    _listen();
    state = await _device.getStatus();
  }

  /// Swaps in an already-constructed device (e.g. a `BluetoothNIRDevice`
  /// after the user picks one from a BLE scan result) and connects it.
  Future<void> useDevice(SpectralDevice device) async {
    await _device.dispose();
    _device = device;
    _listen();
    await _device.connect();
  }

  SimulatedNIRDevice? get simulatedDeviceOrNull =>
      _device is SimulatedNIRDevice ? _device as SimulatedNIRDevice : null;
}

final deviceManagerProvider = NotifierProvider<DeviceManager, NirDeviceInfo>(DeviceManager.new);

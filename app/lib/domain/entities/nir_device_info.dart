enum NirConnectionStatus { disconnected, scanning, connecting, connected, error }

/// Device registration metadata (§75). Populated by whichever
/// [SpectralDevice] implementation is active — `NoNIRDevice` reports
/// [NirConnectionStatus.disconnected] with everything else null.
class NirDeviceInfo {
  final String deviceId;
  final String displayName;
  final NirConnectionStatus status;
  final String? firmwareVersion;
  final String? hardwareRevision;
  final int? protocolVersion;
  final double? batteryPercent;
  final DateTime? lastCalibrationAt;
  final bool isSimulated;

  const NirDeviceInfo({
    required this.deviceId,
    required this.displayName,
    required this.status,
    required this.isSimulated,
    this.firmwareVersion,
    this.hardwareRevision,
    this.protocolVersion,
    this.batteryPercent,
    this.lastCalibrationAt,
  });

  NirDeviceInfo copyWith({
    NirConnectionStatus? status,
    double? batteryPercent,
    DateTime? lastCalibrationAt,
  }) =>
      NirDeviceInfo(
        deviceId: deviceId,
        displayName: displayName,
        status: status ?? this.status,
        isSimulated: isSimulated,
        firmwareVersion: firmwareVersion,
        hardwareRevision: hardwareRevision,
        protocolVersion: protocolVersion,
        batteryPercent: batteryPercent ?? this.batteryPercent,
        lastCalibrationAt: lastCalibrationAt ?? this.lastCalibrationAt,
      );
}

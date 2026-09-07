import 'dart:math';
import 'dart:typed_data';

import 'package:agrispectra/application/scan_orchestrator.dart';
import 'package:agrispectra/database/app_database.dart';
import 'package:agrispectra/database/daos/scan_dao.dart';
import 'package:agrispectra/domain/entities/fusion_result.dart';
import 'package:agrispectra/domain/entities/nir_device_info.dart';
import 'package:agrispectra/domain/entities/spectral_measurement.dart';
import 'package:agrispectra/nir/no_nir_device.dart';
import 'package:agrispectra/nir/spectral_device.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../support/fixtures.dart';

/// A plain grey frame with four dark elongated blobs — passes the quality
/// gate and gives the classical detector real seeds to segment.
Uint8List _syntheticScan() {
  final rng = Random(7);
  final image = img.Image(width: 1280, height: 960);
  for (final p in image) {
    final v = 210 + rng.nextInt(3) - 1; // faint, non-periodic — passes the texture gate
    p.setRgb(v, v, v);
  }
  // A grid of well-separated, hard-edged dark blobs: seed-sized, and their
  // sharp edges give the blur check enough high-frequency energy to pass.
  for (var gy = 0; gy < 3; gy++) {
    for (var gx = 0; gx < 5; gx++) {
      img.fillCircle(
        image,
        x: 180 + gx * 230,
        y: 210 + gy * 270,
        radius: 34,
        color: img.ColorRgb8(28, 28, 28),
      );
    }
  }
  return img.encodePng(image);
}

/// [SpectralDevice] test double. [status] drives the orchestrator's
/// "is it connected" check; [onMeasurement] lets a test blow up mid-scan.
class _FakeNir implements SpectralDevice {
  _FakeNir({required this.connected, this.throwOnScan = false});
  final bool connected;
  final bool throwOnScan;

  @override
  String get deviceId => 'fake_nir';
  @override
  String get displayName => 'Fake NIR';
  @override
  bool get isSimulated => true;

  @override
  Future<NirDeviceInfo> getStatus() async => NirDeviceInfo(
        deviceId: deviceId,
        displayName: displayName,
        status: connected ? NirConnectionStatus.connected : NirConnectionStatus.disconnected,
        isSimulated: true,
      );

  @override
  Future<void> startScan() async {
    if (throwOnScan) throw StateError('device dropped mid-scan');
  }

  @override
  Future<SpectralMeasurement> getMeasurement(String scanId) async {
    if (throwOnScan) throw StateError('device dropped mid-scan');
    return spectral(scanId: scanId);
  }

  @override
  Stream<NirDeviceInfo> get status => Stream.value(
        NirDeviceInfo(
          deviceId: deviceId,
          displayName: displayName,
          status: connected ? NirConnectionStatus.connected : NirConnectionStatus.disconnected,
          isSimulated: true,
        ),
      );
  @override
  Future<void> connect() async {}
  @override
  Future<void> disconnect() async {}
  @override
  Future<void> stopScan() async {}
  @override
  Future<CalibrationState?> getCalibration() async => null;
  @override
  Stream<SpectralMeasurement> subscribeToMeasurements() => const Stream.empty();
  @override
  Future<void> dispose() async {}
}

void main() {
  final orchestrator = ScanOrchestrator();
  final camera = {'lens': 'wide'};

  test('camera-only: no NIR device -> a cameraOnly scan, no spectral', () async {
    final res = await orchestrator.analyze(
      imageBytes: _syntheticScan(),
      crop: 'barley',
      nirDevice: NoNIRDevice(),
      cameraMetadata: camera,
    );

    expect(res.isOk, isTrue);
    final scan = res.valueOrNull!;
    expect(scan.nirAvailable, isFalse);
    expect(scan.fusionResult.mode, AssessmentMode.cameraOnly);
    expect(scan.numberOfSeeds, greaterThan(0));
  });

  test('a connected NIR device produces a multimodal scan', () async {
    final res = await orchestrator.analyze(
      imageBytes: _syntheticScan(),
      crop: 'barley',
      nirDevice: _FakeNir(connected: true),
      cameraMetadata: camera,
    );

    final scan = res.valueOrNull!;
    expect(scan.nirAvailable, isTrue);
    expect(scan.nirDeviceId, isNotNull); // carried from the measurement
    expect(scan.fusionResult.mode, AssessmentMode.multimodal);
    expect(scan.fusionResult.nirScore, isNotNull);
  });

  test('a NIR device that drops mid-scan does not abort the camera result (§36/§58)', () async {
    final res = await orchestrator.analyze(
      imageBytes: _syntheticScan(),
      crop: 'barley',
      nirDevice: _FakeNir(connected: true, throwOnScan: true),
      cameraMetadata: camera,
    );

    expect(res.isOk, isTrue, reason: 'a mid-scan NIR failure must fall back to camera-only');
    final scan = res.valueOrNull!;
    expect(scan.nirAvailable, isFalse);
    expect(scan.fusionResult.mode, AssessmentMode.cameraOnly);
  });

  test('the assembled scan round-trips through the database intact', () async {
    sqfliteFfiInit();
    final db = await databaseFactoryFfi.openDatabase(
      'file:orch_${DateTime.now().microsecondsSinceEpoch}?mode=memory&cache=shared',
      options: OpenDatabaseOptions(singleInstance: false),
    );
    addTearDown(db.close);
    await AppDatabase.createSchemaForTesting(db);
    final dao = ScanDao(db);

    final scan = (await orchestrator.analyze(
      imageBytes: _syntheticScan(),
      crop: 'barley',
      nirDevice: NoNIRDevice(),
      cameraMetadata: camera,
    ))
        .valueOrNull!;

    await dao.insertScan(scan);
    final loaded = await dao.getScan(scan.scanId);

    expect(loaded, isNotNull);
    expect(loaded!.scanId, scan.scanId);
    expect(loaded.numberOfSeeds, scan.numberOfSeeds);
    expect(loaded.batchStatistics.purityRatio, closeTo(scan.batchStatistics.purityRatio, 1e-9));
    expect(loaded.batchStatistics.impurityCount, scan.batchStatistics.impurityCount);
    expect(loaded.imageQuality.textureScore, closeTo(scan.imageQuality.textureScore, 1e-9));
    // every seed persisted unverified
    for (final s in loaded.results) {
      expect(s.verifiedLabel, isNull);
    }
  });
}

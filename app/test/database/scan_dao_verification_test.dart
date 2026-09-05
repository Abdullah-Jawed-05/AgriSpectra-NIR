import 'dart:typed_data';

import 'package:agrispectra/database/app_database.dart';
import 'package:agrispectra/database/daos/scan_dao.dart';
import 'package:agrispectra/domain/entities/batch_statistics.dart';
import 'package:agrispectra/domain/entities/fusion_result.dart';
import 'package:agrispectra/domain/entities/image_quality_report.dart';
import 'package:agrispectra/domain/entities/quality_prediction.dart';
import 'package:agrispectra/domain/entities/scan.dart';
import 'package:agrispectra/domain/entities/seed_features.dart';
import 'package:agrispectra/domain/entities/seed_result.dart';
import 'package:agrispectra/domain/value_objects/quality_class.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

const _dummyGeometry = GeometryFeatures(
  areaPx: 100, perimeterPx: 40, widthPx: 8, lengthPx: 12,
  aspectRatio: 1.5, circularity: 0.8, eccentricity: 0.5, convexity: 0.9,
);
const _dummyFeatures = SeedFeatures(
  geometry: _dummyGeometry,
  color: ColorFeatures(
    meanR: 100, meanG: 90, meanB: 80, meanHue: 30, meanSaturation: 0.3, meanValue: 0.5,
    meanLabL: 50, meanLabA: 2, meanLabB: 10, colorVarianceRgb: 50, discolorationRatio: 0.1,
  ),
  texture: TextureFeatures(edgeDensity: 0.2, entropy: 0.5, surfaceIrregularity: 0.2, localContrast: 0.3),
  damage: DamageIndicators(darkRegionRatio: 0.05, crackLikeEdgeRatio: 0.2, holeRatio: 0.0, abnormalPigmentationScore: 0.05),
);

SeedResult _seed(String id, String scanId) => SeedResult(
      seedId: id,
      scanId: scanId,
      cropPng: Uint8List.fromList([1, 2, 3]),
      segmentation: const {},
      visualFeatures: _dummyFeatures,
      prediction: const QualityPrediction(
        qualityClass: QualityClass.good,
        score: 80,
        confidence: 0.7,
        evidence: [],
        anomalies: [],
        modelVersion: 'test',
      ),
      confidence: 0.7,
      anomalies: const [],
    );

Scan _scan(String scanId, DateTime timestamp, List<SeedResult> results) => Scan(
      scanId: scanId,
      timestamp: timestamp,
      crop: 'barley',
      cameraMetadata: const {},
      imageQuality: const ImageQualityReport(
        usable: true,
        qualityScore: 0.9,
        blurScore: 0.9,
        exposureScore: 0.9,
        glareScore: 0.9,
        backgroundScore: 0.9,
        warnings: [],
      ),
      numberOfSeeds: results.length,
      batchScore: 80,
      confidence: 0.7,
      visionModelVersion: 'test',
      analysisVersion: 'test',
      nirAvailable: false,
      batchStatistics: const BatchStatistics(
        seedsDetected: 2,
        seedsAccepted: 2,
        seedsRejected: 0,
        averageScore: 80,
        uniformity: 1,
        anomalyCount: 0,
        confidence: 0.7,
        scoreHistogram: [],
        qualityClassCounts: {},
        impurityCount: 0,
        purityRatio: 1,
      ),
      fusionResult: const FusionResult(
        assessmentId: 'a1',
        mode: AssessmentMode.cameraOnly,
        crop: 'barley',
        visualScore: 80,
        nirScore: null,
        combinedScore: 80,
        confidence: 0.7,
        seedCount: 2,
        anomalies: 0,
        modelVersions: {'vision': 'test'},
      ),
      results: results,
    );

void main() {
  late Database db;
  late ScanDao dao;

  setUp(() async {
    sqfliteFfiInit();
    // A fresh, isolated in-memory database per test: sqflite_common_ffi can
    // reuse a cached connection for the bare `:memory:` path across opens
    // in the same process, which would silently carry tables (and data)
    // over between tests. A unique URI per test avoids that entirely.
    db = await databaseFactoryFfi.openDatabase(
      'file:test_${DateTime.now().microsecondsSinceEpoch}?mode=memory&cache=shared',
      options: OpenDatabaseOptions(singleInstance: false),
    );
    await AppDatabase.createSchemaForTesting(db);
    dao = ScanDao(db);
  });

  tearDown(() async {
    await db.close();
  });

  test('a freshly inserted scan leaves every seed unverified', () async {
    await dao.insertScan(_scan('scan_1', DateTime(2026, 9, 5), [_seed('s1', 'scan_1'), _seed('s2', 'scan_1')]));

    expect(await dao.unverifiedSeedCount(), 2);
    final unverified = await dao.unverifiedSeeds();
    expect(unverified.map((s) => s.seedId), containsAll(['s1', 's2']));
    expect(await dao.verifiedSeeds(), isEmpty);
  });

  test('verifySeed moves exactly that seed from unverified to verified', () async {
    await dao.insertScan(_scan('scan_1', DateTime(2026, 9, 5), [_seed('s1', 'scan_1'), _seed('s2', 'scan_1')]));

    await dao.verifySeed('s1', QualityClass.broken);

    expect(await dao.unverifiedSeedCount(), 1);
    final stillUnverified = await dao.unverifiedSeeds();
    expect(stillUnverified.map((s) => s.seedId), equals(['s2']));

    final verified = await dao.verifiedSeeds();
    expect(verified, hasLength(1));
    expect(verified.single.seedId, 's1');
    expect(verified.single.verifiedLabel, QualityClass.broken);
    expect(verified.single.crop, 'barley');
  });

  test('unverifiedSeeds orders oldest scan first', () async {
    await dao.insertScan(_scan('scan_old', DateTime(2026, 9, 1), [_seed('old', 'scan_old')]));
    await dao.insertScan(_scan('scan_new', DateTime(2026, 9, 5), [_seed('new', 'scan_new')]));

    final unverified = await dao.unverifiedSeeds();
    expect(unverified.map((s) => s.seedId), ['old', 'new']);
  });
}

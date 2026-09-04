import 'dart:typed_data';

import 'package:sqflite/sqflite.dart';

import '../../domain/entities/batch_statistics.dart';
import '../../domain/entities/fusion_result.dart';
import '../../domain/entities/image_quality_report.dart';
import '../../domain/entities/quality_prediction.dart';
import '../../domain/entities/scan.dart';
import '../../domain/entities/seed_features.dart';
import '../../domain/entities/seed_result.dart';
import '../../domain/value_objects/quality_class.dart';
import '../app_database.dart';

class ScanDao {
  ScanDao(this._db);
  final Database _db;

  Future<void> insertScan(Scan scan) async {
    await _db.transaction((txn) async {
      await txn.insert('scans', {
        'scan_id': scan.scanId,
        'timestamp': scan.timestamp.toIso8601String(),
        'crop': scan.crop,
        'cultivar': scan.cultivar,
        'location': scan.location,
        'camera_metadata': encodeJson(scan.cameraMetadata),
        'image_quality': encodeJson(scan.imageQuality.toJson()),
        'number_of_seeds': scan.numberOfSeeds,
        'batch_score': scan.batchScore,
        'confidence': scan.confidence,
        'vision_model_version': scan.visionModelVersion,
        'analysis_version': scan.analysisVersion,
        'nir_available': scan.nirAvailable ? 1 : 0,
        'nir_device_id': scan.nirDeviceId,
        'batch_statistics': encodeJson({
          'seeds_detected': scan.batchStatistics.seedsDetected,
          'seeds_accepted': scan.batchStatistics.seedsAccepted,
          'seeds_rejected': scan.batchStatistics.seedsRejected,
          'average_score': scan.batchStatistics.averageScore,
          'uniformity': scan.batchStatistics.uniformity,
          'anomaly_count': scan.batchStatistics.anomalyCount,
          'confidence': scan.batchStatistics.confidence,
          'score_histogram': scan.batchStatistics.scoreHistogram,
          'quality_class_counts': scan.batchStatistics.qualityClassCounts,
          'impurity_count': scan.batchStatistics.impurityCount,
          'purity_ratio': scan.batchStatistics.purityRatio,
        }),
        'fusion_result': encodeJson(scan.fusionResult.toJson()),
      }, conflictAlgorithm: ConflictAlgorithm.replace);

      for (final result in scan.results) {
        await txn.insert('seed_results', {
          'seed_id': result.seedId,
          'scan_id': result.scanId,
          'crop_png': result.cropPng,
          'segmentation': encodeJson(result.segmentation),
          'visual_features': encodeJson(result.visualFeatures.toJson()),
          'prediction': encodeJson(result.prediction.toJson()),
          'confidence': result.confidence,
          'anomalies': encodeJson(result.anomalies),
        }, conflictAlgorithm: ConflictAlgorithm.replace);
      }
    });
  }

  Future<List<ScanSummary>> listScans({String? cropFilter}) async {
    final rows = await _db.query(
      'scans',
      where: cropFilter != null ? 'crop = ?' : null,
      whereArgs: cropFilter != null ? [cropFilter] : null,
      orderBy: 'timestamp DESC',
    );
    return rows.map(ScanSummary._fromRow).toList();
  }

  Future<Scan?> getScan(String scanId) async {
    final scanRows = await _db.query('scans', where: 'scan_id = ?', whereArgs: [scanId]);
    if (scanRows.isEmpty) return null;
    final row = scanRows.first;

    final seedRows = await _db.query('seed_results', where: 'scan_id = ?', whereArgs: [scanId]);
    final results = seedRows.map(_seedResultFromRow).toList();

    final batchJson = decodeJsonMap(row['batch_statistics'] as String);
    final fusionJson = decodeJsonMap(row['fusion_result'] as String);

    return Scan(
      scanId: row['scan_id'] as String,
      timestamp: DateTime.parse(row['timestamp'] as String),
      crop: row['crop'] as String,
      cultivar: row['cultivar'] as String?,
      location: row['location'] as String?,
      cameraMetadata: decodeJsonMap(row['camera_metadata'] as String),
      imageQuality: _qualityFromJson(decodeJsonMap(row['image_quality'] as String)),
      numberOfSeeds: row['number_of_seeds'] as int,
      batchScore: (row['batch_score'] as num).toDouble(),
      confidence: (row['confidence'] as num).toDouble(),
      visionModelVersion: row['vision_model_version'] as String,
      analysisVersion: row['analysis_version'] as String,
      nirAvailable: (row['nir_available'] as int) == 1,
      nirDeviceId: row['nir_device_id'] as String?,
      batchStatistics: BatchStatistics(
        seedsDetected: batchJson['seeds_detected'] as int,
        seedsAccepted: batchJson['seeds_accepted'] as int,
        seedsRejected: batchJson['seeds_rejected'] as int,
        averageScore: (batchJson['average_score'] as num).toDouble(),
        uniformity: (batchJson['uniformity'] as num).toDouble(),
        anomalyCount: batchJson['anomaly_count'] as int,
        confidence: (batchJson['confidence'] as num).toDouble(),
        scoreHistogram: (batchJson['score_histogram'] as List).cast<int>(),
        qualityClassCounts:
            (batchJson['quality_class_counts'] as Map).cast<String, int>(),
        // Defaults keep scans written before analysis_version 0.2.0 readable.
        impurityCount: batchJson['impurity_count'] as int? ?? 0,
        purityRatio: (batchJson['purity_ratio'] as num?)?.toDouble() ?? 1.0,
      ),
      fusionResult: FusionResult(
        assessmentId: fusionJson['assessment_id'] as String,
        mode: AssessmentMode.values.byName(fusionJson['mode'] as String),
        crop: fusionJson['crop'] as String,
        visualScore: (fusionJson['visual_score'] as num).toDouble(),
        nirScore: (fusionJson['nir_score'] as num?)?.toDouble(),
        combinedScore: (fusionJson['combined_score'] as num).toDouble(),
        confidence: (fusionJson['confidence'] as num).toDouble(),
        seedCount: fusionJson['seed_count'] as int,
        anomalies: fusionJson['anomalies'] as int,
        modelVersions: (fusionJson['model_versions'] as Map).cast<String, String>(),
      ),
      results: results,
    );
  }

  Future<void> deleteScan(String scanId) async {
    await _db.delete('scans', where: 'scan_id = ?', whereArgs: [scanId]);
  }

  SeedResult _seedResultFromRow(Map<String, Object?> row) {
    final featuresJson = decodeJsonMap(row['visual_features'] as String);
    final predictionJson = decodeJsonMap(row['prediction'] as String);

    return SeedResult(
      seedId: row['seed_id'] as String,
      scanId: row['scan_id'] as String,
      cropPng: row['crop_png'] as Uint8List,
      segmentation: decodeJsonMap(row['segmentation'] as String),
      visualFeatures: _featuresFromJson(featuresJson),
      prediction: QualityPrediction(
        qualityClass: QualityClassLabel.fromStorageKey(
          predictionJson['quality_class'] as String,
        ),
        score: (predictionJson['score'] as num).toDouble(),
        confidence: (predictionJson['confidence'] as num).toDouble(),
        evidence: const [],
        anomalies: (predictionJson['anomalies'] as List).cast<String>(),
        modelVersion: predictionJson['model_version'] as String,
      ),
      confidence: (row['confidence'] as num).toDouble(),
      anomalies: (decodeJsonList(row['anomalies'] as String)).cast<String>(),
    );
  }

  SeedFeatures _featuresFromJson(Map<String, Object?> json) {
    final geo = (json['geometry'] as Map).cast<String, Object?>();
    final color = (json['color'] as Map).cast<String, Object?>();
    final texture = (json['texture'] as Map).cast<String, Object?>();
    final damage = (json['damage'] as Map).cast<String, Object?>();
    final rgb = (color['mean_rgb'] as List).cast<num>();
    final hsv = (color['mean_hsv'] as List).cast<num>();
    final lab = (color['mean_lab'] as List).cast<num>();

    return SeedFeatures(
      geometry: GeometryFeatures(
        areaPx: (geo['area_px'] as num).toDouble(),
        perimeterPx: (geo['perimeter_px'] as num).toDouble(),
        widthPx: (geo['width_px'] as num).toDouble(),
        lengthPx: (geo['length_px'] as num).toDouble(),
        aspectRatio: (geo['aspect_ratio'] as num).toDouble(),
        circularity: (geo['circularity'] as num).toDouble(),
        eccentricity: (geo['eccentricity'] as num).toDouble(),
        convexity: (geo['convexity'] as num).toDouble(),
      ),
      color: ColorFeatures(
        meanR: rgb[0].toDouble(),
        meanG: rgb[1].toDouble(),
        meanB: rgb[2].toDouble(),
        meanHue: hsv[0].toDouble(),
        meanSaturation: hsv[1].toDouble(),
        meanValue: hsv[2].toDouble(),
        meanLabL: lab[0].toDouble(),
        meanLabA: lab[1].toDouble(),
        meanLabB: lab[2].toDouble(),
        colorVarianceRgb: (color['color_variance_rgb'] as num).toDouble(),
        discolorationRatio: (color['discoloration_ratio'] as num).toDouble(),
      ),
      texture: TextureFeatures(
        edgeDensity: (texture['edge_density'] as num).toDouble(),
        entropy: (texture['entropy'] as num).toDouble(),
        surfaceIrregularity: (texture['surface_irregularity'] as num).toDouble(),
        localContrast: (texture['local_contrast'] as num).toDouble(),
      ),
      damage: DamageIndicators(
        darkRegionRatio: (damage['dark_region_ratio'] as num).toDouble(),
        crackLikeEdgeRatio: (damage['crack_like_edge_ratio'] as num).toDouble(),
        holeRatio: (damage['hole_ratio'] as num).toDouble(),
        abnormalPigmentationScore:
            (damage['abnormal_pigmentation_score'] as num).toDouble(),
      ),
    );
  }

  ImageQualityReport _qualityFromJson(Map<String, Object?> json) => ImageQualityReport(
        usable: json['usable'] as bool,
        qualityScore: (json['quality_score'] as num).toDouble(),
        blurScore: (json['blur_score'] as num).toDouble(),
        exposureScore: (json['exposure_score'] as num).toDouble(),
        glareScore: (json['glare_score'] as num).toDouble(),
        backgroundScore: (json['background_score'] as num).toDouble(),
        warnings: (json['warnings'] as List).cast<String>(),
      );
}

/// Lightweight row for the history list — avoids loading every seed crop
/// just to render a list tile (§41).
class ScanSummary {
  final String scanId;
  final DateTime timestamp;
  final String crop;
  final int numberOfSeeds;
  final double batchScore;
  final bool nirAvailable;

  const ScanSummary({
    required this.scanId,
    required this.timestamp,
    required this.crop,
    required this.numberOfSeeds,
    required this.batchScore,
    required this.nirAvailable,
  });

  static ScanSummary _fromRow(Map<String, Object?> row) => ScanSummary(
        scanId: row['scan_id'] as String,
        timestamp: DateTime.parse(row['timestamp'] as String),
        crop: row['crop'] as String,
        numberOfSeeds: row['number_of_seeds'] as int,
        batchScore: (row['batch_score'] as num).toDouble(),
        nirAvailable: (row['nir_available'] as int) == 1,
      );
}

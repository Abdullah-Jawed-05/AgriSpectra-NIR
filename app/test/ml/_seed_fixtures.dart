import 'dart:typed_data';
import 'dart:ui';

import 'package:agrispectra/domain/entities/processed_seed.dart';
import 'package:agrispectra/domain/entities/quality_prediction.dart';
import 'package:agrispectra/domain/entities/seed_features.dart';
import 'package:agrispectra/domain/value_objects/quality_class.dart';

/// Minimal [ProcessedSeed] for pipeline-aggregation tests — only the fields
/// the batch engine / impurity detector actually read are meaningful; the
/// rest are filled with harmless defaults.
ProcessedSeed makeSeed({
  required String id,
  double areaPx = 1000,
  double aspectRatio = 2.0,
  double score = 80,
  double confidence = 0.7,
  double labA = 5,
  double labB = 30,
  QualityClass qualityClass = QualityClass.good,
  List<String> anomalies = const [],
}) {
  return ProcessedSeed(
    seedId: id,
    cropPng: Uint8List(0),
    mask: Uint8List(0),
    maskWidth: 0,
    maskHeight: 0,
    boundingBox: Rect.zero,
    contour: const [],
    center: Offset.zero,
    orientationRadians: 0,
    features: SeedFeatures(
      geometry: GeometryFeatures(
        areaPx: areaPx,
        perimeterPx: 120,
        widthPx: 20,
        lengthPx: 40,
        aspectRatio: aspectRatio,
        circularity: 0.7,
        eccentricity: 0.6,
        convexity: 0.9,
      ),
      color: ColorFeatures(
        meanR: 150,
        meanG: 130,
        meanB: 90,
        meanHue: 35,
        meanSaturation: 0.4,
        meanValue: 0.6,
        meanLabL: 60,
        meanLabA: labA,
        meanLabB: labB,
        colorVarianceRgb: 100,
        discolorationRatio: 0.05,
      ),
      texture: const TextureFeatures(
        edgeDensity: 0.2,
        entropy: 4.0,
        surfaceIrregularity: 0.2,
        localContrast: 0.3,
      ),
      damage: const DamageIndicators(
        darkRegionRatio: 0.05,
        crackLikeEdgeRatio: 0.1,
        holeRatio: 0.0,
        abnormalPigmentationScore: 0.05,
      ),
    ),
    prediction: QualityPrediction(
      qualityClass: qualityClass,
      score: score,
      confidence: confidence,
      evidence: const [],
      anomalies: anomalies,
      modelVersion: 'test',
    ),
  );
}

import '../core/constants/app_constants.dart';
import '../domain/entities/quality_prediction.dart';
import '../domain/entities/seed_features.dart';
import '../domain/value_objects/quality_class.dart';
import 'agrispectra_model_v1_adapter.dart';

/// Whether the vision pipeline should use Model V1's prediction in place
/// of the V0 rule engine when V1 is available.
///
/// Deliberately **off by default**. Promoting a model (copying the two
/// generated files from the Trainer into this directory) only makes V1
/// *available* — it does not mean it's trusted. Per docs/VALIDATION.md, a
/// promoted model must be checked against a held-out collection batch
/// (ideally from a different day than it was trained on) before it's
/// allowed to override the hand-tuned V0 rule. Flip this manually, and
/// only after that check, then rebuild the app.
const bool useModelV1 = false;

/// Flattens [SeedFeatures] into the exact flat key -> value map Model V1
/// was trained on — field-for-field the same flat keys
/// `ml/preprocessing/features.py::extract_all()` writes into the training
/// `features.csv`. Keep this in sync with that function if either side's
/// feature set changes; a silent mismatch here makes every V1 prediction
/// wrong with no error.
Map<String, double> _toFeatureMap(SeedFeatures f) => {
      'area_px': f.geometry.areaPx,
      'perimeter_px': f.geometry.perimeterPx,
      'width_px': f.geometry.widthPx,
      'length_px': f.geometry.lengthPx,
      'aspect_ratio': f.geometry.aspectRatio,
      'circularity': f.geometry.circularity,
      'eccentricity': f.geometry.eccentricity,
      'convexity': f.geometry.convexity,
      'mean_r': f.color.meanR,
      'mean_g': f.color.meanG,
      'mean_b': f.color.meanB,
      'mean_hue': f.color.meanHue,
      'mean_saturation': f.color.meanSaturation,
      'mean_value': f.color.meanValue,
      'mean_lab_l': f.color.meanLabL,
      'mean_lab_a': f.color.meanLabA,
      'mean_lab_b': f.color.meanLabB,
      'color_variance_rgb': f.color.colorVarianceRgb,
      'discoloration_ratio': f.color.discolorationRatio,
      'edge_density': f.texture.edgeDensity,
      'entropy': f.texture.entropy,
      'surface_irregularity': f.texture.surfaceIrregularity,
      'local_contrast': f.texture.localContrast,
      'dark_region_ratio': f.damage.darkRegionRatio,
      'crack_like_edge_ratio': f.damage.crackLikeEdgeRatio,
      'hole_ratio': f.damage.holeRatio,
      'abnormal_pigmentation_score': f.damage.abnormalPigmentationScore,
    };

/// Turns a raw [ModelV1Prediction] into the app's [QualityPrediction]
/// shape. Pulled out of [tryModelV1] so this mapping logic (label decode,
/// confidence from the raw class scores, evidence text) is directly
/// testable without needing [useModelV1] flipped or a real model present.
QualityPrediction predictionFromModelV1Result(ModelV1Prediction result) {
  final qualityClass = QualityClassLabel.fromStorageKey(result.label);
  final total = result.classScores.fold<double>(0, (sum, s) => sum + s);
  final top = result.classScores.fold<double>(0, (m, s) => s > m ? s : m);
  final confidence = total > 0 ? (top / total).clamp(0.0, 1.0) : 0.0;
  final isGood = qualityClass == QualityClass.good;
  return QualityPrediction(
    qualityClass: qualityClass,
    score: confidence * 100,
    confidence: confidence,
    evidence: [
      EvidenceFactor(
        description: 'Predicted ${qualityClass.label.toLowerCase()} by the trained Model V1 classifier',
        supportsGoodQuality: isGood,
        weight: confidence,
      ),
    ],
    anomalies: isGood ? const [] : const ['model_v1_flagged'],
    modelVersion: AppVersions.visionModelVersionV1,
  );
}

/// Runs Model V1 on [features] and returns a [QualityPrediction], or
/// `null` if V1 isn't enabled, isn't available (no model promoted yet),
/// or the call fails for any reason (e.g. an unrecognised label from an
/// older promote) — callers must always have the V0 rule engine as a
/// fallback, never assume this succeeds.
QualityPrediction? tryModelV1(SeedFeatures features) {
  if (!useModelV1 || !modelV1Available) return null;
  try {
    final result = predictModelV1(_toFeatureMap(features));
    return predictionFromModelV1Result(result);
  } catch (_) {
    // Never let a V1 failure (missing label, malformed scores, a stale
    // placeholder) take the scan down — fall back to V0 silently from
    // the caller's point of view.
    return null;
  }
}

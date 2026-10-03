// GENERATED FILE — AgriSpectra Trainer, "Promote to App" (docs/TRAINER_APP_BUILD_PROMPT.md §4).
// Do not hand-edit; re-run Promote to App to regenerate from a newer run.
// This file has NO runtime dependency on Python, scikit-learn, or any ML
// library — it is plain decision logic, safe to drop into the Flutter app.
//
// Feature order the model was trained on (must match
// app/lib/ml/feature_extractor.dart's SeedFeatures field-for-field, in
// THIS exact order — a silent mismatch here makes every on-device
// prediction wrong with no error):
//   0: aspect_ratio
//   1: circularity
//   2: eccentricity
//   3: convexity
//   4: mean_r
//   5: mean_g
//   6: mean_b
//   7: mean_hue
//   8: mean_saturation
//   9: mean_value
//   10: mean_lab_l
//   11: mean_lab_a
//   12: mean_lab_b
//   13: color_variance_rgb
//   14: discoloration_ratio
//   15: edge_density
//   16: entropy
//   17: surface_irregularity
//   18: local_contrast
//   19: dark_region_ratio
//   20: crack_like_edge_ratio
//   21: hole_ratio
//   22: abnormal_pigmentation_score
//
// Label order (the model's raw output index -> class, in THIS order):
//   0: BROKEN
//   1: DAMAGED
//   2: GOOD
//   3: IMPURITIES
//   4: SHRIVELED

import 'model_v1_generated.dart' as generated;

/// True once a real model has been promoted — distinguishes this
/// generated file from the placeholder `agrispectra_model_v1_adapter.dart`
/// that ships in the app before any model exists (see
/// app/lib/ml/model_v1_predictor.dart, which gates on this).
const bool modelV1Available = true;

/// Which promoted model this is (the Trainer's version label, by default
/// "run_<id>"). Scans made with it record this, so a result can always be
/// traced back to the training run that produced it.
const String modelV1VersionLabel = 'run_47136c32aac0';

/// Feature-vector order `predictModelV1` expects in its input map's keys.
/// Keep in sync with app/lib/ml/feature_extractor.dart's SeedFeatures.
const List<String> modelV1FeatureOrder = ['aspect_ratio', 'circularity', 'eccentricity', 'convexity', 'mean_r', 'mean_g', 'mean_b', 'mean_hue', 'mean_saturation', 'mean_value', 'mean_lab_l', 'mean_lab_a', 'mean_lab_b', 'color_variance_rgb', 'discoloration_ratio', 'edge_density', 'entropy', 'surface_irregularity', 'local_contrast', 'dark_region_ratio', 'crack_like_edge_ratio', 'hole_ratio', 'abnormal_pigmentation_score'];

/// Class label order the trained model's raw output index maps to.
const List<String> modelV1LabelOrder = ['BROKEN', 'DAMAGED', 'GOOD', 'IMPURITIES', 'SHRIVELED'];

class ModelV1Prediction {
  final String label;
  final List<double> classScores;
  const ModelV1Prediction(this.label, this.classScores);
}

/// Runs the promoted model on one seed's feature map (as produced by
/// FeatureExtractor) and returns the predicted class + raw per-class
/// scores, in `modelV1LabelOrder` order.
ModelV1Prediction predictModelV1(Map<String, double> features) {
  final input = <double>[
    for (final key in modelV1FeatureOrder) (features[key] ?? 0.0),
  ];
  final scores = generated.score(input);
  var bestIndex = 0;
  for (var i = 1; i < scores.length; i++) {
    if (scores[i] > scores[bestIndex]) bestIndex = i;
  }
  return ModelV1Prediction(modelV1LabelOrder[bestIndex], scores);
}

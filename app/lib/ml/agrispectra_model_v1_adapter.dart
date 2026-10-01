// PLACEHOLDER — no Model V1 has been promoted yet.
//
// The AgriSpectra Trainer's "Promote to App" action
// (docs/TRAINER_APP_BUILD_PROMPT.md §4) regenerates this exact file —
// same name, same API — from a real trained model. Copying its output
// here (this file + model_v1_generated.dart) is the entire integration
// step; nothing else in the app needs to change, because
// model_v1_predictor.dart only depends on this fixed API and on
// [modelV1Available] to decide whether to trust it.

import 'model_v1_generated.dart' as generated;

/// False in this placeholder; a real "Promote to App" run sets this
/// `true` in its generated copy of this file. `model_v1_predictor.dart`
/// gates on this before ever calling [predictModelV1].
const bool modelV1Available = false;

/// Feature-vector order `predictModelV1` expects in its input map's keys.
/// Empty here since there's no trained model to have an order; a real
/// promote fills this in from `feature_columns.json`.
const List<String> modelV1FeatureOrder = [];

/// Class label order the trained model's raw output index maps to.
const List<String> modelV1LabelOrder = [];

class ModelV1Prediction {
  final String label;
  final List<double> classScores;
  const ModelV1Prediction(this.label, this.classScores);
}

/// Runs the promoted model on one seed's feature map. Never call this
/// without checking [modelV1Available] first — see
/// `model_v1_predictor.dart::tryModelV1`, which does that and never lets
/// this placeholder's [UnimplementedError] escape to the pipeline.
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

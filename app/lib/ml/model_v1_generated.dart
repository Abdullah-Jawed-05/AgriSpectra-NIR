// PLACEHOLDER — no Model V1 has been promoted yet.
//
// The AgriSpectra Trainer (trainer_app/, "Promote to App" —
// docs/TRAINER_APP_BUILD_PROMPT.md §4) regenerates this exact file with
// the trained model's real decision logic once one exists; copying its
// two output files into this directory (this one +
// agrispectra_model_v1_adapter.dart) is the entire integration step — no
// other code needs to change. Until then, this placeholder keeps the app
// compiling and `model_v1_predictor.dart`'s `modelV1Available` check
// false, so nothing calls into it.

List<double> score(List<double> input) {
  throw UnimplementedError(
    'Model V1 has not been promoted yet. Train a model in the AgriSpectra '
    'Trainer, run "Promote to App", and copy its two generated files into '
    'app/lib/ml/ to replace this placeholder.',
  );
}

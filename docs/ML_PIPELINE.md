# ML Pipeline

Two things share this name and are easy to conflate — this doc says which
is which.

## 1. On-device pipeline (Dart, ships in the app today)

`app/lib/ml/`:

```
image_quality_gate.dart   — blur/exposure/glare/background/resolution gate
seed_finder.dart          — Otsu threshold + connected components (detection+segmentation)
feature_extractor.dart    — color/texture/damage features over each segmented seed
rule_classifier.dart      — Model V0: hand-tuned rule engine, not trained
impurity_detector.dart    — Model V0: batch-relative size/shape outlier -> IMPURITIES
batch_engine.dart         — aggregates per-seed predictions into batch statistics
```

Orchestrated by `app/lib/application/scan_orchestrator.dart`. This is what
actually runs when a user scans seeds — see
[`ARCHITECTURE.md`](ARCHITECTURE.md) §5 for the pipeline diagram.

## 2. Training pipeline (Python, produces future models)

`ml/` — see [`../ml/README.md`](../ml/README.md) for the full pipeline
(prepare → split → train → evaluate → export). Trains Model V1 (classical
ML on the same features the Dart `FeatureExtractor` computes) and, later,
Model V2 (CNN). **Nothing this pipeline produces is consumed by the app
yet** — there's no real training dataset (see
[`DATASET_GUIDE.md`](DATASET_GUIDE.md)).

## How V0 becomes V1

When a real dataset exists and `ml/training/train_baseline.py` produces a
validated model (`ml/evaluation/evaluate_model.py` results reviewed and
recorded in [`VALIDATION.md`](VALIDATION.md)):

1. Export the trained model in a form the app can load (ONNX via
   `ml/export/export_onnx.py`, or hand-port the decision logic if it's
   small enough — TBD based on what V1 actually turns out to be).
2. Add a Dart-side inference path in `app/lib/ml/` that implements the same
   interface `RuleBasedClassifier.classify(SeedFeatures) -> QualityPrediction`
   currently implements, so `ScanOrchestrator` swaps in the new classifier
   with a one-line change.
3. Keep `RuleBasedClassifier` in the codebase as a fallback for "model file
   missing or corrupt" (§58 of the original build spec) rather than
   deleting it.
4. Bump `AppVersions.visionModelVersion`
   (`app/lib/core/constants/app_constants.dart`) — every historical `Scan`
   row keeps whatever version it was written with (§26).

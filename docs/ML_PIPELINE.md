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
Model V2 (CNN). A first Model V1 has now been trained on the barley
dataset (results in [`VALIDATION.md`](VALIDATION.md)), but **nothing this
pipeline produces is consumed by the app yet** — see "How V0 becomes V1"
below for what's still needed before that's true.

## 3. Python↔Dart feature parity (verified 2026-09-04)

A model trained on `ml/preprocessing`'s features is only valid for
on-device inference if `app/lib/ml/{seed_finder,feature_extractor}.dart`
compute the same features the same way at runtime — both sides' docstrings
say this, but it wasn't actually true until this pass. What changed, and
what's still an accepted residual gap:

**Fixed — real algorithmic mismatches, not just noise:**
- Perimeter/circularity: Dart counted boundary *pixels*; Python used
  `cv2.arcLength` on a *contour*. Dart now traces a proper boundary polygon
  (Moore-neighbor tracing, `seed_finder.dart::_traceContour`) and measures
  polygon arc length, matching Python's `cv2.findContours`+`arcLength`.
- Width/length/eccentricity: Python used `cv2.fitEllipse` (a conic fit to
  the contour); Dart used a moment-based equivalent ellipse. Rather than
  porting `fitEllipse`'s harder-to-replicate algorithm into Dart, Python's
  `segmentation.py::_moment_ellipse` was rewritten to use the *same*
  moment-based formula Dart already had — one shared, simple definition
  instead of two different "correct" ones.
- Texture/edges: Dart used a 1-pixel forward-difference gradient with
  threshold 30; Python used a proper 3×3 Sobel gradient with threshold 60
  (a different scale entirely — the thresholds were never calibrated
  against each other). Dart now implements the same Sobel kernel with
  OpenCV's `BORDER_REFLECT_101` border handling and threshold 60.
- Holes: Dart only caught a single isolated background pixel; Python's
  docstring claimed parity with Dart but actually used
  `cv2.floodFill` from one corner — and that corner seed is itself a latent
  bug (silently misclassifies the entire "outside" as one giant hole
  whenever a shape touches its own bounding-box corner). Both sides now
  flood-fill from *every* border pixel of the crop
  (`feature_extractor.dart::_countHolePixels`,
  `features.py::_hole_ratio`) — the correct and now-identical definition.
- Color (Lab/HSV): Python leaned on `cv2.cvtColor`'s 8-bit-quantized HSV/Lab
  conversion (2°-step hue, a `uint8` round-trip for Lab). `features.py` now
  has an exact numpy port of `feature_extractor.dart`'s float-precision
  `_rgbToHsv`/`_rgbToLab`, so both sides evaluate the literal same formula.

**Fixed — a real production bug this check surfaced, unrelated to Python
parity:** `img.grayscale(src)` (the `image` package) mutates `src` in
place and returns the same object. Both `seed_finder.dart` and
`feature_extractor.dart` were passing the RGB image/crop straight into it
and continuing to use that same reference afterward for color features —
meaning every color feature the app has ever computed (mean R/G/B/hue/
saturation/Lab, discoloration ratio) was silently derived from an
already-desaturated crop, since before the original MVP commit. Fixed by
cloning before grayscaling in both places; regression-tested in
`app/test/ml/{seed_finder,feature_extractor}_test.dart`.

**Accepted residual gap:** resizing. Dart's `copyResize` and OpenCV's
`cv2.resize` both now explicitly use linear interpolation (Dart's default
was actually *nearest*, a second bug this fixes), but the two libraries'
bilinear kernels aren't bit-identical, so pixel values a few percent apart
near edges are expected. Verified acceptable — see below.

**Verification:** `ml/scripts/parity_check.py` and
`app/test/tool/parity_check_dev.dart` run the two pipelines over the same
photo and print every feature as JSON for diffing (dev tools, not part of
the normal test/training run — see each file's header). Spot-checked
across 3 real barley photos (1, 7, and 14 detected seeds): geometry and
texture features now agree within ~1–3%, color features within ~1–3%
(previously: color was completely wrong — desaturated — and geometry/
texture used unrelated algorithms). Re-run this whenever either side's
feature code changes.

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

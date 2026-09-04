# Validation & Known Limitations

Living document. What has and hasn't been checked, so claims made
elsewhere (UI copy, report text, demo scripts) stay honest. Update this
file whenever validation status changes — do not let ARCHITECTURE.md or
the app's UI copy get ahead of what's actually been tested.

## Current status: pre-validation

No formal validation has been run. Model V0
(`app/lib/ml/rule_classifier.dart` + `app/lib/ml/impurity_detector.dart`)
is a hand-tuned rule engine, not a trained-and-evaluated model. A first
labelled dataset now exists — **one barley collection, ~158 images, five
label folders (GOOD / DAMAGED / BROKEN / SHRIVELED / IMPURITIES), single
session** (see [`DATASET_GUIDE.md`](DATASET_GUIDE.md)) — enough to train a
first Model V1 for sanity-checking, not enough to support an accuracy
claim. Everything below is what *will* be checked once V1 exists, listed
now so the validation plan itself is reviewable.

## What §47 of the build spec requires before any accuracy claim

Test the model across:
- different lighting conditions
- different phone models
- different macro lens attachments
- different backgrounds
- different seed batches
- different cultivars (within a crop)
- different storage histories

And explicitly identify which of these factors cause failure — a "known
limitations" section is required output, not optional polish.

## Known limitations today (V0, rule engine)

- **Thresholds are hand-tuned**, not fit to data. `RuleBasedClassifier`'s
  constants (`_highDamageDarkRatio`, etc.) and `ImpurityDetector`'s outlier
  multipliers reflect engineering judgment against the barley reference set,
  explicitly documented as such in the source. Treat any score it produces
  as illustrative, not measured.
- **Those thresholds haven't been re-validated since the 2026-09-04 feature
  parity fix** (`visionModelVersion` v0 → v0.2, see
  [`ML_PIPELINE.md`](ML_PIPELINE.md) §3). Before that fix, color features
  (`_highDiscoloration` and friends) were silently computed from an
  accidentally desaturated crop, so `RuleBasedClassifier`'s color-based
  branch was effectively inert — any hand-tuning that happened against V0's
  actual behavior was tuning around dead code, not around real color
  signal. Geometry/texture thresholds also now see meaningfully different
  input distributions (real Sobel edges instead of a coarser forward-diff
  gradient). Re-tuning against the real barley photos (or better, folding
  this into Model V1 training) is the next honest step, not a retroactive
  claim that V0's current thresholds are still well-calibrated.
- **Single crop, single collection session.** All barley data came from one
  shoot, so `split_dataset.py` can only make an implicit-batch split — a V1
  trained on it will overstate its own accuracy (near-duplicate seeds leak
  across the split). This is the first thing more data collection fixes.
- **V0 impurity detection is population-relative and shape-only.** It flags
  objects that are size/aspect outliers versus the rest of the batch; a
  foreign object that happens to be barley-grain-sized and -shaped will be
  missed, and an unusually large or misshapen real seed can be
  false-flagged. It needs ≥5 detections to run at all.
- **`broken` is never emitted by V0.** The rule engine has no reliable
  single-seed heuristic for fragmentation; only the trained V1 will
  classify it.
- **Detection assumes a reasonably contrasting background.**
  `ClassicalCVSeedFinder` tries both light-foreground and dark-foreground
  Otsu polarities and picks whichever finds more plausible blobs, but a
  background close in luminance to the seeds will still fail to segment
  cleanly — this is why the image quality gate checks background contrast
  before running detection at all.
- **No cultivar-specific tuning.** One rule set is applied regardless of
  crop or cultivar; nothing in the pipeline currently adjusts thresholds
  per crop even though `Crop` is tracked per scan.
- **NIR is entirely simulated.** No physical AgriSpectra NIR device
  exists. `SimulatedNIRDevice`'s spectral curves are hand-authored,
  illustrative shapes, not measurements — see its class doc comment in
  `app/lib/nir/simulated_nir_device.dart`.

## Explicit non-claims

AgriSpectra does not, and must not be described as:
- measuring embryo viability from RGB imagery alone
- predicting germination without a real lab ground-truth dataset behind it
- providing laboratory-grade or certified seed-quality testing
- resolving the AS7265x's 18 discrete channels into a continuous spectrum

See §66 of the original build spec for the exact phrasing discipline this
maps to ("visual quality characteristics that may correlate with quality,"
not "detects X").

# Validation & Known Limitations

Living document. What has and hasn't been checked, so claims made
elsewhere (UI copy, report text, demo scripts) stay honest. Update this
file whenever validation status changes — do not let ARCHITECTURE.md or
the app's UI copy get ahead of what's actually been tested.

## Current status: pre-validation

No formal validation has been run. There is no labeled dataset (see
[`DATASET_GUIDE.md`](DATASET_GUIDE.md)), so Model V0
(`app/lib/ml/rule_classifier.dart`) is a hand-tuned rule engine, not a
trained-and-evaluated model. Everything below is what *will* be checked
once V1 exists, listed now so the validation plan itself is reviewable.

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
  constants (`_highDamageDarkRatio`, etc.) reflect engineering judgment
  against a handful of reference seeds, explicitly documented as such in
  the source. Treat any score it produces as illustrative, not measured.
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

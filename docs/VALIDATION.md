# Validation & Known Limitations

Living document. What has and hasn't been checked, so claims made
elsewhere (UI copy, report text, demo scripts) stay honest. Update this
file whenever validation status changes — do not let ARCHITECTURE.md or
the app's UI copy get ahead of what's actually been tested.

## Model V1 — cross-session evaluation (2026-09-06): it does not generalize

A second barley collection was captured (`batch_2026-09-06_lot2`, 270
images / ~5,100 seed rows, shot on a different day, different
lighting/setup from the first). That makes a **real** held-out test
possible for the first time: train on one whole session, test on the
other — `split_dataset.py --test-batch <id>`, run both directions.

**Result: the LightGBM model trained on classical features does not
transfer across sessions at all.**

| Direction | Train | Test | macro-F1 | balanced acc | ROC-AUC (ovr) |
|---|---|---|---|---|---|
| A | lot1 (Aug) + aug | lot2 (Sep) | **0.10** | 0.21 | **0.50** |
| B | lot2 (Sep) + aug | lot1 (Aug) | **0.15** | 0.19 | **0.46** |

ROC-AUC ≈ 0.5 is random. The earlier 0.62 macro-F1 (below) was **entirely
leakage** — near-duplicate seeds from one shoot sitting in both train and
test. On genuinely held-out data there is no signal.

**Why** (from comparing feature medians between the two batches):
- **Colour is a session fingerprint, not a quality signal.** lot1 median
  `mean_r` 150 / `mean_b` 120 (warm); lot2 `mean_r` 130 / `mean_b` 145
  (cool). The pipeline does **no white-balance or exposure normalisation**
  (§8 of the build spec says preprocessing "should attempt" this — it
  doesn't), so every colour feature encodes which session, not which
  class.
- **Geometry uses absolute pixels.** lot1 median `area_px` 1180, lot2 338
  — a ~3.5× scale difference (different framing / seed density / camera).
  `area_px`, `perimeter_px`, `width_px`, `length_px` are absolute counts;
  they carry session, not shape. (`aspect_ratio`, `circularity`,
  `eccentricity`, `convexity` are already scale-invariant and fine.)
- `edge_density` inherits the scale problem (0.20 vs 0.40) — edge pixels
  are a bigger fraction of a smaller blob.

### What was tried (2026-09-06) and what it showed

1. **White-balance + exposure normalisation** (`_normaliseLighting`, added
   to both `seed_finder.dart` and `segmentation.py`): gray-world plus an
   exposure pull to mid-grey, before any pixel is read. Aligned `mean_r`/
   `mean_g` across the two batches well, `mean_b` less so. **Cross-session
   macro-F1 stayed ~0.12** — it helped colour but not the shape features.
2. **Dropped `area_px` / `perimeter_px` / `width_px` / `length_px`** from
   the trained feature set (kept the scale-invariant ratios). No
   cross-session improvement either.
3. **Diagnostic — a V2-only stratified split** (leaky, but consistent
   photography): macro-F1 **0.48**, ROC-AUC **0.83**. The features *do*
   carry real signal when photography is consistent.
4. **Diagnostic — feature medians by batch** after normalisation:
   `aspect_ratio` 2.2 vs 3.8, `edge_density` 0.06 vs 0.40, `circularity`
   0.17 vs 0.13 — the *shape* features themselves differ hugely between
   sessions, even the scale-invariant ones.
5. **Root cause — the two sessions were photographed differently.** lot1
   averages 4 seeds/photo (often clumped, so segmentation returns a few
   big irregular blobs); lot2 averages 22 seeds/photo, spread out,
   matching the app's own capture guidance (so it returns many clean
   single-seed blobs). An area filter drops ~80% of lot1's rows but only
   ~20% of lot2's — most of lot1's "seeds" aren't single grains. The two
   batches aren't the same kind of object.

### The real cause (2026-09-06, after looking at the actual photos)

Both barley sets are **single-seed macro shots** — one grain per photo.
The "22 seeds/photo" from lot2 was the detector finding **one real grain
plus 80+ spurious blobs on the background**: lot2 was shot on a **blue
woven exercise mat** whose repeating dimple texture and lighting gradient
fragment into dozens of connected components under Otsu. lot1 was shot on
plain white paper (clean — ~1 blob). So lot2's ~5,000 "seed rows" were
mostly mat texture with a quality label attached.

Fixes applied:
- `prepare_dataset.py --one-seed` + `segmentation.py::pick_primary_seed`:
  for a single-subject photo, keep only the blob that looks like a
  coherent coloured object (saturation × convexity, plausible size). Not
  used on-device (real scans are multi-seed) — a dataset-prep concern.

With `--one-seed` (378 clean-ish rows instead of ~7,000):

| Direction | macro-F1 | ROC-AUC |
|---|---|---|
| train lot1 → test lot2 | 0.23 | 0.59 |
| train lot2 → test lot1 | 0.12 | 0.45 |
| lot2-only (leaky) | 0.34 | 0.64 |

Better than random for lot1→lot2, but lot2-trained is still useless
because ~half of lot2's picked crops are *still* mat texture, not seed —
`pick_primary_seed` can't reliably rescue thin straw impurities or small
broken fragments against that background.

**What this means:**
- **Do NOT wire V1 into the app.** Strictly worse than the V0 rule engine.
- The normalisation, drop-absolute-geometry, and `--one-seed` changes are
  all kept — correct regardless.
- **The blocker is the capture background.** lot2's textured mat violates
  the build spec's own guidance (§8 "avoid excessive background clutter",
  §10 "background sufficiently distinct from the seeds"). The next session
  has to be on a **plain, light, matte, untextured** surface — plain white
  paper, like lot1. Then re-run this whole cross-session test.

### Background-texture gate (2026-09-07)

To stop this happening again — in the app *and* in the training data — a
tile-based texture check was added to
`app/lib/ml/image_quality_gate.dart` (`_tileTextureStats`) and mirrored in
`ml/preprocessing/segmentation.py` (`assess_background_texture`, used by
`prepare_dataset.py`, skippable with `--allow-textured-bg`).

It splits a downscaled grey copy into 48 px tiles and, per tile, measures
luminance std-dev and the variance of a 4-neighbour Laplacian. The
**median tile std-dev** tracks the background (robust to a few seed tiles)
and the **busy-tile ratio** measures how much of the frame carries real
high-frequency structure. A frame is hard-rejected when
`median tile std-dev > 3.2` **or** `busy-tile ratio > 0.80`.

Tuned on the two barley sessions (158 clean lot1 photos, 270 textured lot2
photos):

| threshold | lot1 flagged textured (want 0) | lot2 flagged textured (want all) |
|---|---|---|
| `busy>0.55 or med>2.8` | 0 / 158 | 269 / 270 |
| `busy>0.80 or med>3.2` (shipped) | 0 / 158 | 263 / 270 (97.4%) |

The shipped cutoff is deliberately loose on the busy-tile ratio (clean set
p90 ≈ 0.42) so a higher-ISO capture isn't rejected for sensor noise — at
that level the `median tile std-dev > 3.2` term is doing essentially all
of the detection on its own. The old `backgroundScore`
(global std-dev / 45) did the *opposite* of what's needed here — lot2's mat
has a **high** global std-dev and scored *well* on it.
- The single-session "sanity check" numbers below are kept only as a
  record of how misleading a leaky split is — 0.62 vs 0.10, same model.

## Model V1 — first training run (2026-09-05)

`ml/training/train_baseline.py` (LightGBM) trained on the full barley
dataset for the first time, via `prepare_dataset.py` → `split_dataset.py`
→ `train_baseline.py` → `evaluate_model.py`. Read the numbers below with
the caveat in the next paragraph in mind at all times — they are a sanity
check, not a validated accuracy claim (§19/§66 of the build spec).

**Not leakage-safe.** The dataset is one collection session, so
`split_dataset.py` could not do its intended group-by-batch split (a group
split needs ≥2 batches to hold one out from) — it fell back to a
label-stratified row split, which can and does put near-duplicate seeds
from the same shoot on both sides of train/test. Treat every number below
as measuring "does the model separate these 5 classes at all," not
generalization to a new session, lighting setup, or phone.

Held-out test set (121 rows, stratified row split): **macro-F1 0.62,
balanced accuracy 0.60**, ROC-AUC (one-vs-rest, macro) 0.87.

| Class | Precision | Recall | F1 | Support |
|---|---|---|---|---|
| IMPURITIES | 0.82 | 0.75 | 0.78 | 12 |
| BROKEN | 0.75 | 0.67 | 0.71 | 27 |
| GOOD | 0.64 | 0.62 | 0.63 | 37 |
| DAMAGED | 0.46 | 0.59 | 0.52 | 32 |
| SHRIVELED | 0.56 | 0.38 | 0.45 | 13 |

Confusion matrix: `ml/models/v1/eval/confusion_matrix.png` (gitignored —
regenerate with the command above). The confusable pairs are exactly what
you'd expect from the underlying biology/optics, not a red flag:
- **GOOD ↔ DAMAGED** is the main confusion (13 GOOD called DAMAGED, 7
  DAMAGED called GOOD) — mild damage and undamaged sit on a visual
  continuum; this is the hardest real boundary in the taxonomy.
- **SHRIVELED** is the weakest class (recall 0.38) and also the smallest
  (63 images total, 13 in this test split) — the clearest case for "more
  data fixes this," not a modeling problem.
- **IMPURITIES** and **BROKEN** — the two most visually distinct classes —
  perform best, as expected.

This is a genuine, informative first signal that the feature set (now
parity-verified against the app, see [`ML_PIPELINE.md`](ML_PIPELINE.md) §3)
carries real information about the 5 classes. It is not evidence the model
will work on a new photo taken tomorrow — see the leakage caveat above and
the dataset-diversity requirements in §47 below.

**With augmentation** (`ml/scripts/augment_dataset.py`, §18 — see
[`ML_PIPELINE.md`](ML_PIPELINE.md) §4), training rows 409 → 1,636, same
held-out test set: macro-F1 **0.59** (was 0.62), balanced accuracy **0.60**
(was 0.60), ROC-AUC **0.86** (was 0.87). Essentially a wash, not an
improvement — recorded honestly rather than only reporting the better
number. Plausible reasons: several geometry features are already
rotation/flip-invariant by construction (moment-based ellipse), so this
augmentation set adds less signal than it would to a raw-pixel model; and
the eval itself is small and non-leakage-safe, so a real small effect
either direction could be within its noise. Re-run once a second real
batch exists to evaluate against.

## Current status: pre-validation (for anything beyond the V1 sanity check above)

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
- **Detection assumes a plain, contrasting background.**
  `ClassicalCVSeedFinder` tries both light-foreground and dark-foreground
  Otsu polarities and picks whichever finds more plausible blobs, but a
  background close in luminance to the seeds — or a *textured* one (woven
  mat, fabric, wood grain) — will still fail to segment cleanly. The image
  quality gate now checks both before running detection: low global
  contrast, and (since 2026-09-07) background texture via a tile-based
  Laplacian pass. `prepare_dataset.py` applies the same texture check to
  training images.
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

# Dataset Guide

How to collect, label, structure, split, and version data for AgriSpectra
model training. See [`../ml/README.md`](../ml/README.md) for the pipeline
that consumes what this guide produces.

## What "batch" means here, precisely

A **batch** is one physical collection event: a specific set of seeds,
photographed (and optionally NIR-scanned) together, at one place and time.
Everything downstream — labeling, splitting, versioning — is organized
around batches because seeds from the same batch look more like each other
than like seeds from a different batch (same lighting, same background,
same physical seed lot). Treating rows as independent when they're not is
exactly the leakage §17 of the original build spec warns about.

## In-app collection ("Make Our App Better")

As of 2026-09-05, the app itself is a data-collection path — no manual
folder-sorting required to grow the dataset. It's built around how the app
is actually used, not as a separate mode:

- Every scan's seeds are stored **unverified** by default
  (`seed_results.verified_label IS NULL`) — capturing an image never asks
  the user anything; that would defeat normal scanning.
- **"Make Our App Better"** (a home-screen entry, `app/lib/presentation/
  screens/improve_app_screen.dart`) is where anyone using the app reviews
  unverified seeds later, at their own pace: it shows the crop, the
  model's own guess, and the 5 label buttons — confirm or correct with one
  tap. This applies retroactively to every past scan too, not just future
  ones.
- The confirmed label (`verified_label`) is real ground truth. The model's
  own `prediction` never was, and the two are stored separately —
  `RuleBasedClassifier`/`ImpurityDetector` being wrong is exactly the case
  this exists to catch.
- **Export** (the share icon on that screen) zips every verified seed into
  `<crop>/<batch_id>/<LABEL>/<seed_id>.png` — the exact layout
  `prepare_dataset.py` wants — and hands it to the OS share sheet.
  `batch_id` is derived from the scan's capture date (`app_YYYY-MM-DD`),
  not entered by anyone: every day of app usage becomes its own collection
  batch automatically, which is what actually lets `split_dataset.py` do a
  real group split once enough days accumulate (see "What batch means"
  above). Unzip the export straight into `ml/data/raw/barley/`.
- Exports are always the *complete* verified set, not just what's new — no
  export-state tracking to get out of sync. Replace your local
  `ml/data/raw/barley/` wholesale with each new export rather than
  merging by hand.

## Scope: barley only (for now)

AgriSpectra currently has one labelled crop — barley — so that's the only
`Crop` the app offers and the only crop this pipeline is exercised against.
The `<crop>` directory level below stays in the layout (and the `Crop` enum
stays in the app) as the seam for adding crops back once each has its own
data and a tuned model.

## Directory structure for `prepare_dataset.py`

Two layouts work, auto-detected per crop.

**3-level** (explicit collection batches — use this once you're shooting
across multiple sessions/setups):

```
raw/
└── barley/
    ├── batch_2026-08-28_lot1/
    │   ├── GOOD/*.jpg
    │   ├── DAMAGED/*.jpg
    │   └── BROKEN/*.jpg
    └── batch_2026-09-03_lot2/
        └── ...
```

**2-level** (just sort photos straight into per-label folders — fine for an
early sanity pass; every image under the crop becomes one implicit batch):

```
raw/
└── barley/
    ├── GOOD/*.jpg
    ├── DAMAGED/*.jpg
    ├── BROKEN/*.jpg
    ├── SHRIVELED/*.jpg
    └── IMPURITIES/*.jpg
```

The barley reference set that exists today is a 2-level collection (five
label folders, one shoot) — `prepare_dataset.py` treats it as a single
implicit batch, which is why the split can't yet truly separate train from
test (see Splitting, and `docs/VALIDATION.md`).

- One image = one photographed group of seeds (10–50, matching the app's
  capture guidance in `app/lib/presentation/screens/scan_flow_screen.dart`),
  **or** a single seed if you're photographing/cropping them individually
  — either way, `prepare_dataset.py` re-detects seeds in each image itself,
  so both work.
- `label` folders use the `QualityClass` storage keys from
  `app/lib/domain/value_objects/quality_class.dart`. Current set, matching
  the labelled folders of the barley reference collection:

  | Key | Meaning |
  |---|---|
  | `GOOD` | no defects observed (includes what might otherwise be called "premium"/"perfect" — score, not a separate class, carries that gradation) |
  | `DAMAGED` | hull/shell compromised but the seed may still be viable. **Also where hull-missing ("shell-free") seeds go** — there were too few to justify a separate class |
  | `BROKEN` | physically fragmented (e.g. cut/split in half) — an observable physical state, not itself a germination claim, but practically implies non-viability |
  | `SHRIVELED` | shrunken/wrinkled appearance (also where a purely visual "looks dead" call belongs — see the note below) |
  | `IMPURITIES` | **not a seed** — foreign matter (stones, chaff, stems, other-crop seeds). A valid training label, but the app keeps it out of per-seed quality stats and reports it as a batch-purity figure instead (see below) |
  | `UNKNOWN` | doesn't fit a specific category. Internal fallback — not a folder you should normally be sorting into |

  Folder names are matched case-insensitively with spaces/hyphens
  normalized to underscores, so `Impurities`, `impurities`, and
  `IMPURITIES` all land on the same label.

  Removed from the earlier taxonomy: `DISCOLORED`, `SHELL_FREE`,
  `MOLD_SUSPECT`, `INSECT_DAMAGED` — no barley data was collected for them.
  Old scans stored with those keys load back as `UNKNOWN`.

### How `IMPURITIES` is treated

Foreign matter is a *batch-purity* concern, not a *seed-quality* one, so
the two are kept separate:

- **Training** — `IMPURITIES` is an ordinary label. `prepare_dataset.py`
  accepts the folder and the trained model learns to output the class.
- **In the app** — any detection classified `IMPURITIES` (by the trained
  model, or by `impurity_detector.dart`'s size/shape outlier rule in V0) is
  excluded from batch score / uniformity / anomaly count, and surfaced as
  `BatchStatistics.impurityCount` + `purityRatio` on the result screen.
- These are **visual-quality labels a human assigned by looking at the
  seed**, not germination outcomes. Deliberately no `DEAD`/`ALIVE` label:
  a photo alone can't establish that, only a real germination test can
  (§15/§16 of the build spec) — a seed that visually looks non-viable
  belongs in `SHRIVELED` (or another specific defect class), not a label
  that asserts a biological outcome nothing here actually measured. See
  §Germination dataset below for the protocol that *would* justify a real
  viability label.

## Labeling methodology

Label at the *image* level (a whole batch photo gets one label) if the
batch is visually uniform, or crop and label individual seeds if it's
mixed — `prepare_dataset.py` assigns the image's label to every seed it
detects in that image, so mixed-quality images need to be split into
single-class sub-images before running the script. Document who labeled
each batch and by what criteria; put that in a `LABELING_NOTES.md` next to
the raw batch folder, not just in someone's memory.

## Germination dataset (future, separate protocol)

To eventually train a real germination predictor (Model V4/V5 in
[`ARCHITECTURE.md`](ARCHITECTURE.md) §8), a *different* dataset is needed,
linking image → seed → certified lab germination result:

```
For each batch:
1. Photograph seeds (and NIR-scan, if a device is available).
2. Assign unique per-seed IDs.
3. Run AgriSpectra visual analysis, store the prediction.
4. Perform a controlled germination test on the same physical seeds.
5. Record the germination outcome.
6. Link image → seed → lab result via the seed ID.
```

This does not exist yet. Do not train or claim a germination model without
it — see `docs/VALIDATION.md`.

## Splitting

Use `ml/scripts/split_dataset.py`. It group-splits by `batch_id` — no
batch appears in more than one of train/val/test. Re-running
`prepare_dataset.py` with new batches and re-splitting is expected as the
dataset grows; don't hand-edit the split CSVs.

## Versioning

Each dataset snapshot gets a version folder (`dataset_v0.1/`,
`dataset_v0.2/`, ...). A new version is warranted when: batches are added,
a labeling error is corrected, or the split methodology changes. Each
version's directory should be able to answer, from its own contents:
number of samples, crops covered, class distribution, source batches,
collection date range, and the labeling methodology used (link to the
`LABELING_NOTES.md` files for the batches it includes).

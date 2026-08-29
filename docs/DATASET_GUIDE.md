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

## Directory structure for `prepare_dataset.py`

Two layouts work, auto-detected per crop:

```
raw/
├── wheat/                            (3-level: explicit batches)
│   ├── batch_2026-08-01_farmA/
│   │   ├── GOOD/*.jpg
│   │   ├── DAMAGED/*.jpg
│   │   └── DISCOLORED/*.jpg
│   └── batch_2026-08-03_farmB/
│       └── ...
└── barley/                           (2-level: no batch folder)
    ├── GOOD/*.jpg
    ├── DAMAGED/*.jpg
    ├── BROKEN/*.jpg
    └── ...
```

The 2-level form (just sort photos straight into per-label folders) is
fine for an early sanity-check pass or when everything really did come
from one shoot — `prepare_dataset.py` treats all of a crop's images as one
implicit batch in that case. Switch to the 3-level form once you're
collecting across multiple sessions/setups deliberately, so splitting can
group by batch properly (see below).

- One image = one photographed group of seeds (10–50, matching the app's
  capture guidance in `app/lib/presentation/screens/scan_flow_screen.dart`),
  **or** a single seed if you're photographing/cropping them individually
  — either way, `prepare_dataset.py` re-detects seeds in each image itself,
  so both work.
- `label` folders use the `QualityClass` storage keys from
  `app/lib/domain/value_objects/quality_class.dart`. Current set, refined
  against a real barley reference collection:

  | Key | Meaning |
  |---|---|
  | `GOOD` | no defects observed (includes what might otherwise be called "premium"/"perfect" — score, not a separate class, carries that gradation) |
  | `DAMAGED` | hull/shell compromised but the seed may still be viable |
  | `BROKEN` | physically fragmented (e.g. cut/split in half) — an observable physical state, not itself a germination claim, but practically implies non-viability |
  | `DISCOLORED` | abnormal pigmentation |
  | `SHRIVELED` | shrunken/wrinkled appearance (also where a purely visual "looks dead" call belongs — see the note below) |
  | `SHELL_FREE` | hull missing entirely, seed exposed |
  | `MOLD_SUSPECT` | visible fungal-like growth |
  | `INSECT_DAMAGED` | holes/boring consistent with insect damage |
  | `UNKNOWN` | doesn't fit a specific category |

  Folder names are matched case-insensitively with spaces/hyphens
  normalized to underscores, so `Shell Free`, `shell-free`, and
  `SHELL_FREE` all land on the same label.
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

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

```
raw/
├── wheat/
│   ├── batch_2026-08-01_farmA/
│   │   ├── GOOD/*.jpg
│   │   ├── DAMAGED/*.jpg
│   │   └── DISCOLORED/*.jpg
│   └── batch_2026-08-03_farmB/
│       └── ...
└── rice/
    └── ...
```

- One image = one photographed group of seeds (10–50, matching the app's
  capture guidance in `app/lib/presentation/screens/scan_flow_screen.dart`).
- `label` folders use the `QualityClass` storage keys from
  `app/lib/domain/value_objects/quality_class.dart`: `GOOD`, `DAMAGED`,
  `DISCOLORED`, `SHRIVELED`, `MOLD_SUSPECT`, `INSECT_DAMAGED`, `UNKNOWN`.
- These are **visual-quality labels a human assigned by looking at the
  seed**, not germination outcomes. See §Germination dataset below for
  that separate, harder protocol.

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

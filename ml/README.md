# AgriSpectra ML pipeline

Python training repository for Model V1 (classical ML baseline) and, once
a larger image dataset exists, Model V2 (CNN transfer learning). See
[`../docs/ARCHITECTURE.md`](../docs/ARCHITECTURE.md) §8 for the roadmap and
[`../docs/DATASET_GUIDE.md`](../docs/DATASET_GUIDE.md) for how to collect
and structure data.

**Nothing in this directory is wired into the Flutter app yet.** The app
ships with `RuleBasedClassifier` (`app/lib/ml/rule_classifier.dart`, Model
V0) because no labeled dataset exists to train V1 on. This pipeline is
here so that the moment real data is collected, training can start without
also having to design the pipeline from scratch.

## Setup

```bash
cd ml
python -m venv .venv
source .venv/bin/activate   # .venv\Scripts\activate on Windows
pip install -r requirements.txt
```

## Pipeline

```
raw/<crop>/<batch_id>/<label>/*.jpg
        │  prepare_dataset.py — detects+segments seeds (preprocessing/segmentation.py,
        │  mirrors app/lib/ml/seed_finder.dart) and extracts features
        │  (preprocessing/features.py, mirrors app/lib/ml/feature_extractor.dart)
        ▼
dataset_v0.1/features.csv, crops/
        │  split_dataset.py — GROUPS BY batch_id, never splits within a batch
        ▼
dataset_v0.1/{train,val,test}.csv
        │  training/train_baseline.py — LightGBM or RandomForest
        ▼
models/v1/model.joblib
        │  evaluation/evaluate_model.py, evaluation/generate_confusion_matrix.py
        ▼
models/v1/eval/evaluation_report.json, confusion_matrix.png
        │  export/export_onnx.py (interop) — NOT consumed by the app yet
        ▼
models/v1/model.onnx
```

Model V2 (`training/train_cnn.py`, `export/export_tflite.py`) is gated on
a substantially larger image dataset — see the module docstrings for why.

## Why features are computed twice (Python and Dart)

`preprocessing/segmentation.py` and `preprocessing/features.py` are
deliberate ports of `app/lib/ml/seed_finder.dart` and
`app/lib/ml/feature_extractor.dart`. A model trained on features computed
one way is only valid for on-device inference if the app extracts features
the same way at runtime. If you change one side's algorithm, change the
other side too, or the two projects will silently drift.

## Data leakage discipline

`split_dataset.py` groups by `batch_id`, not by individual row — see the
module docstring and §17 of the original build spec. Do not "fix" a small
dataset by switching to a random row-level split; it will inflate every
metric by leaking near-duplicate seeds from the same batch into both train
and test.

#!/usr/bin/env python3
"""Model V1 (docs/ARCHITECTURE.md §8): classical ML on extracted features.

This is the trained successor to the Dart rule engine at
app/lib/ml/rule_classifier.dart (Model V0). It exists specifically because
Model V0 was never meant to be the long-term classifier — §43 of the build
spec is explicit that V0's only job is proving the pipeline works, and V1
is "reliable hackathon demonstration" quality once real labeled data
exists.

Deliberately not a deep network (§14 of the build spec: "do not blindly use
a huge neural network") — LightGBM (or RandomForest as a dependency-light
fallback) on the same feature set the Dart FeatureExtractor computes.

Usage:
    python train_baseline.py --train dataset_v0.1/train.csv --val dataset_v0.1/val.csv --out models/v1/
"""

from __future__ import annotations

import argparse
import json
from pathlib import Path

import joblib
import pandas as pd
from sklearn.ensemble import RandomForestClassifier
from sklearn.metrics import balanced_accuracy_score, f1_score
from sklearn.preprocessing import LabelEncoder

NON_FEATURE_COLUMNS = {
    "crop",
    "batch_id",
    "source_image",
    "seed_id",
    "crop_image_file",
    "mask_file",
    "label",
    "is_augmented",
    # Absolute pixel measurements: framing / seed-density / camera-distance
    # artefacts, not shape. They were a session fingerprint in the first
    # cross-session test (docs/VALIDATION.md). The scale-invariant shape
    # features (aspect_ratio, circularity, eccentricity, convexity) stay.
    "area_px",
    "perimeter_px",
    "width_px",
    "length_px",
}

try:
    import lightgbm as lgb

    HAS_LIGHTGBM = True
except ImportError:  # pragma: no cover - environment dependent
    HAS_LIGHTGBM = False


def load_xy(csv_path: Path, label_encoder: LabelEncoder | None = None):
    df = pd.read_csv(csv_path)
    feature_columns = [c for c in df.columns if c not in NON_FEATURE_COLUMNS]
    x = df[feature_columns].to_numpy()

    if label_encoder is None:
        label_encoder = LabelEncoder()
        y = label_encoder.fit_transform(df["label"])
    else:
        y = label_encoder.transform(df["label"])

    return x, y, feature_columns, label_encoder


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--train", required=True, type=Path)
    parser.add_argument("--val", required=True, type=Path)
    parser.add_argument("--out", required=True, type=Path)
    parser.add_argument(
        "--model",
        choices=["lightgbm", "random_forest"],
        default="lightgbm" if HAS_LIGHTGBM else "random_forest",
    )
    args = parser.parse_args()

    if args.model == "lightgbm" and not HAS_LIGHTGBM:
        raise SystemExit("lightgbm is not installed. `pip install lightgbm` or pass --model random_forest.")

    x_train, y_train, feature_columns, label_encoder = load_xy(args.train)
    x_val, y_val, _, _ = load_xy(args.val, label_encoder)

    if args.model == "lightgbm":
        model = lgb.LGBMClassifier(
            n_estimators=200,
            num_leaves=15,  # kept small deliberately — this dataset is expected to be small at V1
            class_weight="balanced",
            random_state=42,
        )
    else:
        model = RandomForestClassifier(
            n_estimators=300,
            max_depth=8,
            class_weight="balanced",
            random_state=42,
        )

    model.fit(x_train, y_train)

    val_pred = model.predict(x_val)
    macro_f1 = f1_score(y_val, val_pred, average="macro")
    balanced_acc = balanced_accuracy_score(y_val, val_pred)

    args.out.mkdir(parents=True, exist_ok=True)
    joblib.dump(model, args.out / "model.joblib")
    (args.out / "label_classes.json").write_text(json.dumps(list(label_encoder.classes_)))
    (args.out / "feature_columns.json").write_text(json.dumps(feature_columns))

    metadata = {
        "model_type": args.model,
        "n_train_rows": len(x_train),
        "n_val_rows": len(x_val),
        "val_macro_f1": macro_f1,
        "val_balanced_accuracy": balanced_acc,
    }
    (args.out / "training_metadata.json").write_text(json.dumps(metadata, indent=2))

    print(json.dumps(metadata, indent=2))
    print(f"\nSaved model to {args.out}")
    print(
        "\nReminder (§19 of the build spec): do not report these numbers as a general accuracy "
        "claim without noting dataset size and diversity. Run evaluate_model.py against the "
        "held-out test.csv for the numbers that actually belong in a report."
    )


if __name__ == "__main__":
    main()

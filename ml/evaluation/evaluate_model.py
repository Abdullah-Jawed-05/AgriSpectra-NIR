#!/usr/bin/env python3
"""Evaluation report (§19 of the build spec): accuracy, precision, recall,
F1, confusion matrix, per-class performance, macro-F1 and balanced
accuracy (the metrics that matter for an imbalanced small dataset — do not
report plain accuracy alone). ROC-AUC is reported one-vs-rest per class
when the model exposes predict_proba.

Usage:
    python evaluate_model.py --model models/v1/ --test dataset_v0.1/test.csv --out models/v1/eval/
"""

from __future__ import annotations

import argparse
import json
from pathlib import Path

import joblib
import numpy as np
import pandas as pd
from sklearn.metrics import (
    balanced_accuracy_score,
    classification_report,
    confusion_matrix,
    f1_score,
    roc_auc_score,
)

NON_FEATURE_COLUMNS = {"crop", "batch_id", "source_image", "seed_id", "crop_image_file", "label"}


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--model", required=True, type=Path, help="directory from train_baseline.py")
    parser.add_argument("--test", required=True, type=Path)
    parser.add_argument("--out", required=True, type=Path)
    args = parser.parse_args()

    model = joblib.load(args.model / "model.joblib")
    label_classes = json.loads((args.model / "label_classes.json").read_text())
    feature_columns = json.loads((args.model / "feature_columns.json").read_text())

    df = pd.read_csv(args.test)
    missing = [c for c in feature_columns if c not in df.columns]
    if missing:
        raise SystemExit(f"test.csv is missing feature columns the model was trained on: {missing}")

    x_test = df[feature_columns].to_numpy()
    label_to_index = {label: i for i, label in enumerate(label_classes)}
    y_true = df["label"].map(label_to_index).to_numpy()

    y_pred = model.predict(x_test)

    report = classification_report(y_true, y_pred, target_names=label_classes, output_dict=True, zero_division=0)
    cm = confusion_matrix(y_true, y_pred, labels=list(range(len(label_classes))))
    macro_f1 = f1_score(y_true, y_pred, average="macro", zero_division=0)
    balanced_acc = balanced_accuracy_score(y_true, y_pred)

    roc_auc = None
    if hasattr(model, "predict_proba"):
        try:
            proba = model.predict_proba(x_test)
            present_classes = sorted(set(y_true))
            if len(present_classes) > 1:
                roc_auc = roc_auc_score(
                    y_true, proba, multi_class="ovr", average="macro", labels=list(range(len(label_classes)))
                )
        except ValueError:
            roc_auc = None  # e.g. a class missing entirely from the (small) test set

    args.out.mkdir(parents=True, exist_ok=True)

    result = {
        "n_test_rows": len(df),
        "n_test_batches": int(df["batch_id"].nunique()) if "batch_id" in df.columns else None,
        "macro_f1": macro_f1,
        "balanced_accuracy": balanced_acc,
        "roc_auc_ovr_macro": roc_auc,
        "per_class": report,
        "label_classes": label_classes,
    }
    (args.out / "evaluation_report.json").write_text(json.dumps(result, indent=2))
    np.savetxt(args.out / "confusion_matrix.csv", cm, fmt="%d", delimiter=",")

    predictions_df = df[["crop", "batch_id", "seed_id", "label"]].copy()
    predictions_df["predicted_label"] = [label_classes[i] for i in y_pred]
    predictions_df.to_csv(args.out / "predictions.csv", index=False)

    print(json.dumps({k: v for k, v in result.items() if k != "per_class"}, indent=2))
    print(f"\nWrote {args.out / 'evaluation_report.json'}, confusion_matrix.csv, predictions.csv")

    if len(df) < 30 or (df["batch_id"].nunique() if "batch_id" in df.columns else 0) < 3:
        print(
            "\nCAUTION: this test set is very small. Report these numbers as preliminary "
            "prototype validation on the available dataset, not as generalization performance "
            "(§19/§66 of the build spec)."
        )


if __name__ == "__main__":
    main()

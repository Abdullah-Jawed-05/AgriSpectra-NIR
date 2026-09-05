#!/usr/bin/env python3
"""Group-aware train/val/test split.

§17 of the build spec, verbatim: "Do not randomly split individual images
from the same physical batch into train and test sets... so that visually
similar samples do not leak into both training and testing." This splits by
`batch_id`, never by row — every seed from one batch lands entirely in one
split.

Usage:
    python split_dataset.py --features dataset_v0.1/features.csv --out dataset_v0.1/
"""

from __future__ import annotations

import argparse
import json
from pathlib import Path

import pandas as pd
from sklearn.model_selection import GroupShuffleSplit, StratifiedShuffleSplit


def _group_split(df: pd.DataFrame, test_fraction: float, val_fraction: float, seed: int):
    """The real thing: every batch lands entirely in one split (§17)."""
    splitter = GroupShuffleSplit(n_splits=1, test_size=test_fraction, random_state=seed)
    trainval_idx, test_idx = next(splitter.split(df, groups=df["batch_id"]))
    trainval_df = df.iloc[trainval_idx]

    val_splitter = GroupShuffleSplit(n_splits=1, test_size=val_fraction, random_state=seed)
    train_idx, val_idx = next(val_splitter.split(trainval_df, groups=trainval_df["batch_id"]))
    return trainval_df.iloc[train_idx], trainval_df.iloc[val_idx], df.iloc[test_idx]


def _stratified_row_split(df: pd.DataFrame, test_fraction: float, val_fraction: float, seed: int):
    """Fallback for a single-batch dataset, where a group split is
    mathematically impossible (there is nothing to hold a group out
    *from*). Splits by row, stratified by label so every class appears in
    every split.

    This is NOT leakage-safe — near-duplicate seeds from the same shoot can
    land on both sides — and must never be reported as a generalization
    estimate (§17/§66). It only answers "does the model learn to tell the
    classes apart at all," which is what a single-batch dataset can
    actually support (see docs/DATASET_GUIDE.md).
    """
    splitter = StratifiedShuffleSplit(n_splits=1, test_size=test_fraction, random_state=seed)
    trainval_idx, test_idx = next(splitter.split(df, df["label"]))
    trainval_df = df.iloc[trainval_idx]

    val_splitter = StratifiedShuffleSplit(n_splits=1, test_size=val_fraction, random_state=seed)
    train_idx, val_idx = next(val_splitter.split(trainval_df, trainval_df["label"]))
    return trainval_df.iloc[train_idx], trainval_df.iloc[val_idx], df.iloc[test_idx]


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--features", required=True, type=Path)
    parser.add_argument("--out", required=True, type=Path)
    parser.add_argument("--test-fraction", type=float, default=0.2)
    parser.add_argument("--val-fraction", type=float, default=0.15, help="fraction of the remaining train pool")
    parser.add_argument("--seed", type=int, default=42)
    args = parser.parse_args()

    df = pd.read_csv(args.features)
    if "batch_id" not in df.columns:
        raise SystemExit("features.csv must have a batch_id column (produced by prepare_dataset.py)")

    n_batches = df["batch_id"].nunique()
    leakage_safe = n_batches >= 2
    if n_batches < 2:
        print(
            f"WARNING: only {n_batches} distinct batch in this dataset — a group split needs at "
            "least 2 to hold anything out. Falling back to a label-stratified ROW split. This is "
            "NOT leakage-safe (near-duplicate seeds from the same shoot can land on both sides) "
            "and must not be reported as a generalization estimate — it only checks whether the "
            "model learns to separate the classes at all. Collect more batches to get a real "
            "held-out test (see docs/DATASET_GUIDE.md)."
        )
    elif n_batches < 3:
        print(
            f"WARNING: only {n_batches} distinct batches in this dataset. A group split "
            "needs several batches per split to be meaningful — this split will be thin "
            "until more batches are collected (see docs/DATASET_GUIDE.md).",
        )

    if leakage_safe:
        train_df, val_df, test_df = _group_split(df, args.test_fraction, args.val_fraction, args.seed)
    else:
        train_df, val_df, test_df = _stratified_row_split(df, args.test_fraction, args.val_fraction, args.seed)

    args.out.mkdir(parents=True, exist_ok=True)
    train_df.to_csv(args.out / "train.csv", index=False)
    val_df.to_csv(args.out / "val.csv", index=False)
    test_df.to_csv(args.out / "test.csv", index=False)

    train_batches = set(train_df["batch_id"])
    val_batches = set(val_df["batch_id"])
    test_batches = set(test_df["batch_id"])
    if leakage_safe:
        assert not (train_batches & val_batches), "leak: batch in both train and val"
        assert not (train_batches & test_batches), "leak: batch in both train and test"
        assert not (val_batches & test_batches), "leak: batch in both val and test"

    summary = {
        "leakage_safe": leakage_safe,
        "train": {"rows": len(train_df), "batches": len(train_batches)},
        "val": {"rows": len(val_df), "batches": len(val_batches)},
        "test": {"rows": len(test_df), "batches": len(test_batches)},
    }
    if not leakage_safe:
        summary["note"] = (
            "Row-level stratified split, not a group split — only one batch exists. Not "
            "leakage-safe; sanity-check numbers only, not a generalization estimate."
        )
    (args.out / "split_summary.json").write_text(json.dumps(summary, indent=2))

    print(json.dumps(summary, indent=2))
    if leakage_safe:
        print("\nNo batch appears in more than one split (verified).")
    else:
        print("\nNOT a leakage-safe split — see 'note' in split_summary.json.")


if __name__ == "__main__":
    main()

#!/usr/bin/env python3
"""Group-aware train/val/test split.

§17 of the build spec, verbatim: "Do not randomly split individual images
from the same physical batch into train and test sets... so that visually
similar samples do not leak into both training and testing." The **test**
set is always a whole held-out batch (or batches) when more than one
exists — that's the number you're allowed to report as generalization.

The **val** set is only for early stopping / hyperparameter choice, so if
the remaining train pool has just one batch, val is carved from it by a
label-stratified row split — val leaking into train doesn't touch the
reported test metric.

With only one batch total, nothing can be held out at all: the whole
split degrades to stratified rows and is explicitly flagged not
leakage-safe (a sanity check, not a generalization estimate).

Usage:
    python split_dataset.py --features dataset_v0.2/features.csv --out dataset_v0.2/
    python split_dataset.py --features ... --out ... --test-batch batch_2026-08_lot1
"""

from __future__ import annotations

import argparse
import json
from pathlib import Path

import pandas as pd
from sklearn.model_selection import GroupShuffleSplit, StratifiedShuffleSplit


def _stratified_val(trainval_df: pd.DataFrame, val_fraction: float, seed: int):
    splitter = StratifiedShuffleSplit(n_splits=1, test_size=val_fraction, random_state=seed)
    train_idx, val_idx = next(splitter.split(trainval_df, trainval_df["label"]))
    return trainval_df.iloc[train_idx], trainval_df.iloc[val_idx]


def _group_val(trainval_df: pd.DataFrame, val_fraction: float, seed: int):
    splitter = GroupShuffleSplit(n_splits=1, test_size=val_fraction, random_state=seed)
    train_idx, val_idx = next(splitter.split(trainval_df, groups=trainval_df["batch_id"]))
    return trainval_df.iloc[train_idx], trainval_df.iloc[val_idx]


def _split(df: pd.DataFrame, test_fraction: float, val_fraction: float, seed: int, test_batch: str | None):
    n_batches = df["batch_id"].nunique()

    if n_batches < 2:
        # Nothing to hold out — whole split is stratified rows.
        s = StratifiedShuffleSplit(n_splits=1, test_size=test_fraction, random_state=seed)
        trainval_idx, test_idx = next(s.split(df, df["label"]))
        trainval_df = df.iloc[trainval_idx]
        train_df, val_df = _stratified_val(trainval_df, val_fraction, seed)
        return train_df, val_df, df.iloc[test_idx], {"test_leakage_safe": False, "val_leakage_safe": False}

    # Test = a whole held-out batch (clean).
    if test_batch is not None:
        if test_batch not in set(df["batch_id"]):
            raise SystemExit(f"--test-batch {test_batch!r} not found. Batches: {sorted(set(df['batch_id']))}")
        test_df = df[df["batch_id"] == test_batch]
        trainval_df = df[df["batch_id"] != test_batch]
    else:
        s = GroupShuffleSplit(n_splits=1, test_size=test_fraction, random_state=seed)
        trainval_idx, test_idx = next(s.split(df, groups=df["batch_id"]))
        trainval_df, test_df = df.iloc[trainval_idx], df.iloc[test_idx]

    # Val from the train pool — group split if it still has >=2 batches,
    # otherwise stratified rows (only affects early stopping, not the test metric).
    if trainval_df["batch_id"].nunique() >= 2:
        train_df, val_df = _group_val(trainval_df, val_fraction, seed)
        val_leakage_safe = True
    else:
        train_df, val_df = _stratified_val(trainval_df, val_fraction, seed)
        val_leakage_safe = False

    return train_df, val_df, test_df, {"test_leakage_safe": True, "val_leakage_safe": val_leakage_safe}


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--features", required=True, type=Path)
    parser.add_argument("--out", required=True, type=Path)
    parser.add_argument("--test-fraction", type=float, default=0.2)
    parser.add_argument("--val-fraction", type=float, default=0.15, help="fraction of the remaining train pool")
    parser.add_argument("--seed", type=int, default=42)
    parser.add_argument("--test-batch", type=str, default=None, help="hold out this exact batch_id as the test set")
    args = parser.parse_args()

    df = pd.read_csv(args.features)
    if "batch_id" not in df.columns:
        raise SystemExit("features.csv must have a batch_id column (produced by prepare_dataset.py)")

    n_batches = df["batch_id"].nunique()
    if n_batches < 2:
        print(
            "WARNING: only 1 distinct batch — a group split needs at least 2 to hold anything "
            "out. Whole split falls back to stratified rows: NOT leakage-safe, a sanity check "
            "only, never a generalization estimate (see docs/DATASET_GUIDE.md)."
        )
    elif n_batches == 2:
        print(
            "NOTE: 2 batches — test is a clean held-out batch (a real cross-session "
            "generalization number), but val is a stratified row split of the single "
            "remaining train batch (fine — val only drives early stopping)."
        )

    train_df, val_df, test_df, flags = _split(
        df, args.test_fraction, args.val_fraction, args.seed, args.test_batch
    )

    args.out.mkdir(parents=True, exist_ok=True)
    train_df.to_csv(args.out / "train.csv", index=False)
    val_df.to_csv(args.out / "val.csv", index=False)
    test_df.to_csv(args.out / "test.csv", index=False)

    train_batches = set(train_df["batch_id"])
    test_batches = set(test_df["batch_id"])
    if flags["test_leakage_safe"]:
        assert not (train_batches & test_batches), "leak: batch in both train and test"
        assert not (set(val_df["batch_id"]) & test_batches), "leak: batch in both val and test"

    summary = {
        **flags,
        "train": {"rows": len(train_df), "batches": sorted(train_batches)},
        "val": {"rows": len(val_df), "batches": sorted(set(val_df["batch_id"]))},
        "test": {"rows": len(test_df), "batches": sorted(test_batches)},
        "test_label_distribution": test_df["label"].value_counts().to_dict(),
    }
    (args.out / "split_summary.json").write_text(json.dumps(summary, indent=2))
    print(json.dumps(summary, indent=2))


if __name__ == "__main__":
    main()

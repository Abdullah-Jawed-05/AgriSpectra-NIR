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
from sklearn.model_selection import GroupShuffleSplit


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
    if n_batches < 3:
        print(
            f"WARNING: only {n_batches} distinct batch(es) in this dataset. A group split "
            "needs multiple batches per split to be meaningful — this split will be degenerate "
            "until more batches are collected (see docs/DATASET_GUIDE.md).",
        )

    splitter = GroupShuffleSplit(n_splits=1, test_size=args.test_fraction, random_state=args.seed)
    trainval_idx, test_idx = next(splitter.split(df, groups=df["batch_id"]))
    trainval_df = df.iloc[trainval_idx]

    val_splitter = GroupShuffleSplit(n_splits=1, test_size=args.val_fraction, random_state=args.seed)
    train_idx, val_idx = next(val_splitter.split(trainval_df, groups=trainval_df["batch_id"]))
    train_df = trainval_df.iloc[train_idx]
    val_df = trainval_df.iloc[val_idx]
    test_df = df.iloc[test_idx]

    args.out.mkdir(parents=True, exist_ok=True)
    train_df.to_csv(args.out / "train.csv", index=False)
    val_df.to_csv(args.out / "val.csv", index=False)
    test_df.to_csv(args.out / "test.csv", index=False)

    train_batches = set(train_df["batch_id"])
    val_batches = set(val_df["batch_id"])
    test_batches = set(test_df["batch_id"])
    assert not (train_batches & val_batches), "leak: batch in both train and val"
    assert not (train_batches & test_batches), "leak: batch in both train and test"
    assert not (val_batches & test_batches), "leak: batch in both val and test"

    summary = {
        "train": {"rows": len(train_df), "batches": len(train_batches)},
        "val": {"rows": len(val_df), "batches": len(val_batches)},
        "test": {"rows": len(test_df), "batches": len(test_batches)},
    }
    (args.out / "split_summary.json").write_text(json.dumps(summary, indent=2))

    print(json.dumps(summary, indent=2))
    print("\nNo batch appears in more than one split (verified).")


if __name__ == "__main__":
    main()

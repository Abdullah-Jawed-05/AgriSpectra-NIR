#!/usr/bin/env python3
"""Augment a training split (§18 of the build spec): small rotation/scale/
flip/brightness/contrast/blur/noise on each already-segmented seed crop,
re-extracting the full feature set (geometry recomputed from the augmented
mask, not reused from the original) so augmented rows are feature-complete
and consistent with real ones.

Run this AFTER split_dataset.py, on train.csv only — never on val.csv or
test.csv. Augmenting before the split (or augmenting eval data at all)
would leak near-duplicates of eval rows into training, or inflate eval
metrics with easy near-duplicates of training rows; either way the
numbers would stop meaning anything (§17/§66 of the build spec).

Usage:
    python augment_dataset.py --train dataset_v0.1/train.csv \\
        --crops-dir dataset_v0.1/crops --masks-dir dataset_v0.1/masks \\
        --out dataset_v0.1/ --multiplier 3
"""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

import cv2
import numpy as np
import pandas as pd

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
from preprocessing.augmentation import random_augment  # noqa: E402
from preprocessing.features import extract_all  # noqa: E402
from preprocessing.segmentation import SegmentedSeed, geometry_from_mask  # noqa: E402


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--train", required=True, type=Path, help="train.csv from split_dataset.py")
    parser.add_argument("--crops-dir", required=True, type=Path)
    parser.add_argument("--masks-dir", required=True, type=Path)
    parser.add_argument("--out", required=True, type=Path)
    parser.add_argument("--multiplier", type=int, default=3, help="augmented variants per original row")
    parser.add_argument("--seed", type=int, default=42)
    args = parser.parse_args()

    df = pd.read_csv(args.train)
    rng = np.random.default_rng(args.seed)

    args.out.mkdir(parents=True, exist_ok=True)
    aug_crops_dir = args.out / "augmented_crops"
    aug_crops_dir.mkdir(exist_ok=True)

    original_rows = df.copy()
    original_rows["is_augmented"] = False

    augmented_rows = []
    skipped = 0

    for _, row in df.iterrows():
        crop_path = args.crops_dir / row["crop_image_file"]
        mask_path = args.masks_dir / row["mask_file"]
        crop_bgr = cv2.imread(str(crop_path))
        mask = cv2.imread(str(mask_path), cv2.IMREAD_GRAYSCALE)
        if crop_bgr is None or mask is None:
            print(f"WARNING: could not read {crop_path} / {mask_path}, skipping", file=sys.stderr)
            continue

        for v in range(args.multiplier):
            aug_crop, aug_mask = random_augment(crop_bgr, mask, rng)
            geometry = geometry_from_mask(aug_mask)
            if geometry["perimeter_px"] <= 0:
                skipped += 1
                continue

            seed = SegmentedSeed(
                seed_id=f"{row['seed_id']}_aug{v}",
                crop_bgr=aug_crop,
                mask=aug_mask,
                bbox=(0, 0, aug_mask.shape[1], aug_mask.shape[0]),
                **geometry,
            )
            features = extract_all(seed)

            aug_filename = f"{Path(row['crop_image_file']).stem}_aug{v}.png"
            cv2.imwrite(str(aug_crops_dir / aug_filename), aug_crop)

            augmented_rows.append(
                {
                    "crop": row["crop"],
                    "batch_id": row["batch_id"],
                    "source_image": row["source_image"],
                    "seed_id": seed.seed_id,
                    "crop_image_file": aug_filename,
                    "mask_file": "",
                    "label": row["label"],
                    "is_augmented": True,
                    **features,
                }
            )

    combined = pd.concat([original_rows, pd.DataFrame(augmented_rows)], ignore_index=True)
    out_csv = args.out / "train_augmented.csv"
    combined.to_csv(out_csv, index=False)

    print(f"Original rows: {len(df)}")
    print(f"Augmented rows added: {len(augmented_rows)} (skipped {skipped} degenerate variants)")
    print(f"Wrote {out_csv} ({len(combined)} total rows)")
    print("\nLabel distribution (combined):")
    print(combined["label"].value_counts().to_string())
    print(
        "\nTrain train_baseline.py on this file instead of train.csv to use the "
        "augmented data — val.csv/test.csv are untouched and stay real."
    )


if __name__ == "__main__":
    main()

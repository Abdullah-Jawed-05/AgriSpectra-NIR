#!/usr/bin/env python3
"""Turn a raw collected-image directory into a flat feature dataset.

Expected input layout (this is what the "data collection application",
§44 of the build spec, should eventually produce automatically):

    raw/<crop>/<batch_id>/<label>/<image files>.jpg

    e.g. raw/wheat/batch_2026-08-01_farmA/GOOD/img001.jpg
         raw/wheat/batch_2026-08-01_farmA/DAMAGED/img002.jpg

`label` must be one of the QualityClass storage keys in
app/lib/domain/value_objects/quality_class.dart (GOOD, DAMAGED, DISCOLORED,
SHRIVELED, MOLD_SUSPECT, INSECT_DAMAGED, UNKNOWN) — these are labels a human
assigned by looking at the seed, not a claim about germination (§15/§16 of
the build spec; do not repurpose this pipeline to output germination
predictions without real lab ground truth wired through a different label
column).

Each image may contain multiple seeds; every detected seed becomes one row,
inheriting the image's label. `batch_id` is carried through to every row so
split_dataset.py can group-split without leaking near-duplicate seeds from
the same physical batch across train/test (§17 of the build spec).

Usage:
    python prepare_dataset.py --raw-dir raw/ --out dataset_v0.1/
"""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

import cv2
import pandas as pd

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
from preprocessing.features import extract_all  # noqa: E402
from preprocessing.segmentation import find_seeds  # noqa: E402

VALID_LABELS = {
    "GOOD",
    "DAMAGED",
    "DISCOLORED",
    "SHRIVELED",
    "MOLD_SUSPECT",
    "INSECT_DAMAGED",
    "UNKNOWN",
}

IMAGE_EXTENSIONS = {".jpg", ".jpeg", ".png"}


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--raw-dir", required=True, type=Path, help="raw/<crop>/<batch_id>/<label>/*.jpg")
    parser.add_argument("--out", required=True, type=Path, help="output directory for features.csv + crops/")
    args = parser.parse_args()

    if not args.raw_dir.exists():
        raise SystemExit(
            f"Raw data directory not found: {args.raw_dir}\n"
            "This script does not fabricate a dataset — point it at real collected images "
            "structured as raw/<crop>/<batch_id>/<label>/*.jpg (see docs/DATASET_GUIDE.md)."
        )

    args.out.mkdir(parents=True, exist_ok=True)
    crops_dir = args.out / "crops"
    crops_dir.mkdir(exist_ok=True)

    rows = []
    n_images = 0
    n_seeds = 0

    for crop_dir in sorted(p for p in args.raw_dir.iterdir() if p.is_dir()):
        crop_name = crop_dir.name
        for batch_dir in sorted(p for p in crop_dir.iterdir() if p.is_dir()):
            batch_id = batch_dir.name
            for label_dir in sorted(p for p in batch_dir.iterdir() if p.is_dir()):
                label = label_dir.name.upper()
                if label not in VALID_LABELS:
                    print(f"WARNING: skipping unrecognized label directory '{label_dir}'", file=sys.stderr)
                    continue

                for image_path in sorted(label_dir.iterdir()):
                    if image_path.suffix.lower() not in IMAGE_EXTENSIONS:
                        continue

                    image = cv2.imread(str(image_path))
                    if image is None:
                        print(f"WARNING: could not read {image_path}", file=sys.stderr)
                        continue
                    n_images += 1

                    seeds = find_seeds(image)
                    for seed in seeds:
                        features = extract_all(seed)
                        crop_filename = f"{crop_name}_{batch_id}_{image_path.stem}_{seed.seed_id}.png"
                        cv2.imwrite(str(crops_dir / crop_filename), seed.crop_bgr)

                        rows.append(
                            {
                                "crop": crop_name,
                                "batch_id": batch_id,
                                "source_image": image_path.name,
                                "seed_id": seed.seed_id,
                                "crop_image_file": crop_filename,
                                "label": label,
                                **features,
                            }
                        )
                        n_seeds += 1

    if not rows:
        raise SystemExit(
            "No seeds were extracted from any image. Check that raw-dir follows "
            "raw/<crop>/<batch_id>/<label>/*.jpg and that images have sufficient contrast "
            "for the classical detector (see app/lib/ml/image_quality_gate.dart for what "
            "'sufficient contrast' means)."
        )

    df = pd.DataFrame(rows)
    out_csv = args.out / "features.csv"
    df.to_csv(out_csv, index=False)

    print(f"Processed {n_images} images -> {n_seeds} seed rows.")
    print(f"Wrote {out_csv}")
    print(f"Wrote {n_seeds} crop images to {crops_dir}")
    print("\nLabel distribution:")
    print(df["label"].value_counts().to_string())
    print(f"\nBatches: {df['batch_id'].nunique()} (split_dataset.py groups by this column)")


if __name__ == "__main__":
    main()

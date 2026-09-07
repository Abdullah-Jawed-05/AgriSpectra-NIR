#!/usr/bin/env python3
"""Point this at a flat folder of seed captures and it reports what the
vision pipeline sees — before any labelling or training. It runs the same
steps the app runs (background-texture gate -> lighting normalisation ->
segmentation -> touching-seed split -> feature extraction) and writes one
CSV row per image plus a summary.

Use it to triage a new collection session: how many frames are usable,
which are rejected for a textured background, single vs multi seed, and
whether the feature distributions look sane.

    python ml/scripts/analyze_capture_set.py --dir "path/to/captures" --out out/wheat

This does NOT produce a training dataset — that needs per-image labels
(prepare_dataset.py, raw/<crop>/<label>/*.jpg).
"""
from __future__ import annotations

import argparse
import sys
from pathlib import Path

import cv2
import numpy as np
import pandas as pd

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
from preprocessing.features import extract_all  # noqa: E402
from preprocessing.segmentation import (  # noqa: E402
    assess_background_texture,
    pick_primary_seed,
    segment,
)

IMAGE_EXTS = {".jpg", ".jpeg", ".png"}

FEATURE_KEYS = [
    "area_px", "aspect_ratio", "circularity", "eccentricity", "convexity",
    "dark_region_ratio", "crack_like_edge_ratio", "hole_ratio",
    "discoloration_ratio", "mean_hue", "mean_saturation", "mean_value",
]


def imread_unicode(path: Path):
    data = np.fromfile(str(path), dtype=np.uint8)
    return cv2.imdecode(data, cv2.IMREAD_COLOR)


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--dir", required=True, type=Path)
    ap.add_argument("--out", required=True, type=Path)
    ap.add_argument("--save-crops", action="store_true", help="also write each primary-seed crop for eyeballing")
    args = ap.parse_args()

    files = sorted(p for p in args.dir.rglob("*") if p.suffix.lower() in IMAGE_EXTS)
    if not files:
        raise SystemExit(f"No images under {args.dir}")

    args.out.mkdir(parents=True, exist_ok=True)
    crops_dir = args.out / "primary_crops"
    if args.save_crops:
        crops_dir.mkdir(exist_ok=True)

    rows = []
    for i, path in enumerate(files, 1):
        img = imread_unicode(path)
        if img is None:
            print(f"  ! unreadable: {path.name}", file=sys.stderr)
            continue

        tex = assess_background_texture(img)
        row = {
            "file": path.name,
            "width": img.shape[1],
            "height": img.shape[0],
            "bg_median_tile_std": round(tex.median_tile_stddev, 2),
            "bg_busy_tile_ratio": round(tex.busy_tile_ratio, 3),
            "bg_flat_tile_ratio": round(tex.flat_tile_ratio, 3),
            "bg_textured": tex.is_textured,
        }

        result = segment(img)
        seeds = result.seeds
        row["seeds_found"] = len(seeds)
        row["channel"] = result.channel
        row["piled"] = result.piled
        primary = pick_primary_seed(seeds)
        if primary is not None:
            feats = extract_all(primary)
            for k in FEATURE_KEYS:
                row[k] = round(float(feats[k]), 4) if k in feats else None
            if args.save_crops:
                cv2.imwrite(str(crops_dir / f"{path.stem}.png"), primary.crop_bgr)
        rows.append(row)
        if i % 20 == 0 or i == len(files):
            print(f"  {i}/{len(files)}")

    df = pd.DataFrame(rows)
    csv = args.out / "capture_analysis.csv"
    df.to_csv(csv, index=False)

    n = len(df)
    textured = int(df["bg_textured"].sum())
    no_seed = int((df["seeds_found"] == 0).sum())
    piled = int(df["piled"].sum())
    print(f"\n=== {args.dir.name}: {n} images ===")
    print(f"Wrote {csv}")
    print(f"  textured background (would be rejected at capture): {textured}/{n} ({100*textured/n:.0f}%)")
    print(f"  no seed segmented:                                  {no_seed}/{n} ({100*no_seed/n:.0f}%)")
    print(f"  seeds piled / touching (rejected at capture):       {piled}/{n} ({100*piled/n:.0f}%)")
    usable = df[(~df["bg_textured"]) & (~df["piled"]) & (df["seeds_found"] >= 1)]
    print(f"  clean, spread out, at least one seed:               {len(usable)}/{n} ({100*len(usable)/n:.0f}%)")
    if not usable.empty:
        print("\n  primary-seed feature ranges on the usable frames (p10 / p50 / p90):")
        for k in FEATURE_KEYS:
            if k in usable:
                v = usable[k].dropna()
                if not v.empty:
                    print(f"    {k:24s} {np.percentile(v,10):8.3f} {np.percentile(v,50):8.3f} {np.percentile(v,90):8.3f}")


if __name__ == "__main__":
    main()

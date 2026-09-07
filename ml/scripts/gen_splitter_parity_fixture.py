#!/usr/bin/env python3
"""Generate the touching-seed-splitter parity fixture.

Writes app/test/ml/fixtures/seed_splitter_parity.json: a set of synthetic
component masks plus the exact split `split_component` produces for each
(part count and sorted part sizes). `seed_splitter_parity_test.dart` runs
the Dart `SeedSplitter` over the same masks and must match — this is what
keeps ml/preprocessing/seed_splitter.py and app/lib/ml/seed_splitter.dart
from drifting apart (§11 / docs/ML_PIPELINE.md).

    python ml/scripts/gen_splitter_parity_fixture.py
"""
from __future__ import annotations

import base64
import json
import sys
from pathlib import Path

import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
from preprocessing.seed_splitter import split_component  # noqa: E402

OUT = Path(__file__).resolve().parent.parent.parent / "app/test/ml/fixtures/seed_splitter_parity.json"


def disc(mask, cx, cy, r):
    h, w = mask.shape
    yy, xx = np.ogrid[:h, :w]
    mask[(xx - cx) ** 2 + (yy - cy) ** 2 <= r * r] = 1


def pepper(mask, seed, holes):
    """Punch random 1px holes — the thresholded masks from the real
    pipeline are never solid."""
    rng = np.random.default_rng(seed)
    ys, xs = np.nonzero(mask)
    pick = rng.choice(len(ys), size=min(holes, len(ys)), replace=False)
    mask[ys[pick], xs[pick]] = 0


def cases():
    # single grain — must NOT split
    m = np.zeros((90, 90), np.uint8)
    disc(m, 45, 45, 30)
    yield "single_disc", m

    m = np.zeros((70, 140), np.uint8)
    disc(m, 42, 35, 30)
    disc(m, 98, 35, 30)
    yield "touching_pair", m

    m = np.zeros((70, 140), np.uint8)
    disc(m, 42, 35, 30)
    disc(m, 98, 35, 30)
    pepper(m, 1, 260)
    yield "touching_pair_peppered", m

    m = np.zeros((70, 200), np.uint8)
    for cx in (40, 100, 160):
        disc(m, cx, 35, 26)
    yield "row_of_three", m

    m = np.zeros((130, 130), np.uint8)
    disc(m, 42, 46, 26)
    disc(m, 82, 82, 26)  # centres ~53 apart, r 26 -> just touching
    yield "diagonal_pair", m

    # a single lumpy grain (two bumps but one convex blob) must NOT split
    m = np.zeros((80, 120), np.uint8)
    disc(m, 52, 40, 30)
    disc(m, 68, 40, 30)  # centres 16 apart -> one grain with a waist
    yield "lumpy_single", m

    # barely touching — separation ~= 2r, a shallow neck
    m = np.zeros((80, 160), np.uint8)
    disc(m, 45, 40, 34)
    disc(m, 112, 40, 34)
    yield "kissing_pair", m


def rle(mask: np.ndarray) -> str:
    return base64.b64encode(np.packbits(mask.astype(bool)).tobytes()).decode()


def main():
    entries = []
    for name, mask in cases():
        parts = split_component(mask)
        sizes = sorted(int(p.sum()) for p in parts)
        entries.append(
            {
                "name": name,
                "h": mask.shape[0],
                "w": mask.shape[1],
                "mask_b64": rle(mask),
                "part_count": len(parts),
                "part_sizes": sizes,
            }
        )
    OUT.parent.mkdir(parents=True, exist_ok=True)
    OUT.write_text(json.dumps(entries, indent=2))
    print(f"wrote {OUT} ({len(entries)} cases)")
    for e in entries:
        print(f"  {e['name']:24s} -> {e['part_count']} parts {e['part_sizes']}")


if __name__ == "__main__":
    main()

#!/usr/bin/env python3
"""Dev-only tool: run the Python segmentation+feature pipeline over one
image and dump each detected seed's features as JSON, in the same shape
app/tool/parity_check.dart produces for the Dart pipeline — for diffing the
two (the Python<->Dart feature-parity check, docs/ML_PIPELINE.md).

Usage: python parity_check.py <path/to/image.jpg>
"""
from __future__ import annotations

import json
import sys
from pathlib import Path

import cv2
import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
from preprocessing.features import extract_all  # noqa: E402
from preprocessing.segmentation import find_seeds  # noqa: E402


def main() -> None:
    if len(sys.argv) < 2:
        print("Usage: python parity_check.py <image_path>", file=sys.stderr)
        raise SystemExit(1)

    image = cv2.imread(sys.argv[1])
    if image is None:
        print(f"Could not read image: {sys.argv[1]}", file=sys.stderr)
        raise SystemExit(1)

    seeds = find_seeds(image)
    out = []
    for seed in seeds:
        features = extract_all(seed)
        x, y, w, h = seed.bbox
        ys, xs = np.nonzero(seed.mask)
        out.append(
            {
                "seed_id": seed.seed_id,
                "center_x": x + float(xs.mean()),
                "center_y": y + float(ys.mean()),
                "bbox": [x, y, w, h],
                **features,
            }
        )
    print(json.dumps(out, indent=2))


if __name__ == "__main__":
    main()

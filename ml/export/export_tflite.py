#!/usr/bin/env python3
"""Converts a Model V2 SavedModel (train_cnn.py output) to TFLite for
on-device inference via the `tflite_flutter` package already wired into
app/pubspec.yaml (unused until a real model exists — see
docs/ARCHITECTURE.md §8).

Usage:
    python export_tflite.py --saved-model models/v2/saved_model --out models/v2/model.tflite
"""

from __future__ import annotations

import argparse
from pathlib import Path

try:
    import tensorflow as tf
except ImportError:
    tf = None


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--saved-model", required=True, type=Path)
    parser.add_argument("--out", required=True, type=Path)
    parser.add_argument("--quantize", action="store_true", help="dynamic-range int8 quantization for mobile")
    args = parser.parse_args()

    if tf is None:
        raise SystemExit("TensorFlow is not installed — see train_cnn.py for when this phase starts.")
    if not args.saved_model.exists():
        raise SystemExit(f"{args.saved_model} does not exist. Run train_cnn.py first.")

    converter = tf.lite.TFLiteConverter.from_saved_model(str(args.saved_model))
    if args.quantize:
        converter.optimizations = [tf.lite.Optimize.DEFAULT]

    tflite_model = converter.convert()
    args.out.parent.mkdir(parents=True, exist_ok=True)
    args.out.write_bytes(tflite_model)

    size_kb = args.out.stat().st_size / 1024
    print(f"Wrote {args.out} ({size_kb:.0f} KB)")


if __name__ == "__main__":
    main()

#!/usr/bin/env python3
"""Exports the Model V1 classical baseline (train_baseline.py output) to
ONNX — the practical interoperable format for a scikit-learn/LightGBM
model, letting it run outside Python (e.g. a future desktop/cloud
inference path in docs/ARCHITECTURE.md §8) without re-implementing the
model. The Flutter app does not consume this yet; V0's Dart rule engine is
still what ships (see app/lib/ml/rule_classifier.dart).

Usage:
    python export_onnx.py --model models/v1/ --out models/v1/model.onnx
"""

from __future__ import annotations

import argparse
import json
from pathlib import Path

import joblib
from skl2onnx import convert_sklearn
from skl2onnx.common.data_types import FloatTensorType


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--model", required=True, type=Path, help="directory from train_baseline.py")
    parser.add_argument("--out", required=True, type=Path)
    args = parser.parse_args()

    model = joblib.load(args.model / "model.joblib")
    feature_columns = json.loads((args.model / "feature_columns.json").read_text())

    initial_type = [("input", FloatTensorType([None, len(feature_columns)]))]
    onnx_model = convert_sklearn(model, initial_types=initial_type)

    args.out.parent.mkdir(parents=True, exist_ok=True)
    args.out.write_bytes(onnx_model.SerializeToString())

    print(f"Wrote {args.out}")
    print(f"Input: float32[N, {len(feature_columns)}], columns in order: {feature_columns}")


if __name__ == "__main__":
    main()

#!/usr/bin/env python3
"""Model V2 (docs/ARCHITECTURE.md §8): lightweight CNN / transfer learning.

Not part of the hackathon MVP — the rule engine (V0) and classical baseline
(V1, train_baseline.py) are what ship first (§14 of the build spec: choose
the approach that trades off accuracy/dataset-size/training-time/
explainability/mobile-inference-speed/dev-complexity well; a CNN only wins
that tradeoff once there's enough image data to actually benefit from it).

Requires `tensorflow` (see requirements.txt — commented out until this
phase actually starts) and an image-folder dataset:

    images/train/<label>/*.png
    images/val/<label>/*.png

Build image folders from prepare_dataset.py's crops/ output with a helper
script once a real dataset exists — the crops there are keyed by
seed_id/batch_id/label but flattened into one directory, so a class-labeled
symlink farm is a few lines away when this phase starts.

Usage (once TensorFlow is installed and image folders exist):
    python train_cnn.py --train images/train --val images/val --out models/v2/
"""

from __future__ import annotations

import argparse
import json
from pathlib import Path

try:
    import tensorflow as tf
except ImportError:
    tf = None

IMAGE_SIZE = (160, 160)
BATCH_SIZE = 16


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--train", required=True, type=Path)
    parser.add_argument("--val", required=True, type=Path)
    parser.add_argument("--out", required=True, type=Path)
    parser.add_argument("--epochs", type=int, default=20)
    parser.add_argument("--base-model", choices=["mobilenet_v2", "efficientnet_lite"], default="mobilenet_v2")
    args = parser.parse_args()

    if tf is None:
        raise SystemExit(
            "TensorFlow is not installed. This is expected until Model V2 work actually starts "
            "(see docs/ARCHITECTURE.md roadmap) — `pip install tensorflow` and uncomment it in "
            "ml/requirements.txt when it does."
        )

    if not args.train.exists() or not args.val.exists():
        raise SystemExit(
            f"Expected image-folder datasets at {args.train} and {args.val} "
            "(images/train/<label>/*.png, images/val/<label>/*.png). None exist yet — "
            "this is Model V2, gated on Model V1 (train_baseline.py) and a larger image dataset."
        )

    train_ds = tf.keras.utils.image_dataset_from_directory(
        args.train, image_size=IMAGE_SIZE, batch_size=BATCH_SIZE
    )
    val_ds = tf.keras.utils.image_dataset_from_directory(args.val, image_size=IMAGE_SIZE, batch_size=BATCH_SIZE)
    class_names = train_ds.class_names

    if args.base_model == "mobilenet_v2":
        base = tf.keras.applications.MobileNetV2(
            input_shape=IMAGE_SIZE + (3,), include_top=False, weights="imagenet"
        )
        preprocess = tf.keras.applications.mobilenet_v2.preprocess_input
    else:
        base = tf.keras.applications.EfficientNetB0(
            input_shape=IMAGE_SIZE + (3,), include_top=False, weights="imagenet"
        )
        preprocess = tf.keras.applications.efficientnet.preprocess_input

    base.trainable = False  # transfer learning, not full fine-tuning, given expected dataset size

    inputs = tf.keras.Input(shape=IMAGE_SIZE + (3,))
    x = preprocess(inputs)
    x = base(x, training=False)
    x = tf.keras.layers.GlobalAveragePooling2D()(x)
    x = tf.keras.layers.Dropout(0.3)(x)
    outputs = tf.keras.layers.Dense(len(class_names), activation="softmax")(x)
    model = tf.keras.Model(inputs, outputs)

    model.compile(optimizer="adam", loss="sparse_categorical_crossentropy", metrics=["accuracy"])
    history = model.fit(train_ds, validation_data=val_ds, epochs=args.epochs)

    args.out.mkdir(parents=True, exist_ok=True)
    model.save(args.out / "saved_model")
    (args.out / "class_names.json").write_text(json.dumps(class_names))
    (args.out / "history.json").write_text(json.dumps({k: [float(v) for v in vs] for k, vs in history.history.items()}))

    print(f"Saved model to {args.out / 'saved_model'}")
    print("Next: export_tflite.py to convert for on-device inference.")


if __name__ == "__main__":
    main()

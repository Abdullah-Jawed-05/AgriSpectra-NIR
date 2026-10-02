#!/usr/bin/env python3
"""Export a trained model.joblib as dependency-free Dart for the Flutter app
("Promote to App", docs/TRAINER_APP_BUILD_PROMPT.md section 4).

Usage:
    python export_dart.py --model-dir <train_baseline.py --out dir> --export-dir <dir> [--version-label v1]

Writes model_v1_generated.dart (the model's decision logic, via m2cgen,
with a scikit-learn tree-introspection fallback), agrispectra_model_v1_adapter.dart
(feature/label ordering + predictModelV1), the two orderings as JSON, a
README, and promote_result.json describing what it wrote.

Lives in ml/ and runs in the same Python that trained the model: unpickling
model.joblib needs the scikit-learn / LightGBM that saved it. The Trainer
calls this as a subprocess rather than importing it, because its packaged
executable doesn't bundle those libraries.
"""

from __future__ import annotations

import argparse
import json
from pathlib import Path

import joblib

_HEADER = """// GENERATED FILE — AgriSpectra Trainer, "Promote to App" (docs/TRAINER_APP_BUILD_PROMPT.md §4).
// Do not hand-edit; re-run Promote to App to regenerate from a newer run.
// This file has NO runtime dependency on Python, scikit-learn, or any ML
// library — it is plain decision logic, safe to drop into the Flutter app.
"""

_ADAPTER_TEMPLATE = '''{header}
//
// Feature order the model was trained on (must match
// app/lib/ml/feature_extractor.dart's SeedFeatures field-for-field, in
// THIS exact order — a silent mismatch here makes every on-device
// prediction wrong with no error):
{feature_comment}
//
// Label order (the model's raw output index -> class, in THIS order):
{label_comment}

import '{generated_import}' as generated;

/// True once a real model has been promoted — distinguishes this
/// generated file from the placeholder `agrispectra_model_v1_adapter.dart`
/// that ships in the app before any model exists (see
/// app/lib/ml/model_v1_predictor.dart, which gates on this).
const bool modelV1Available = true;

/// Feature-vector order `predictModelV1` expects in its input map's keys.
/// Keep in sync with app/lib/ml/feature_extractor.dart's SeedFeatures.
const List<String> modelV1FeatureOrder = {feature_list_dart};

/// Class label order the trained model's raw output index maps to.
const List<String> modelV1LabelOrder = {label_list_dart};

class ModelV1Prediction {{
  final String label;
  final List<double> classScores;
  const ModelV1Prediction(this.label, this.classScores);
}}

/// Runs the promoted model on one seed's feature map (as produced by
/// FeatureExtractor) and returns the predicted class + raw per-class
/// scores, in `modelV1LabelOrder` order.
ModelV1Prediction predictModelV1(Map<String, double> features) {{
  final input = <double>[
    for (final key in modelV1FeatureOrder) (features[key] ?? 0.0),
  ];
  final scores = generated.score(input);
  var bestIndex = 0;
  for (var i = 1; i < scores.length; i++) {{
    if (scores[i] > scores[bestIndex]) bestIndex = i;
  }}
  return ModelV1Prediction(modelV1LabelOrder[bestIndex], scores);
}}
'''



def _dart_string_list(items: list[str]) -> str:
    inner = ", ".join(f"'{x}'" for x in items)
    return f"[{inner}]"


def _numbered_comment(prefix: str, items: list[str]) -> str:
    return "\n".join(f"//   {i}: {name}" for i, name in enumerate(items)) if items else "//   (none)"



def export_model(model_dir: Path, export_dir: Path, version_label: str) -> dict:
    model = joblib.load(model_dir / "model.joblib")
    feature_columns: list[str] = json.loads((model_dir / "feature_columns.json").read_text(encoding="utf-8"))
    label_classes: list[str] = json.loads((model_dir / "label_classes.json").read_text(encoding="utf-8"))
    export_dir.mkdir(parents=True, exist_ok=True)

    method = "m2cgen"
    try:
        import m2cgen

        dart_code = m2cgen.export_to_dart(model, function_name="score")
    except Exception:  # noqa: BLE001 � m2cgen can raise many exporter-specific error types
        method = "fallback_tree"
        from dart_fallback_codegen import export_forest_to_dart

        dart_code = export_forest_to_dart(model)

    generated_filename = "model_v1_generated.dart"
    adapter_filename = "agrispectra_model_v1_adapter.dart"
    # Explicit UTF-8: Dart requires it, and Windows' default encoding turns
    # the header's em dash into an invalid byte (0x97).
    (export_dir / generated_filename).write_text(_HEADER + "\n" + dart_code, encoding="utf-8")
    (export_dir / adapter_filename).write_text(
        _ADAPTER_TEMPLATE.format(
            header=_HEADER.rstrip(),
            feature_comment=_numbered_comment("feature", feature_columns),
            label_comment=_numbered_comment("label", label_classes),
            generated_import=generated_filename,
            feature_list_dart=_dart_string_list(feature_columns),
            label_list_dart=_dart_string_list(label_classes),
        ),
        encoding="utf-8",
    )
    (export_dir / "feature_columns.json").write_text(json.dumps(feature_columns, indent=2), encoding="utf-8")
    (export_dir / "label_classes.json").write_text(json.dumps(label_classes, indent=2), encoding="utf-8")
    (export_dir / "README.md").write_text(_readme_text(version_label, method, feature_columns, label_classes), encoding="utf-8")

    result = {
        "method": method,
        "generated_dart": generated_filename,
        "adapter_dart": adapter_filename,
        "readme": "README.md",
        "feature_columns": feature_columns,
        "label_classes": label_classes,
    }
    (export_dir / "promote_result.json").write_text(json.dumps(result, indent=2), encoding="utf-8")
    return result


def _readme_text(version_label: str, method: str, feature_columns: list[str], label_classes: list[str]) -> str:
    feature_lines = "\n".join(f"{i}. `{c}`" for i, c in enumerate(feature_columns))
    label_lines = "\n".join(f"{i}. `{c}`" for i, c in enumerate(label_classes))
    return f"""# Promoted model — {version_label}

Generated by AgriSpectra Trainer's "Promote to App" action
(docs/TRAINER_APP_BUILD_PROMPT.md §4). Export method: **{method}**.

This folder is **not** automatically wired into the Flutter app — copying
these two files into `app/lib/ml/` and calling `predictModelV1` from the
app's prediction pipeline is a deliberate decision made separately, with
the cross-session validation test in `docs/VALIDATION.md` in mind.

## Files

- `model_v1_generated.dart` — the trained model's decision logic as plain
  Dart, no ML library dependency at runtime.
- `agrispectra_model_v1_adapter.dart` — builds the feature vector from the
  app's feature map in the exact order below, calls the generated
  function, and maps the result back to a class label.
- `feature_columns.json` / `label_classes.json` — the same two orderings,
  machine-readable.

## Feature order (input vector index -> name)

Must match `app/lib/ml/feature_extractor.dart`'s `SeedFeatures` output
field-for-field. A mismatch here is silent and makes every prediction
wrong with no error.

{feature_lines}

## Label order (raw output index -> class)

{label_lines}
"""



def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--model-dir", required=True, type=Path)
    ap.add_argument("--export-dir", required=True, type=Path)
    ap.add_argument("--version-label", default=None)
    args = ap.parse_args()
    result = export_model(args.model_dir, args.export_dir, args.version_label or args.export_dir.name)
    print(f"Exported ({result['method']}) to {args.export_dir}")


if __name__ == "__main__":
    main()

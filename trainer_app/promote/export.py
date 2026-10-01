"""Promote to App — §4. Turns a trained `model.joblib` (RandomForest or
LightGBM, whichever train_baseline.py used) into a dependency-free Dart
file the Flutter app can call with no Python/ML runtime at inference
time, plus a small adapter that wires it to the app's existing feature
map using the exact column/label ordering the model was trained with.

This never runs automatically after training (§3 Mode B.5, §6): it is a
separate, explicit action the project owner takes on a specific run from
the results dashboard / History.
"""

from __future__ import annotations

import json
import shutil
from dataclasses import dataclass
from pathlib import Path
from typing import Optional

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


@dataclass
class PromoteResult:
    export_dir: Path
    generated_dart_path: Path
    adapter_dart_path: Path
    readme_path: Path
    feature_columns: list[str]
    label_classes: list[str]
    method: str  # "m2cgen" or "fallback_tree"


def _dart_string_list(items: list[str]) -> str:
    inner = ", ".join(f"'{x}'" for x in items)
    return f"[{inner}]"


def _numbered_comment(prefix: str, items: list[str]) -> str:
    return "\n".join(f"//   {i}: {name}" for i, name in enumerate(items)) if items else "//   (none)"


def promote_model(
    model_dir: Path,
    export_root: Path,
    run_id: str,
    version_label: Optional[str] = None,
) -> PromoteResult:
    model = joblib.load(model_dir / "model.joblib")
    feature_columns: list[str] = json.loads((model_dir / "feature_columns.json").read_text())
    label_classes: list[str] = json.loads((model_dir / "label_classes.json").read_text())

    version_label = version_label or f"run_{run_id}"
    export_dir = export_root / f"trained_model_{version_label}"
    export_dir.mkdir(parents=True, exist_ok=True)

    method = "m2cgen"
    try:
        import m2cgen

        dart_code = m2cgen.export_to_dart(model, function_name="score")
    except Exception:  # noqa: BLE001 — m2cgen can raise many exporter-specific error types
        method = "fallback_tree"
        from promote.fallback_codegen import export_forest_to_dart

        dart_code = export_forest_to_dart(model)

    generated_filename = "model_v1_generated.dart"
    adapter_filename = "agrispectra_model_v1_adapter.dart"

    (export_dir / generated_filename).write_text(_HEADER + "\n" + dart_code)

    adapter_code = _ADAPTER_TEMPLATE.format(
        header=_HEADER.rstrip(),
        feature_comment=_numbered_comment("feature", feature_columns),
        label_comment=_numbered_comment("label", label_classes),
        generated_import=generated_filename,
        feature_list_dart=_dart_string_list(feature_columns),
        label_list_dart=_dart_string_list(label_classes),
    )
    (export_dir / adapter_filename).write_text(adapter_code)

    (export_dir / "feature_columns.json").write_text(json.dumps(feature_columns, indent=2))
    (export_dir / "label_classes.json").write_text(json.dumps(label_classes, indent=2))

    readme = export_dir / "README.md"
    readme.write_text(_readme_text(version_label, method, feature_columns, label_classes))

    return PromoteResult(
        export_dir=export_dir,
        generated_dart_path=export_dir / generated_filename,
        adapter_dart_path=export_dir / adapter_filename,
        readme_path=readme,
        feature_columns=feature_columns,
        label_classes=label_classes,
        method=method,
    )


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


def copy_promoted_to(export_dir: Path, destination: Path) -> list[Path]:
    """Convenience for a one-click copy of the two Dart files into an
    app source tree the user points at explicitly — never done
    automatically (§4.3)."""
    destination.mkdir(parents=True, exist_ok=True)
    copied = []
    for name in ("model_v1_generated.dart", "agrispectra_model_v1_adapter.dart"):
        src = export_dir / name
        dst = destination / name
        shutil.copy2(src, dst)
        copied.append(dst)
    return copied

"""Promote to App — §4. Turns a trained `model.joblib` into dependency-free
Dart the Flutter app can call, by running `ml/export/export_dart.py` in the
user's Python.

It runs there, not in-process, for the same reason the training stages
do: unpickling `model.joblib` needs the scikit-learn (or LightGBM) that
saved it, and the packaged Trainer doesn't bundle those. Running in the
training environment also guarantees the versions match.

This never runs automatically after training (§3 Mode B.5, §6): it is a
separate, explicit action on a specific run.
"""

from __future__ import annotations

import json
import shutil
from dataclasses import dataclass
from pathlib import Path
from typing import Optional

from core.config import AppConfig
from pipeline.runner import OnLine, run_subprocess


class PromoteFailed(RuntimeError):
    pass


@dataclass
class PromoteResult:
    export_dir: Path
    generated_dart_path: Path
    adapter_dart_path: Path
    readme_path: Path
    feature_columns: list[str]
    label_classes: list[str]
    method: str  # "tree_functions" (scikit-learn forests) or "m2cgen" (other models)


def promote_model(
    config: AppConfig,
    model_dir: Path,
    export_root: Path,
    run_id: str,
    version_label: Optional[str] = None,
    on_line: Optional[OnLine] = None,
) -> PromoteResult:
    version_label = version_label or f"run_{run_id}"
    export_dir = export_root / f"trained_model_{version_label}"
    script = Path(config.pipeline_dir) / "export" / "export_dart.py"

    try:
        result = run_subprocess(
            [
                config.python_exe,
                str(script),
                "--model-dir", str(model_dir),
                "--export-dir", str(export_dir),
                "--version-label", version_label,
            ],
            Path(config.pipeline_dir),
            "promote",
            on_line,
        )
    except FileNotFoundError as exc:
        raise PromoteFailed(f"Couldn't run the Python interpreter set in Settings: {exc}") from exc

    summary_file = export_dir / "promote_result.json"
    if result.returncode != 0 or not summary_file.is_file():
        tail = "\n".join(result.log.strip().splitlines()[-3:])
        raise PromoteFailed(tail or f"export_dart.py exited with code {result.returncode}")

    summary = json.loads(summary_file.read_text(encoding="utf-8"))
    return PromoteResult(
        export_dir=export_dir,
        generated_dart_path=export_dir / summary["generated_dart"],
        adapter_dart_path=export_dir / summary["adapter_dart"],
        readme_path=export_dir / summary["readme"],
        feature_columns=summary["feature_columns"],
        label_classes=summary["label_classes"],
        method=summary["method"],
    )


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

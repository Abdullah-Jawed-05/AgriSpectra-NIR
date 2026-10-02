"""Persisted app settings — §5/§3 "Shared chrome: Settings".

Plain JSON on disk (core/paths.config_file()), not a database: there are
only a handful of fields and a human may want to hand-edit or inspect this
file. The dataset itself is never represented here beyond a path — it
stays as files under raw_data_root, per the non-negotiable in §5 ("don't
invent a new database").
"""

from __future__ import annotations

import json
import shutil
import sys
from dataclasses import asdict, dataclass, field
from pathlib import Path

from . import paths

# The taxonomy is a closed, fixed list (§1) — not user-configurable.
CROP = "barley"


def _discover_pipeline_dir() -> str:
    """Find the ml/ pipeline scripts directory.

    Checked in order: next to the packaged executable (a bundled release,
    see §5 "Packaging"), then the ml/ directory two levels up from this
    source file (running from a checkout of the AgriSpectra-NIR repo where
    trainer_app/ is a sibling of ml/). Falls back to an empty string, which
    the Settings screen then shows as "not configured" rather than
    guessing further.
    """
    candidates = []
    if getattr(sys, "frozen", False):
        candidates.append(Path(sys.executable).resolve().parent / "ml")
    candidates.append(Path(__file__).resolve().parents[2] / "ml")
    for c in candidates:
        if (c / "scripts" / "prepare_dataset.py").is_file():
            return str(c)
    return str(candidates[-1]) if candidates else ""


def _discover_python_exe() -> str:
    """Find a real, spawnable Python interpreter for Train Mode's
    subprocess calls into ml/.

    `sys.executable` is correct when running from source (`python
    main.py`) — it IS a real interpreter. It is wrong when frozen
    (PyInstaller/similar): it then points at this app's own bundled exe,
    which isn't a general-purpose Python and can't run ml/'s scripts.
    A packaged build deliberately requires the user's own Python already
    installed (see trainer_app/README.md "Packaging") rather than
    bundling a second one, so look for it on PATH instead; an empty
    result shows as "not configured" in Settings, same as pipeline_dir.
    """
    if not getattr(sys, "frozen", False):
        return sys.executable
    return shutil.which("python") or shutil.which("python3") or ""


def _discover_app_lib_ml_dir() -> str:
    """Find the Flutter app's `app/lib/ml/` directory — the "Copy to app"
    destination for Promote to App (§4.3). Same two-candidate strategy as
    `_discover_pipeline_dir`: next to a packaged executable, or two levels
    up from this checkout (trainer_app/ and app/ as siblings)."""
    candidates = []
    if getattr(sys, "frozen", False):
        candidates.append(Path(sys.executable).resolve().parent / "app" / "lib" / "ml")
    candidates.append(Path(__file__).resolve().parents[2] / "app" / "lib" / "ml")
    for c in candidates:
        if (c / "vision_pipeline.dart").is_file():
            return str(c)
    return str(candidates[-1]) if candidates else ""


@dataclass
class AppConfig:
    raw_data_root: str = field(default_factory=lambda: str(paths.default_dataset_root() / "raw"))
    models_root: str = field(default_factory=lambda: str(paths.default_dataset_root() / "models"))
    work_root: str = field(default_factory=lambda: str(paths.default_dataset_root() / "work"))
    export_root: str = field(default_factory=lambda: str(paths.default_dataset_root() / "export"))
    pipeline_dir: str = field(default_factory=_discover_pipeline_dir)
    python_exe: str = field(default_factory=_discover_python_exe)
    app_lib_ml_dir: str = field(default_factory=_discover_app_lib_ml_dir)

    def ensure_dirs(self) -> None:
        for p in (self.raw_data_root, self.models_root, self.work_root, self.export_root):
            Path(p).mkdir(parents=True, exist_ok=True)

    def scripts_dir(self) -> Path:
        return Path(self.pipeline_dir) / "scripts"

    def training_dir(self) -> Path:
        return Path(self.pipeline_dir) / "training"

    def evaluation_dir(self) -> Path:
        return Path(self.pipeline_dir) / "evaluation"

    def is_pipeline_configured(self) -> bool:
        return (self.scripts_dir() / "prepare_dataset.py").is_file()

    def is_app_lib_ml_dir_configured(self) -> bool:
        return (Path(self.app_lib_ml_dir) / "vision_pipeline.dart").is_file()

    def to_dict(self) -> dict:
        return asdict(self)

    @classmethod
    def load(cls) -> "AppConfig":
        path = paths.config_file()
        if not path.exists():
            cfg = cls()
            cfg.save()
            return cfg
        try:
            data = json.loads(path.read_text())
        except (json.JSONDecodeError, OSError):
            return cls()
        cfg = cls()
        for k, v in data.items():
            if hasattr(cfg, k):
                setattr(cfg, k, v)
        return cfg

    def save(self) -> None:
        paths.config_file().write_text(json.dumps(self.to_dict(), indent=2))

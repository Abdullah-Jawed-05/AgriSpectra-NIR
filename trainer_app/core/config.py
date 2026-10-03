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
from typing import Optional

from . import paths


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


def _is_usable_python(exe: str) -> bool:
    """Whether `exe` could plausibly run ml/'s scripts: it exists (as a
    path, or a bare name on PATH) and, in a packaged build, isn't this
    app's own exe -- see `_discover_python_exe`."""
    if not exe:
        return False
    p = Path(exe)
    if not (p.is_file() or shutil.which(exe)):
        return False
    if getattr(sys, "frozen", False) and p.is_file():
        try:
            if p.resolve() == Path(sys.executable).resolve():
                return False
        except OSError:
            return False
    return True


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


def _discover_flutter_exe() -> str:
    """Find the `flutter` SDK executable, for "Enable Model V1 & rebuild
    APK" (§4.4). Like `python_exe`, this machine may have more than one
    Flutter checkout — PATH's `flutter` is only a reasonable default, not
    guaranteed correct; Settings lets it be overridden."""
    return shutil.which("flutter") or ""


@dataclass
class AppConfig:
    raw_data_root: str = field(default_factory=lambda: str(paths.default_dataset_root() / "raw"))
    models_root: str = field(default_factory=lambda: str(paths.default_dataset_root() / "models"))
    work_root: str = field(default_factory=lambda: str(paths.default_dataset_root() / "work"))
    export_root: str = field(default_factory=lambda: str(paths.default_dataset_root() / "export"))
    pipeline_dir: str = field(default_factory=_discover_pipeline_dir)
    python_exe: str = field(default_factory=_discover_python_exe)
    app_lib_ml_dir: str = field(default_factory=_discover_app_lib_ml_dir)
    flutter_exe: str = field(default_factory=_discover_flutter_exe)
    crop: str = "barley"  # the crop (kind of seed) being worked on; see core/crops.py

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

    def app_root(self) -> Optional[Path]:
        """The Flutter app's project root — two levels up from
        app_lib_ml_dir (app/lib/ml -> app/lib -> app). None if
        app_lib_ml_dir isn't set deep enough to have two parents."""
        p = Path(self.app_lib_ml_dir)
        return p.parents[1] if len(p.parents) > 1 else None

    def is_flutter_configured(self) -> bool:
        """Only checks what's cheap and reliable to check ahead of time —
        flutter_exe not being empty, and a pubspec.yaml existing where
        app_root() points. Deliberately doesn't try to run `flutter_exe`
        here (e.g. to validate it resolves): a bare command name like
        "flutter" is valid and PATH-resolved at actual subprocess time,
        same as python_exe elsewhere in this file never being run just to
        validate it. build_apk's own FileNotFoundError handling covers
        the case where it doesn't."""
        root = self.app_root()
        return bool(self.flutter_exe) and root is not None and (root / "pubspec.yaml").is_file()

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
        cfg.repair_stale_tool_paths()
        return cfg

    def repair_stale_tool_paths(self) -> list[str]:
        """Re-discover tool paths that no longer point at anything usable.

        Saved paths outlive what they point at: a build folder gets deleted,
        or an older packaged build saved its own exe as python_exe. Left as
        they are, Train and Promote fail until someone fixes them by hand in
        Settings. A path that still works is never touched, and a broken one
        is only replaced when discovery finds something that works. Returns
        the names of the fields that changed; nothing is written to disk."""
        changed = []
        if not self.is_pipeline_configured():
            found = _discover_pipeline_dir()
            if (Path(found) / "scripts" / "prepare_dataset.py").is_file():
                self.pipeline_dir = found
                changed.append("pipeline_dir")
        if not _is_usable_python(self.python_exe):
            found = _discover_python_exe()
            if found and _is_usable_python(found):
                self.python_exe = found
                changed.append("python_exe")
        if not self.is_app_lib_ml_dir_configured():
            found = _discover_app_lib_ml_dir()
            if (Path(found) / "vision_pipeline.dart").is_file():
                self.app_lib_ml_dir = found
                changed.append("app_lib_ml_dir")
        if not self.flutter_exe or not (Path(self.flutter_exe).is_file() or shutil.which(self.flutter_exe)):
            found = _discover_flutter_exe()
            if found and found != self.flutter_exe:
                self.flutter_exe = found
                changed.append("flutter_exe")
        return changed

    def save(self) -> None:
        paths.config_file().write_text(json.dumps(self.to_dict(), indent=2))

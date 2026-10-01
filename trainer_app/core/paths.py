"""Default on-disk layout for the trainer app's own (non-dataset) state.

The dataset itself (raw photos, features.csv, trained models) lives under
whatever root the user picks in Settings — see config.py. This module only
knows about the app's *own* support files: the settings file and the
SQLite app-state database, which always live next to each other in a
per-user app-data directory regardless of where the dataset root points.
"""

from __future__ import annotations

import os
import sys
from pathlib import Path


def app_data_dir() -> Path:
    """Per-user directory for this app's own settings/db — not the dataset."""
    if sys.platform == "win32":
        base = os.environ.get("APPDATA") or str(Path.home() / "AppData" / "Roaming")
        d = Path(base) / "AgriSpectra Trainer"
    elif sys.platform == "darwin":
        d = Path.home() / "Library" / "Application Support" / "AgriSpectra Trainer"
    else:
        base = os.environ.get("XDG_DATA_HOME") or str(Path.home() / ".local" / "share")
        d = Path(base) / "agrispectra-trainer"
    d.mkdir(parents=True, exist_ok=True)
    return d


def default_dataset_root() -> Path:
    """Sensible default for where sorted photos / models live, per §5."""
    d = Path.home() / "Documents" / "AgriSpectra Trainer"
    return d


def config_file() -> Path:
    return app_data_dir() / "settings.json"


def app_db_file() -> Path:
    return app_data_dir() / "app_state.sqlite3"


def log_file() -> Path:
    return app_data_dir() / "trainer_app.log"

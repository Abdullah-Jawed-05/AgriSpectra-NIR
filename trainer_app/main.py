#!/usr/bin/env python3
"""AgriSpectra Trainer — entry point.

An offline, gamified seed-labelling + model-training desktop app that
wraps the real ml/ pipeline (see docs/TRAINER_APP_BUILD_PROMPT.md).
Launch with `python main.py` for development, or package with
`flet build windows` for a standalone .exe (see README.md).
"""

from __future__ import annotations

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

import flet as ft

from core.config import AppConfig
from core.paths import app_db_file
from data.db import Database
from ui.app import build_page


def main(page: ft.Page) -> None:
    config = AppConfig.load()
    config.ensure_dirs()
    db = Database(app_db_file())
    db.reconcile_stale_runs()  # any run still "running" belongs to a process that's gone
    build_page(page, config, db)


if __name__ == "__main__":
    ft.run(main, assets_dir=str(Path(__file__).resolve().parent / "assets"))

"""Serve the Trainer UI on http://localhost:8551 for inspecting it in a
browser (e.g. screenshots during UI work). Uses throwaway data/config dirs,
never your real ones -- don't use it for actual sorting or training.

    set FLET_FORCE_WEB_SERVER=true && python dev_web_preview.py

FLET_FORCE_WEB_SERVER serves without also popping a browser window open.
The native file picker isn't available in browser mode.
"""

import sys
import tempfile
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

import flet as ft

import core.paths as paths
from core.config import AppConfig
from data.db import Database
from ui.app import build_page

_tmp = Path(tempfile.mkdtemp(prefix="trainer_web_"))
# Anything that saves settings (Settings screen, switching crop) must land in
# the throwaway dir -- otherwise it overwrites the real settings.json with
# these temp paths.
paths.config_file = lambda: _tmp / "settings.json"


def main(page: ft.Page) -> None:
    cfg = AppConfig(
        raw_data_root=str(_tmp / "raw"),
        models_root=str(_tmp / "models"),
        work_root=str(_tmp / "work"),
        export_root=str(_tmp / "export"),
    )
    cfg.ensure_dirs()
    build_page(page, cfg, Database(_tmp / "app.sqlite3"))


if __name__ == "__main__":
    ft.run(main, view=ft.AppView.WEB_BROWSER, port=8551, assets_dir=str(Path(__file__).resolve().parent / "assets"))

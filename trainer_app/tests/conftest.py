from __future__ import annotations

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

import cv2
import numpy as np
import pytest

from core.config import AppConfig
from data.db import Database

REPO_ML_DIR = Path(__file__).resolve().parents[2] / "ml"


@pytest.fixture
def config(tmp_path: Path) -> AppConfig:
    cfg = AppConfig(
        raw_data_root=str(tmp_path / "raw"),
        models_root=str(tmp_path / "models"),
        work_root=str(tmp_path / "work"),
        export_root=str(tmp_path / "export"),
        pipeline_dir=str(REPO_ML_DIR),
    )
    cfg.ensure_dirs()
    return cfg


@pytest.fixture
def db(tmp_path: Path) -> Database:
    return Database(tmp_path / "app.sqlite3")


def make_seed_photo(path: Path, n_seeds: int, seed: int, color=(40, 90, 150)) -> None:
    rng = np.random.default_rng(seed)
    img = np.full((300, 400, 3), 235, np.uint8)
    for _ in range(n_seeds):
        cx, cy = rng.integers(60, 340), rng.integers(60, 240)
        axes = (int(rng.integers(16, 24)), int(rng.integers(9, 14)))
        cv2.ellipse(img, (cx, cy), axes, int(rng.integers(0, 180)), 0, 360, color, -1)
    cv2.imwrite(str(path), img)


def make_textured_photo(path: Path, seed: int = 99) -> None:
    rng = np.random.default_rng(seed)
    img = rng.integers(80, 180, (300, 400, 3)).astype(np.uint8)
    cv2.imwrite(str(path), img)


@pytest.fixture
def import_folder(tmp_path: Path) -> Path:
    folder = tmp_path / "import_me"
    folder.mkdir()
    for i in range(4):
        make_seed_photo(folder / f"photo_{i}.jpg", n_seeds=3, seed=i)
    make_textured_photo(folder / "textured.jpg")
    return folder


LABEL_COLORS = {
    "GOOD": (60, 130, 170),
    "DAMAGED": (20, 40, 60),
    "BROKEN": (50, 120, 160),
    "SHRIVELED": (70, 110, 140),
    "IMPURITIES": (120, 120, 120),
}


@pytest.fixture
def two_batch_raw_dataset(tmp_path: Path, config: AppConfig) -> Path:
    """Writes a small labelled dataset in the raw/<crop>/<batch>/<LABEL>
    layout directly (bypassing Sort Mode) — used by pipeline/promote
    tests that need labelled data without exercising the UI."""
    raw = Path(config.raw_data_root) / "barley"
    for batch_i, batch in enumerate(["batch_2026-09-01", "batch_2026-09-15"]):
        rng_seed = batch_i
        for label, color in LABEL_COLORS.items():
            d = raw / batch / label
            d.mkdir(parents=True, exist_ok=True)
            for i in range(20):
                make_seed_photo(d / f"img_{i:03d}.jpg", n_seeds=1, seed=rng_seed * 100 + i, color=color)
    return raw

from __future__ import annotations

import csv
import subprocess
import sys
from pathlib import Path

import pytest

from conftest import REPO_ML_DIR, make_seed_photo
from core.crops import can_promote_to_phone_app, crop_label, known_crops, normalize_crop


@pytest.mark.parametrize(
    "typed,slug",
    [("Wheat", "wheat"), ("  Durum wheat ", "durum_wheat"), ("Rice-2", "rice_2"), ("!!!", "")],
)
def test_normalize_crop(typed, slug):
    assert normalize_crop(typed) == slug


def test_crop_label():
    assert crop_label("durum_wheat") == "Durum wheat"


def test_known_crops_lists_data_folders_plus_current_and_default(tmp_path):
    (tmp_path / "wheat").mkdir()
    (tmp_path / "Not A Slug").mkdir()  # hand-made folder: ignored rather than mangled
    assert known_crops(tmp_path, "rice") == ["barley", "rice", "wheat"]
    assert known_crops(tmp_path / "missing", "barley") == ["barley"]


def test_only_barley_can_be_promoted_to_the_phone_app():
    assert can_promote_to_phone_app("barley")
    assert not can_promote_to_phone_app("wheat")


def test_prepare_dataset_crop_filter_never_mixes_crops(tmp_path):
    """Regression: prepare_dataset used to process every crop folder, so a
    second crop would have been trained into the same model."""
    raw = tmp_path / "raw"
    for crop in ("barley", "wheat"):
        d = raw / crop / "batch_1" / "GOOD"
        d.mkdir(parents=True)
        for i in range(2):
            make_seed_photo(d / f"{i}.jpg", n_seeds=1, seed=i)
    out = tmp_path / "out"

    proc = subprocess.run(
        [sys.executable, str(REPO_ML_DIR / "scripts" / "prepare_dataset.py"),
         "--raw-dir", str(raw), "--out", str(out), "--crop", "wheat", "--one-seed"],
        capture_output=True, text=True,
    )

    assert proc.returncode == 0, proc.stderr
    with open(out / "features.csv", newline="") as f:
        crops = {row["crop"] for row in csv.DictReader(f)}
    assert crops == {"wheat"}


def test_prepare_dataset_unknown_crop_fails_clearly(tmp_path):
    (tmp_path / "raw" / "barley").mkdir(parents=True)
    proc = subprocess.run(
        [sys.executable, str(REPO_ML_DIR / "scripts" / "prepare_dataset.py"),
         "--raw-dir", str(tmp_path / "raw"), "--out", str(tmp_path / "out"), "--crop", "wheat"],
        capture_output=True, text=True,
    )
    assert proc.returncode != 0
    assert "wheat" in (proc.stderr + proc.stdout)


def test_runs_record_crop_and_best_run_is_same_crop_only(db):
    barley_old = db.create_run("/w1", crop="barley")
    db.finish_run(barley_old, macro_f1=0.9)
    wheat = db.create_run("/w2", crop="wheat")
    db.finish_run(wheat, macro_f1=0.5)
    barley_new = db.create_run("/w3", crop="barley")
    db.finish_run(barley_new, macro_f1=0.6)
    wheat_new = db.create_run("/w4", crop="wheat")
    db.finish_run(wheat_new, macro_f1=0.4)

    assert db.get_run(wheat)["crop"] == "wheat"
    assert db.best_run_before(barley_new)["id"] == barley_old  # not the later/other-crop runs
    assert db.best_run_before(wheat_new)["id"] == wheat  # never compared against barley's 0.9


def test_existing_runs_default_to_barley_after_migration(tmp_path):
    """Runs recorded before crops existed were all barley."""
    import sqlite3

    from data.db import SCHEMA, Database

    path = tmp_path / "old.sqlite3"
    conn = sqlite3.connect(path)
    conn.executescript(SCHEMA)
    conn.execute("INSERT INTO runs (id, created_at, status, work_dir) VALUES ('old', 1, 'succeeded', '/w')")
    conn.commit()
    conn.close()

    assert Database(path).get_run("old")["crop"] == "barley"

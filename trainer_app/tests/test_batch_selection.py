"""Choosing which batch folders a training run uses."""

from __future__ import annotations

import csv
import json
import subprocess
import sys
from pathlib import Path

import pytest

from conftest import REPO_ML_DIR, make_seed_photo
from pipeline.preflight import scan_raw_data

BATCH_A, BATCH_B = "batch_2026-09-01", "batch_2026-09-15"


def _prepare(raw: Path, out: Path, *extra: str) -> subprocess.CompletedProcess:
    return subprocess.run(
        [sys.executable, str(REPO_ML_DIR / "scripts" / "prepare_dataset.py"),
         "--raw-dir", str(raw), "--out", str(out), "--crop", "barley", "--one-seed", *extra],
        capture_output=True, text=True,
    )


def _small_dataset(raw: Path) -> None:
    for batch in ("lot1", "lot2", "lot3"):
        for label in ("GOOD", "DAMAGED"):
            d = raw / "barley" / batch / label
            d.mkdir(parents=True)
            make_seed_photo(d / "a.jpg", n_seeds=1, seed=len(batch))


def test_prepare_dataset_uses_only_the_chosen_batches(tmp_path):
    _small_dataset(tmp_path / "raw")
    proc = _prepare(tmp_path / "raw", tmp_path / "out", "--batch", "lot1", "--batch", "lot3")

    assert proc.returncode == 0, proc.stderr
    with open(tmp_path / "out" / "features.csv", newline="") as f:
        assert {row["batch_id"] for row in csv.DictReader(f)} == {"lot1", "lot3"}


def test_prepare_dataset_unknown_batch_fails_before_processing(tmp_path):
    _small_dataset(tmp_path / "raw")
    proc = _prepare(tmp_path / "raw", tmp_path / "out", "--batch", "lot1", "--batch", "nope")

    assert proc.returncode != 0
    assert "nope" in proc.stderr + proc.stdout
    assert not any((tmp_path / "out" / "crops").iterdir())  # no image was processed


def test_preflight_counts_only_included_batches(config, two_batch_raw_dataset):
    summary = scan_raw_data(Path(config.raw_data_root), "barley", [BATCH_B])

    assert [b.batch_id for b in summary.batches] == [BATCH_A, BATCH_B]
    assert [b.included for b in summary.batches] == [True, False]
    assert summary.batch_ids == [BATCH_A]
    assert summary.total_images == 100  # 5 classes x 20 photos, one batch
    assert all(n == 20 for n in summary.class_counts.values())
    assert any("leakage" in w.lower() for w in summary.warnings)


def test_preflight_nothing_selected_is_not_ready(config, two_batch_raw_dataset):
    summary = scan_raw_data(Path(config.raw_data_root), "barley", [BATCH_A, BATCH_B])

    assert not summary.is_ready
    assert len(summary.batches) == 2
    assert any("No batches are selected" in w for w in summary.warnings)


def test_batch_exclusions_persist_per_crop(config, tmp_path, monkeypatch):
    import core.paths as paths
    from core.config import AppConfig

    monkeypatch.setattr(paths, "config_file", lambda: tmp_path / "settings.json")
    config.set_batch_included("barley", "lot1", False)
    config.set_batch_included("wheat", "w1", False)
    config.save()

    loaded = AppConfig.load()
    assert loaded.excluded_batches_for("barley") == ["lot1"]
    assert loaded.excluded_batches_for("wheat") == ["w1"]
    assert loaded.excluded_batches_for("rice") == []

    loaded.set_batch_included("barley", "lot1", True)
    assert "barley" not in loaded.excluded_batches  # no empty leftovers


def test_hand_edited_garbage_exclusions_are_ignored(config):
    config.excluded_batches = {"barley": "lot1"}  # not a list
    assert config.excluded_batches_for("barley") == []
    config.excluded_batches = ["lot1"]  # not a dict
    assert config.excluded_batches_for("barley") == []
    config.set_batch_included("barley", "lot2", False)
    assert config.excluded_batches_for("barley") == ["lot2"]


def test_runner_passes_the_chosen_batches_to_prepare(config, db, two_batch_raw_dataset, monkeypatch):
    import pipeline.runner as runner_mod

    seen = []

    def fake_subprocess(argv, cwd, stage, on_line):
        seen.append(argv)
        return runner_mod.StageResult(stage, 1, "stop here", 0.0)

    monkeypatch.setattr(runner_mod, "run_subprocess", fake_subprocess)
    runner = runner_mod.PipelineRunner(config, db, db.create_run("w"))

    with pytest.raises(runner_mod.StageFailed):
        runner.run("barley", batches=[BATCH_B])

    argv = seen[0]
    assert argv[argv.index("--batch") + 1] == BATCH_B
    assert argv.count("--batch") == 1


def test_runner_refuses_an_empty_selection(config, db, two_batch_raw_dataset):
    from pipeline.runner import PipelineRunner, StageFailed

    with pytest.raises(StageFailed, match="No batches"):
        PipelineRunner(config, db, db.create_run("w")).run("barley", batches=[])


def test_train_screen_untick_a_batch_then_train_without_it(config, db, two_batch_raw_dataset, tmp_path, monkeypatch):
    import core.paths as paths
    import ui.train_screen as ts
    from test_ui_build import StubPage

    monkeypatch.setattr(paths, "config_file", lambda: tmp_path / "settings.json")

    class Ctx:
        pass

    ctx = Ctx()
    ctx.config, ctx.db, ctx.crop, ctx.page = config, db, "barley", StubPage()
    ctx.navigate = lambda n: None
    notes = []
    ctx.notify = lambda msg, **k: notes.append(msg)

    captured = {}

    def fake_run(self, crop, **kwargs):
        captured.update(kwargs, running=screen.running)
        raise ts.StageFailed("prepare", 1, "stopped by test")

    monkeypatch.setattr(ts.PipelineRunner, "run", fake_run)

    screen = ts.TrainScreen(ctx)
    screen.build()
    screen._set_batches_included([BATCH_A], False)

    assert json.loads((tmp_path / "settings.json").read_text())["excluded_batches"] == {"barley": [BATCH_A]}
    assert not screen.start_button.disabled  # one batch is still enough to train

    screen._on_start(None)

    assert captured["batches"] == [BATCH_B]
    assert captured["running"] is True
    run = db.list_runs()[0]
    assert json.loads(run["batches_json"]) == [BATCH_B]
    assert screen.running is False and not screen.start_button.disabled  # unlocked after the run

    screen._set_batches_included([BATCH_A, BATCH_B], False)
    assert screen.start_button.disabled  # nothing selected


def test_runs_from_before_batch_selection_say_so(db):
    from ui.components import trained_on_text

    old = db.get_run(db.create_run("w"))
    new = db.get_run(db.create_run("w", batches=["lot1", "lot2"]))
    assert "every batch" in trained_on_text(old)
    assert trained_on_text(new) == "Trained on 2 batches: lot1, lot2"

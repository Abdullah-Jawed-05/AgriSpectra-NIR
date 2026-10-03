"""The same photo in two batches must not pass as a leakage-safe test."""

from __future__ import annotations

import csv
import shutil
from pathlib import Path

from conftest import make_seed_photo
from pipeline.duplicates import count_test_rows_seen_in_training, find_shared_photos
from pipeline.preflight import scan_raw_data


def _batch(root: Path, name: str, seeds: dict[str, range]) -> None:
    for label, idx in seeds.items():
        d = root / name / label
        d.mkdir(parents=True, exist_ok=True)
        for i in idx:
            make_seed_photo(d / f"{label.lower()}_{i}.jpg", n_seeds=1, seed=i + (0 if label == "GOOD" else 500))


def test_shared_photos_found_by_content_not_name(tmp_path):
    crop = tmp_path / "barley"
    _batch(crop, "lot1", {"GOOD": range(4)})
    _batch(crop, "lot2", {"GOOD": range(10, 13)})
    (crop / "lot2" / "GOOD" / "renamed.jpg").write_bytes((crop / "lot1" / "GOOD" / "good_0.jpg").read_bytes())
    shutil.copytree(crop / "lot1", crop / "lot1_again")

    shared = {(s.batch_a, s.batch_b): s.n_shared for s in find_shared_photos(crop, ["lot1", "lot2", "lot1_again"])}

    assert shared == {("lot1", "lot1_again"): 4, ("lot1", "lot2"): 1, ("lot1_again", "lot2"): 1}


def test_preflight_warns_only_about_ticked_batches(config):
    crop = Path(config.raw_data_root) / "barley"
    _batch(crop, "lot1", {"GOOD": range(3), "DAMAGED": range(3)})
    shutil.copytree(crop / "lot1", crop / "lot1_copy")
    _batch(crop, "lot2", {"GOOD": range(20, 23), "DAMAGED": range(20, 23)})

    summary = scan_raw_data(Path(config.raw_data_root), "barley")
    assert any("lot1 and lot1_copy share 6 identical photo" in w for w in summary.warnings)

    summary = scan_raw_data(Path(config.raw_data_root), "barley", ["lot1_copy"])
    assert summary.shared_photos == []
    assert not any("identical photo" in w for w in summary.warnings)


def _split_csv(path: Path, rows: list[tuple[str, str, str]]) -> None:
    with open(path, "w", newline="", encoding="utf-8") as f:
        w = csv.DictWriter(f, fieldnames=["batch_id", "label", "source_image"])
        w.writeheader()
        for batch_id, label, image in rows:
            w.writerow({"batch_id": batch_id, "label": label, "source_image": image})


def test_counts_test_rows_whose_photo_is_in_training(tmp_path):
    crop = tmp_path / "barley"
    _batch(crop, "lot1", {"GOOD": range(3)})
    _batch(crop, "Lot2", {"Good": range(3, 5)})  # hand-named folders: label matched case-insensitively
    shutil.copy(crop / "lot1" / "GOOD" / "good_0.jpg", crop / "Lot2" / "Good" / "copied.jpg")
    split = tmp_path / "split"
    split.mkdir()
    _split_csv(split / "train.csv", [("lot1", "GOOD", f"good_{i}.jpg") for i in range(3)])
    _split_csv(split / "val.csv", [])
    _split_csv(split / "test.csv", [("Lot2", "GOOD", "good_3.jpg"), ("Lot2", "GOOD", "good_4.jpg"),
                                    ("Lot2", "GOOD", "copied.jpg"), ("Lot2", "GOOD", "missing.jpg")])

    assert count_test_rows_seen_in_training(crop, split) == 1


def test_run_on_a_copied_batch_is_not_leakage_safe(config, db, two_batch_raw_dataset):
    """End to end with the real scripts: two batch folders holding the same
    photos used to be reported as a leakage-safe test."""
    from pipeline.runner import PipelineRunner

    shutil.rmtree(two_batch_raw_dataset / "batch_2026-09-15")
    shutil.copytree(two_batch_raw_dataset / "batch_2026-09-01", two_batch_raw_dataset / "batch_2026-09-15")
    lines = []

    result = PipelineRunner(config, db, db.create_run("w")).run("barley", on_line=lambda s, ln: lines.append(ln))

    summary = result["split_summary"]
    assert summary["test_leakage_safe"] is False
    assert summary["test_rows_seen_in_training"] == summary["test"]["rows"] > 0
    assert any("NOT leakage-safe" in ln for ln in lines)


def test_results_explain_the_overlap(db):
    from ui.components import test_overlap_text

    clean = db.create_run("w")
    db.finish_run(clean, n_test_rows=10, test_rows_seen_in_training=0)
    leaky = db.create_run("w")
    db.finish_run(leaky, n_test_rows=10, test_rows_seen_in_training=7)

    assert test_overlap_text(db.get_run(clean)) is None
    assert "7 of 10 test rows" in test_overlap_text(db.get_run(leaky))

from __future__ import annotations

from pathlib import Path

from pipeline.preflight import scan_raw_data


def test_scan_empty_root_warns(config):
    summary = scan_raw_data(Path(config.raw_data_root), "barley")
    assert summary.total_images == 0
    assert summary.warnings


def test_scan_two_batch_dataset(config, two_batch_raw_dataset):
    summary = scan_raw_data(Path(config.raw_data_root), "barley")
    assert summary.n_batches == 2
    assert summary.leakage_safe_possible
    assert set(summary.class_counts) == {"GOOD", "DAMAGED", "BROKEN", "SHRIVELED", "IMPURITIES"}
    assert all(n == 40 for n in summary.class_counts.values())
    assert summary.is_ready
    assert not any("leakage" in w.lower() for w in summary.warnings)


def test_scan_single_batch_flags_leakage(config, tmp_path):
    raw = Path(config.raw_data_root) / "barley" / "GOOD"
    raw.mkdir(parents=True)
    (raw / "fake.jpg").write_bytes(b"not a real image, just needs to exist for the count")
    summary = scan_raw_data(Path(config.raw_data_root), "barley")
    assert summary.n_batches == 1
    assert not summary.leakage_safe_possible
    assert any("leakage" in w.lower() for w in summary.warnings)

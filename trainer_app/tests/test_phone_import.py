from __future__ import annotations

import zipfile
from pathlib import Path

from sort.phone_import import import_phone_export


def _write_zip(path: Path, entries: dict[str, bytes]) -> None:
    with zipfile.ZipFile(path, "w") as zf:
        for name, data in entries.items():
            zf.writestr(name, data)


def test_import_phone_export_writes_matching_layout(tmp_path: Path):
    zip_path = tmp_path / "export.zip"
    _write_zip(
        zip_path,
        {
            "barley/app_2026-10-02/GOOD/seed1.png": b"a",
            "barley/app_2026-10-02/DAMAGED/seed2.png": b"b",
            "barley/app_2026-10-03/GOOD/seed3.png": b"c",
        },
    )
    raw_root = tmp_path / "raw"

    summary = import_phone_export(zip_path, raw_root, "barley")

    assert summary.total_added == 3
    assert summary.added == {"GOOD": 2, "DAMAGED": 1}
    assert summary.batches == {"app_2026-10-02", "app_2026-10-03"}
    assert not summary.skipped
    assert (raw_root / "barley" / "app_2026-10-02" / "GOOD" / "seed1.png").read_bytes() == b"a"
    assert (raw_root / "barley" / "app_2026-10-03" / "GOOD" / "seed3.png").read_bytes() == b"c"


def test_import_phone_export_never_touches_other_batches(tmp_path: Path):
    raw_root = tmp_path / "raw"
    existing = raw_root / "barley" / "batch_2026-09-01" / "GOOD" / "manual.png"
    existing.parent.mkdir(parents=True)
    existing.write_bytes(b"manual-sort")

    zip_path = tmp_path / "export.zip"
    _write_zip(zip_path, {"barley/app_2026-10-02/GOOD/seed1.png": b"a"})

    import_phone_export(zip_path, raw_root, "barley")

    assert existing.read_bytes() == b"manual-sort"  # untouched by the import


def test_import_phone_export_reimport_overwrites_same_batch_idempotently(tmp_path: Path):
    raw_root = tmp_path / "raw"
    zip_path = tmp_path / "export.zip"
    _write_zip(zip_path, {"barley/app_2026-10-02/GOOD/seed1.png": b"first"})
    import_phone_export(zip_path, raw_root, "barley")

    _write_zip(
        zip_path,
        {
            "barley/app_2026-10-02/GOOD/seed1.png": b"first-updated",
            "barley/app_2026-10-02/GOOD/seed2.png": b"second",
        },
    )
    summary = import_phone_export(zip_path, raw_root, "barley")

    assert summary.added == {"GOOD": 2}
    assert (raw_root / "barley" / "app_2026-10-02" / "GOOD" / "seed1.png").read_bytes() == b"first-updated"
    assert (raw_root / "barley" / "app_2026-10-02" / "GOOD" / "seed2.png").read_bytes() == b"second"


def test_import_phone_export_skips_wrong_crop_and_bad_label(tmp_path: Path):
    raw_root = tmp_path / "raw"
    zip_path = tmp_path / "export.zip"
    _write_zip(
        zip_path,
        {
            "wheat/app_2026-10-02/GOOD/seed1.png": b"a",
            "barley/app_2026-10-02/MOLD_SUSPECT/seed2.png": b"b",
            "barley/flat_file.png": b"c",
        },
    )

    summary = import_phone_export(zip_path, raw_root, "barley")

    assert summary.total_added == 0
    assert len(summary.skipped) == 3
    assert not (raw_root / "barley").exists()


def test_import_phone_export_empty_zip(tmp_path: Path):
    zip_path = tmp_path / "export.zip"
    _write_zip(zip_path, {})

    summary = import_phone_export(zip_path, tmp_path / "raw", "barley")

    assert summary.total_added == 0
    assert summary.skipped == ["Zip is empty."]

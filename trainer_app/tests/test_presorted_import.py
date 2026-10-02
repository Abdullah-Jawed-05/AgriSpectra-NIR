from __future__ import annotations

from pathlib import Path

import pytest

from sort.presorted_import import (
    BatchExistsError,
    default_presorted_batch_id,
    import_presorted,
    normalize_label,
    scan_presorted_folder,
)


def _make(root: Path, layout: dict[str, list[str]]) -> Path:
    for folder, files in layout.items():
        d = root / folder
        d.mkdir(parents=True, exist_ok=True)
        for name in files:
            (d / name).write_bytes(b"x")
    return root


@pytest.mark.parametrize(
    "folder,expected",
    [
        ("Good", "GOOD"),
        ("good", "GOOD"),
        ("Impurity", "IMPURITIES"),  # Barley V4 names it singular
        ("Impurities", "IMPURITIES"),
        ("Shrivelled", "SHRIVELED"),
        ("foreign matter", "IMPURITIES"),
        ("Misc", None),
        ("Unknown", None),  # a fallback class, never a deliberate sorting target
    ],
)
def test_normalize_label(folder, expected):
    assert normalize_label(folder) == expected


def test_scan_maps_barley_v4_shaped_folder(tmp_path):
    src = _make(
        tmp_path / "Barley V4",
        {
            "Good": ["a.jpg", "b.JPG"],
            "Impurity": ["c.jpg"],
            "Shriveled": ["d.jpeg", "notes.txt"],
            "Misc": ["e.jpg"],
        },
    )
    (src / "loose.jpg").write_bytes(b"x")

    plan = scan_presorted_folder(src)

    assert plan.counts == {"GOOD": 2, "IMPURITIES": 1, "SHRIVELED": 1}
    assert plan.total == 4
    assert ("Impurity", "IMPURITIES") in plan.renamed
    assert ("Good", "GOOD") not in plan.renamed  # only case differs: not worth flagging
    assert plan.unrecognized_folders == ["Misc"]
    assert plan.skipped_files == 1
    assert plan.loose_images == 1


def test_import_copies_into_canonical_layout_and_leaves_source(tmp_path):
    src = _make(tmp_path / "src", {"Good": ["a.jpg"], "Impurity": ["b.jpg"]})
    raw = tmp_path / "raw"
    plan = scan_presorted_folder(src)

    copied = import_presorted(plan, raw, "barley", "sorted_src")

    assert copied == {"GOOD": 1, "IMPURITIES": 1}
    assert (raw / "barley" / "sorted_src" / "GOOD" / "a.jpg").is_file()
    assert (raw / "barley" / "sorted_src" / "IMPURITIES" / "b.jpg").is_file()
    assert (src / "Good" / "a.jpg").is_file()  # copied, not moved


def test_import_refuses_existing_batch(tmp_path):
    src = _make(tmp_path / "src", {"Good": ["a.jpg"]})
    raw = tmp_path / "raw"
    (raw / "barley" / "sorted_src").mkdir(parents=True)
    with pytest.raises(BatchExistsError):
        import_presorted(scan_presorted_folder(src), raw, "barley", "sorted_src")


def test_two_folders_mapping_to_one_class_dont_overwrite(tmp_path):
    src = _make(tmp_path / "src", {"Impurity": ["x.jpg"], "Impurities": ["x.jpg"]})
    raw = tmp_path / "raw"
    copied = import_presorted(scan_presorted_folder(src), raw, "barley", "b")
    assert copied == {"IMPURITIES": 2}
    assert len(list((raw / "barley" / "b" / "IMPURITIES").iterdir())) == 2


def test_default_batch_id_is_prefixed_and_unique(tmp_path):
    raw = tmp_path / "raw"
    src = tmp_path / "Barley V4"
    assert default_presorted_batch_id(raw, "barley", src) == "sorted_barley_v4"
    (raw / "barley" / "sorted_barley_v4").mkdir(parents=True)
    assert default_presorted_batch_id(raw, "barley", src) == "sorted_barley_v4_2"


def test_imported_batch_is_seen_by_train_preflight(tmp_path, config):
    """End to end with Train's own pre-flight scan, so a batch this writes
    is one Train actually picks up."""
    from pipeline.preflight import scan_raw_data

    src = _make(tmp_path / "src", {"Good": ["a.jpg", "b.jpg"], "Impurity": ["c.jpg"]})
    import_presorted(scan_presorted_folder(src), Path(config.raw_data_root), "barley", "sorted_src")

    summary = scan_raw_data(Path(config.raw_data_root), "barley")
    assert summary.class_counts == {"GOOD": 2, "IMPURITIES": 1}
    assert "sorted_src" in summary.batch_ids

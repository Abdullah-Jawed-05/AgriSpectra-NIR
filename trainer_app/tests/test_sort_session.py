from __future__ import annotations

from pathlib import Path

from sort.session import SortSession, default_batch_id


def test_default_batch_id_increments_same_day(config):
    b1 = default_batch_id(config, "barley")
    (Path(config.raw_data_root) / "barley" / b1).mkdir(parents=True)
    b2 = default_batch_id(config, "barley")
    assert b1 != b2
    assert b2.startswith(b1)


def test_import_triage_and_file_round_trip(config, db, import_folder):
    batch_id = default_batch_id(config, "barley")
    session = SortSession.create(db, config, "barley", batch_id, str(import_folder))

    summary = session.import_photos(import_folder)
    assert summary.total == 5
    assert len(summary.usable) == 4
    assert len(summary.textured_rejected) == 1

    stats = session.stats()
    assert stats["total"] == 12  # 4 usable photos x 3 seeds each
    assert stats["pending"] == 12

    filed = []
    while True:
        item = session.current_item()
        if item is None:
            break
        filed_row = session.file_current(item["suggested_label"])
        filed.append(filed_row)

    stats = session.stats()
    assert stats["pending"] == 0
    assert stats["filed"] == 12

    raw_files = list((Path(config.raw_data_root) / "barley" / batch_id).rglob("*.png"))
    assert len(raw_files) == 12


def test_undo_removes_written_file(config, db, import_folder):
    batch_id = default_batch_id(config, "barley")
    session = SortSession.create(db, config, "barley", batch_id, str(import_folder))
    session.import_photos(import_folder)

    item = session.current_item()
    filed = session.file_current("GOOD")
    assert Path(filed["filed_path"]).is_file()

    session.undo_last()
    assert not Path(filed["filed_path"]).is_file()
    assert session.current_item()["id"] == item["id"]


def test_refile_moves_between_class_folders(config, db, import_folder):
    batch_id = default_batch_id(config, "barley")
    session = SortSession.create(db, config, "barley", batch_id, str(import_folder))
    session.import_photos(import_folder)

    filed = session.file_current("GOOD")
    good_path = Path(filed["filed_path"])
    assert good_path.parent.name == "GOOD"

    refiled = session.refile(filed["id"], "DAMAGED")
    assert Path(refiled["filed_path"]).parent.name == "DAMAGED"
    assert not good_path.is_file()
    assert Path(refiled["filed_path"]).is_file()


def test_override_rejected_photo_adds_items(config, db, import_folder):
    batch_id = default_batch_id(config, "barley")
    session = SortSession.create(db, config, "barley", batch_id, str(import_folder))
    session.import_photos(import_folder)

    rejected = session.rejected_photos()
    textured = next(r for r in rejected if r["reason"] == "textured background")
    before = session.stats()["total"]
    n_added = session.override_rejected(textured)
    after = session.stats()["total"]
    assert after - before == n_added

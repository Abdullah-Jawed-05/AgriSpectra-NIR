from __future__ import annotations


def test_sort_queue_filing_and_undo(db):
    sid = db.create_session("barley", "batch_2026-10-01", "/tmp/raw")
    db.add_queue_items(
        sid,
        [
            {"source_image": "a.jpg", "crop_image_path": "/tmp/a1.png", "suggested_label": "GOOD", "suggested_reason": "r"},
            {"source_image": "a.jpg", "crop_image_path": "/tmp/a2.png", "suggested_label": "DAMAGED", "suggested_reason": "r"},
        ],
    )
    assert db.queue_counts(sid) == {"pending": 2, "filed": 0, "total": 2}

    item = db.next_unfiled(sid)
    db.file_item(item["id"], "GOOD", "/tmp/raw/barley/batch/GOOD/a1.png")
    assert db.queue_counts(sid) == {"pending": 1, "filed": 1, "total": 2}
    assert db.class_counts(sid) == {"GOOD": 1}

    last = db.last_filed(sid)
    assert last["id"] == item["id"]
    db.unfile_item(last["id"])
    assert db.queue_counts(sid) == {"pending": 2, "filed": 0, "total": 2}


def test_run_history_and_best_run(db):
    r1 = db.create_run("/tmp/w1")
    db.finish_run(r1, macro_f1=0.6, balanced_accuracy=0.55)
    r2 = db.create_run("/tmp/w2")
    db.finish_run(r2, macro_f1=0.8, balanced_accuracy=0.75)

    best_before_r2 = db.best_run_before(r2)
    assert best_before_r2["id"] == r1

    best_before_r1 = db.best_run_before(r1)
    assert best_before_r1 is None

    runs = db.list_runs()
    assert [r["id"] for r in runs] == [r2, r1]


def test_rejected_photos_override(db):
    sid = db.create_session("barley", "batch_1", "/tmp/raw")
    db.add_rejected(sid, "/tmp/bad.jpg", "textured background")
    rows = db.rejected_photos(sid)
    assert len(rows) == 1
    assert rows[0]["overridden"] == 0
    db.mark_rejected_overridden(rows[0]["id"])
    assert db.rejected_photos(sid)[0]["overridden"] == 1

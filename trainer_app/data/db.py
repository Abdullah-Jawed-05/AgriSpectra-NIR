"""SQLite store for the trainer app's *own* state only — sort-session
progress, the undo stack, and training-run history (§5: "a small local
SQLite file is fine for app-only state... but never as the source of
truth for the actual dataset; that stays as plain files").

Every write here is immediate (autocommit, WAL) so a crash mid-sort or
mid-run loses at most the in-flight row, never the whole session — the
non-negotiable in §6 ("never lose sorted data").
"""

from __future__ import annotations

import json
import sqlite3
import time
import uuid
from contextlib import contextmanager
from pathlib import Path
from typing import Any, Iterator, Optional

SCHEMA = """
CREATE TABLE IF NOT EXISTS sort_sessions (
    id TEXT PRIMARY KEY,
    crop TEXT NOT NULL,
    batch_id TEXT NOT NULL,
    source_folder TEXT NOT NULL,
    created_at REAL NOT NULL,
    updated_at REAL NOT NULL,
    status TEXT NOT NULL DEFAULT 'active'   -- active | completed
);

CREATE TABLE IF NOT EXISTS sort_queue_items (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    session_id TEXT NOT NULL REFERENCES sort_sessions(id),
    order_index INTEGER NOT NULL,
    source_image TEXT NOT NULL,
    crop_image_path TEXT NOT NULL,
    suggested_label TEXT,
    suggested_reason TEXT,
    filed_label TEXT,
    filed_path TEXT,
    filed_at REAL
);
CREATE INDEX IF NOT EXISTS idx_queue_session_order
    ON sort_queue_items(session_id, order_index);

CREATE TABLE IF NOT EXISTS rejected_photos (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    session_id TEXT NOT NULL REFERENCES sort_sessions(id),
    source_image TEXT NOT NULL,
    reason TEXT NOT NULL,
    overridden INTEGER NOT NULL DEFAULT 0
);

CREATE TABLE IF NOT EXISTS runs (
    id TEXT PRIMARY KEY,
    created_at REAL NOT NULL,
    status TEXT NOT NULL,              -- running | succeeded | failed
    current_stage TEXT,
    work_dir TEXT NOT NULL,
    model_dir TEXT,
    eval_dir TEXT,
    log TEXT NOT NULL DEFAULT '',
    error TEXT,
    n_train_rows INTEGER,
    n_val_rows INTEGER,
    n_test_rows INTEGER,
    n_batches INTEGER,
    test_leakage_safe INTEGER,
    val_leakage_safe INTEGER,
    macro_f1 REAL,
    balanced_accuracy REAL,
    roc_auc REAL,
    confusion_matrix_json TEXT,
    per_class_json TEXT,
    label_classes_json TEXT,
    promoted INTEGER NOT NULL DEFAULT 0
);
"""


def new_id() -> str:
    return uuid.uuid4().hex[:12]


class Database:
    def __init__(self, path: Path):
        self.path = Path(path)
        self.path.parent.mkdir(parents=True, exist_ok=True)
        self._conn = sqlite3.connect(str(self.path), check_same_thread=False)
        self._conn.row_factory = sqlite3.Row
        self._conn.execute("PRAGMA journal_mode=WAL")
        self._conn.execute("PRAGMA foreign_keys=ON")
        self._conn.executescript(SCHEMA)
        self._conn.commit()

    @contextmanager
    def cursor(self) -> Iterator[sqlite3.Cursor]:
        cur = self._conn.cursor()
        try:
            yield cur
            self._conn.commit()
        except Exception:
            self._conn.rollback()
            raise

    def close(self) -> None:
        self._conn.close()

    # ---- sort sessions ----------------------------------------------

    def get_active_session(self, crop: str) -> Optional[sqlite3.Row]:
        with self.cursor() as cur:
            cur.execute(
                "SELECT * FROM sort_sessions WHERE crop=? AND status='active' "
                "ORDER BY created_at DESC LIMIT 1",
                (crop,),
            )
            return cur.fetchone()

    def create_session(self, crop: str, batch_id: str, source_folder: str) -> str:
        session_id = new_id()
        now = time.time()
        with self.cursor() as cur:
            cur.execute(
                "INSERT INTO sort_sessions (id, crop, batch_id, source_folder, created_at, updated_at, status) "
                "VALUES (?, ?, ?, ?, ?, ?, 'active')",
                (session_id, crop, batch_id, source_folder, now, now),
            )
        return session_id

    def touch_session(self, session_id: str) -> None:
        with self.cursor() as cur:
            cur.execute("UPDATE sort_sessions SET updated_at=? WHERE id=?", (time.time(), session_id))

    def complete_session(self, session_id: str) -> None:
        with self.cursor() as cur:
            cur.execute(
                "UPDATE sort_sessions SET status='completed', updated_at=? WHERE id=?",
                (time.time(), session_id),
            )

    def get_session(self, session_id: str) -> Optional[sqlite3.Row]:
        with self.cursor() as cur:
            cur.execute("SELECT * FROM sort_sessions WHERE id=?", (session_id,))
            return cur.fetchone()

    def recent_sessions(self, crop: str, limit: int = 20) -> list[sqlite3.Row]:
        with self.cursor() as cur:
            cur.execute(
                "SELECT * FROM sort_sessions WHERE crop=? ORDER BY created_at DESC LIMIT ?",
                (crop, limit),
            )
            return cur.fetchall()

    # ---- sort queue ---------------------------------------------------

    def add_queue_items(self, session_id: str, items: list[dict[str, Any]]) -> None:
        """`items`: list of {source_image, crop_image_path, suggested_label, suggested_reason}."""
        with self.cursor() as cur:
            cur.execute(
                "SELECT COALESCE(MAX(order_index), -1) FROM sort_queue_items WHERE session_id=?",
                (session_id,),
            )
            start = cur.fetchone()[0] + 1
            cur.executemany(
                "INSERT INTO sort_queue_items "
                "(session_id, order_index, source_image, crop_image_path, suggested_label, suggested_reason) "
                "VALUES (?, ?, ?, ?, ?, ?)",
                [
                    (
                        session_id,
                        start + i,
                        it["source_image"],
                        it["crop_image_path"],
                        it.get("suggested_label"),
                        it.get("suggested_reason"),
                    )
                    for i, it in enumerate(items)
                ],
            )

    def next_unfiled(self, session_id: str) -> Optional[sqlite3.Row]:
        with self.cursor() as cur:
            cur.execute(
                "SELECT * FROM sort_queue_items WHERE session_id=? AND filed_label IS NULL "
                "ORDER BY order_index LIMIT 1",
                (session_id,),
            )
            return cur.fetchone()

    def queue_counts(self, session_id: str) -> dict[str, int]:
        with self.cursor() as cur:
            cur.execute(
                "SELECT COUNT(*) FILTER (WHERE filed_label IS NULL) AS pending, "
                "COUNT(*) FILTER (WHERE filed_label IS NOT NULL) AS filed, "
                "COUNT(*) AS total FROM sort_queue_items WHERE session_id=?",
                (session_id,),
            )
            row = cur.fetchone()
            return {"pending": row["pending"], "filed": row["filed"], "total": row["total"]}

    def class_counts(self, session_id: str) -> dict[str, int]:
        with self.cursor() as cur:
            cur.execute(
                "SELECT filed_label, COUNT(*) AS n FROM sort_queue_items "
                "WHERE session_id=? AND filed_label IS NOT NULL GROUP BY filed_label",
                (session_id,),
            )
            return {r["filed_label"]: r["n"] for r in cur.fetchall()}

    def file_item(self, item_id: int, label: str, filed_path: str) -> None:
        with self.cursor() as cur:
            cur.execute(
                "UPDATE sort_queue_items SET filed_label=?, filed_path=?, filed_at=? WHERE id=?",
                (label, filed_path, time.time(), item_id),
            )

    def last_filed(self, session_id: str) -> Optional[sqlite3.Row]:
        with self.cursor() as cur:
            cur.execute(
                "SELECT * FROM sort_queue_items WHERE session_id=? AND filed_label IS NOT NULL "
                "ORDER BY filed_at DESC LIMIT 1",
                (session_id,),
            )
            return cur.fetchone()

    def unfile_item(self, item_id: int) -> None:
        with self.cursor() as cur:
            cur.execute(
                "UPDATE sort_queue_items SET filed_label=NULL, filed_path=NULL, filed_at=NULL WHERE id=?",
                (item_id,),
            )

    def refile_item(self, item_id: int, label: str, filed_path: str) -> None:
        with self.cursor() as cur:
            cur.execute(
                "UPDATE sort_queue_items SET filed_label=?, filed_path=?, filed_at=? WHERE id=?",
                (label, filed_path, time.time(), item_id),
            )

    def recent_filed(self, session_id: str, limit: int = 500) -> list[sqlite3.Row]:
        with self.cursor() as cur:
            cur.execute(
                "SELECT * FROM sort_queue_items WHERE session_id=? AND filed_label IS NOT NULL "
                "ORDER BY filed_at DESC LIMIT ?",
                (session_id, limit),
            )
            return cur.fetchall()

    def get_item(self, item_id: int) -> Optional[sqlite3.Row]:
        with self.cursor() as cur:
            cur.execute("SELECT * FROM sort_queue_items WHERE id=?", (item_id,))
            return cur.fetchone()

    # ---- rejected photos -----------------------------------------------

    def add_rejected(self, session_id: str, source_image: str, reason: str) -> None:
        with self.cursor() as cur:
            cur.execute(
                "INSERT INTO rejected_photos (session_id, source_image, reason) VALUES (?, ?, ?)",
                (session_id, source_image, reason),
            )

    def rejected_photos(self, session_id: str) -> list[sqlite3.Row]:
        with self.cursor() as cur:
            cur.execute("SELECT * FROM rejected_photos WHERE session_id=?", (session_id,))
            return cur.fetchall()

    def mark_rejected_overridden(self, rejected_id: int) -> None:
        with self.cursor() as cur:
            cur.execute("UPDATE rejected_photos SET overridden=1 WHERE id=?", (rejected_id,))

    # ---- training runs -------------------------------------------------

    def create_run(self, work_dir: str) -> str:
        run_id = new_id()
        with self.cursor() as cur:
            cur.execute(
                "INSERT INTO runs (id, created_at, status, work_dir) VALUES (?, ?, 'running', ?)",
                (run_id, time.time(), work_dir),
            )
        return run_id

    def set_work_dir(self, run_id: str, work_dir: str) -> None:
        with self.cursor() as cur:
            cur.execute("UPDATE runs SET work_dir=? WHERE id=?", (work_dir, run_id))

    def append_log(self, run_id: str, text: str) -> None:
        with self.cursor() as cur:
            cur.execute("UPDATE runs SET log = log || ? WHERE id=?", (text, run_id))

    def set_stage(self, run_id: str, stage: str) -> None:
        with self.cursor() as cur:
            cur.execute("UPDATE runs SET current_stage=? WHERE id=?", (stage, run_id))

    def fail_run(self, run_id: str, error: str) -> None:
        with self.cursor() as cur:
            cur.execute("UPDATE runs SET status='failed', error=? WHERE id=?", (error, run_id))

    def finish_run(self, run_id: str, **fields: Any) -> None:
        if not fields:
            with self.cursor() as cur:
                cur.execute("UPDATE runs SET status='succeeded' WHERE id=?", (run_id,))
            return
        cols = ", ".join(f"{k}=?" for k in fields)
        values = list(fields.values())
        with self.cursor() as cur:
            cur.execute(f"UPDATE runs SET status='succeeded', {cols} WHERE id=?", (*values, run_id))

    def get_run(self, run_id: str) -> Optional[sqlite3.Row]:
        with self.cursor() as cur:
            cur.execute("SELECT * FROM runs WHERE id=?", (run_id,))
            return cur.fetchone()

    def list_runs(self, limit: int = 100) -> list[sqlite3.Row]:
        with self.cursor() as cur:
            cur.execute("SELECT * FROM runs ORDER BY created_at DESC LIMIT ?", (limit,))
            return cur.fetchall()

    def best_run_before(self, run_id: str, metric: str = "macro_f1") -> Optional[sqlite3.Row]:
        """The best succeeded run strictly *before* `run_id` in time, by
        `metric` — used for the "compare against previous best" headline
        (§3 Mode B.3). Chronological, not just "best other run": a run
        created later must never be used as the "previous" best."""
        if metric not in {"macro_f1", "balanced_accuracy", "roc_auc"}:
            raise ValueError(metric)
        with self.cursor() as cur:
            cur.execute(
                f"SELECT * FROM runs WHERE status='succeeded' AND {metric} IS NOT NULL "
                f"AND created_at < (SELECT created_at FROM runs WHERE id = ?) "
                f"ORDER BY {metric} DESC LIMIT 1",
                (run_id,),
            )
            return cur.fetchone()

    def mark_promoted(self, run_id: str) -> None:
        with self.cursor() as cur:
            cur.execute("UPDATE runs SET promoted=1 WHERE id=?", (run_id,))


def dumps(obj: Any) -> str:
    return json.dumps(obj)


def loads(text: Optional[str]) -> Any:
    if not text:
        return None
    return json.loads(text)

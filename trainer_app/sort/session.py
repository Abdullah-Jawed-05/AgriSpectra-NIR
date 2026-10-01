"""Sort Mode session state machine — §3 Mode A.

Owns batch-id assignment (§3.6), the import/triage step, the file-one-
seed/undo-one-seed loop, and the review/re-file list (§3.8). The
filesystem under `raw_data_root/<crop>/<batch_id>/<LABEL>/` is the
durable truth (§6 "never lose sorted data") — the SQLite queue is only
bookkeeping for the UI (what's left, what's filed, the undo pointer) and
can be rebuilt by re-importing if it's ever lost; the filed photos
themselves cannot.
"""

from __future__ import annotations

import re
import shutil
from datetime import date
from pathlib import Path
from typing import Callable, Optional

from core.config import AppConfig
from data.db import Database
from sort.importer import TriageSummary, build_queue_items, triage_folder


def default_batch_id(config: AppConfig, crop: str, today: Optional[date] = None) -> str:
    """Today's date, with an auto-incrementing suffix if more than one
    session happens in a day (§3.6) — quietly handled, never asked."""
    today = today or date.today()
    prefix = f"batch_{today.isoformat()}"
    crop_dir = Path(config.raw_data_root) / crop
    existing = set()
    if crop_dir.is_dir():
        existing = {p.name for p in crop_dir.iterdir() if p.is_dir()}
    if prefix not in existing:
        return prefix
    n = 2
    while f"{prefix}_{n}" in existing:
        n += 1
    return f"{prefix}_{n}"


def _sanitize(name: str) -> str:
    return re.sub(r"[^A-Za-z0-9_.-]+", "_", name)


class SortSession:
    def __init__(self, db: Database, config: AppConfig, row) -> None:
        self.db = db
        self.config = config
        self.id: str = row["id"]
        self.crop: str = row["crop"]
        self.batch_id: str = row["batch_id"]
        self.source_folder: str = row["source_folder"]

    # ---- lifecycle ------------------------------------------------

    @classmethod
    def find_active(cls, db: Database, config: AppConfig, crop: str) -> Optional["SortSession"]:
        row = db.get_active_session(crop)
        return cls(db, config, row) if row else None

    @classmethod
    def create(cls, db: Database, config: AppConfig, crop: str, batch_id: str, source_folder: str) -> "SortSession":
        session_id = db.create_session(crop, batch_id, source_folder)
        return cls(db, config, db.get_session(session_id))

    @classmethod
    def resume(cls, db: Database, config: AppConfig, session_id: str) -> "SortSession":
        row = db.get_session(session_id)
        if row is None:
            raise KeyError(f"no sort session {session_id!r}")
        return cls(db, config, row)

    def crops_cache_dir(self) -> Path:
        return Path(self.config.work_root) / "sort_cache" / self.id

    def complete(self) -> None:
        self.db.complete_session(self.id)

    # ---- import / triage --------------------------------------------

    def import_photos(
        self,
        folder: Path,
        allow_textured_bg: bool = False,
        one_seed: bool = False,
        on_progress: Optional[Callable[[int, int], None]] = None,
    ) -> TriageSummary:
        summary = triage_folder(folder, self.config, allow_textured_bg=allow_textured_bg, on_progress=on_progress)
        for photo in summary.photos:
            if not photo.usable:
                self.db.add_rejected(self.id, str(photo.path), photo.reason or "rejected")

        items = build_queue_items(
            [p.path for p in summary.usable],
            self.config,
            self.crops_cache_dir(),
            allow_textured_bg=allow_textured_bg,
            one_seed=one_seed,
            on_progress=on_progress,
        )
        if items:
            self.db.add_queue_items(self.id, items)
        self.db.touch_session(self.id)
        return summary

    def override_rejected(self, rejected_row, on_progress: Optional[Callable[[int, int], None]] = None) -> int:
        """Keep a rejected photo anyway (§3 Mode A.1 — "let the user see
        them and decide"). Returns how many seed-crop queue items it added."""
        path = Path(rejected_row["source_image"])
        allow_textured = rejected_row["reason"] == "textured background"
        items = build_queue_items(
            [path], self.config, self.crops_cache_dir(), allow_textured_bg=allow_textured, on_progress=on_progress
        )
        if items:
            self.db.add_queue_items(self.id, items)
        self.db.mark_rejected_overridden(rejected_row["id"])
        self.db.touch_session(self.id)
        return len(items)

    def rejected_photos(self):
        return self.db.rejected_photos(self.id)

    # ---- the sort loop -----------------------------------------------

    def current_item(self):
        return self.db.next_unfiled(self.id)

    def stats(self) -> dict:
        counts = self.db.queue_counts(self.id)
        counts["by_class"] = self.db.class_counts(self.id)
        return counts

    def _label_dir(self, label: str) -> Path:
        d = Path(self.config.raw_data_root) / self.crop / self.batch_id / label
        d.mkdir(parents=True, exist_ok=True)
        return d

    def file_current(self, label: str):
        """Confirms/overrides the pre-suggestion for the current item and
        writes it to raw/<crop>/<batch_id>/<LABEL>/ (§3 Mode A.7)."""
        item = self.current_item()
        if item is None:
            return None
        dest = self._label_dir(label) / f"{item['id']:06d}_{_sanitize(Path(item['crop_image_path']).name)}"
        shutil.copy2(item["crop_image_path"], dest)
        self.db.file_item(item["id"], label, str(dest))
        self.db.touch_session(self.id)
        return self.db.get_item(item["id"])

    def undo_last(self):
        """Single-keystroke undo of the most recent filing (§3 Mode A.3)."""
        last = self.db.last_filed(self.id)
        if last is None:
            return None
        filed_path = Path(last["filed_path"])
        if filed_path.is_file():
            filed_path.unlink()
        self.db.unfile_item(last["id"])
        self.db.touch_session(self.id)
        return self.db.get_item(last["id"])

    def refile(self, item_id: int, new_label: str):
        """Re-files an already-sorted item to a different class — the
        filmstrip review/fix-up action (§3 Mode A.8)."""
        item = self.db.get_item(item_id)
        if item is None or item["filed_label"] is None:
            return None
        old_path = Path(item["filed_path"])
        dest = self._label_dir(new_label) / f"{item_id:06d}_{_sanitize(Path(item['crop_image_path']).name)}"
        if old_path.is_file():
            if old_path.parent != dest.parent:
                shutil.move(str(old_path), str(dest))
            else:
                old_path.rename(dest)
        else:
            shutil.copy2(item["crop_image_path"], dest)
        self.db.refile_item(item_id, new_label, str(dest))
        self.db.touch_session(self.id)
        return self.db.get_item(item_id)

    def review_filmstrip(self, limit: int = 500):
        return self.db.recent_filed(self.id, limit=limit)

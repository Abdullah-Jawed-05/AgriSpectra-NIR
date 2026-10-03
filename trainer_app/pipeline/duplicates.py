"""Finding the same photo in more than one batch.

Batch folders are what the train/test split holds apart, so "leakage-safe"
assumes different batches hold different photos. Importing the same
pre-sorted folder twice under two names breaks that silently: the test batch
is then mostly photos the model trained on, and its score says nothing about
new seeds. Photos are compared by content (SHA-1 of the file bytes), so a
renamed or re-copied file still counts as the same photo.
"""

from __future__ import annotations

import csv
import hashlib
import re
from dataclasses import dataclass
from itertools import combinations
from pathlib import Path
from typing import Iterable

IMAGE_EXTS = {".jpg", ".jpeg", ".png"}

# (path, size, mtime_ns) -> digest. Pre-flight re-scans on every checkbox
# click; only new or changed files are read again.
_digest_cache: dict[tuple[str, int, int], str] = {}


def file_digest(path: Path) -> str:
    st = path.stat()
    key = (str(path), st.st_size, st.st_mtime_ns)
    digest = _digest_cache.get(key)
    if digest is None:
        h = hashlib.sha1()
        with open(path, "rb") as f:
            for chunk in iter(lambda: f.read(1 << 20), b""):
                h.update(chunk)
        digest = _digest_cache[key] = h.hexdigest()
    return digest


def _normalize_label(name: str) -> str:
    return re.sub(r"[\s-]+", "_", name.strip()).upper()


def batch_dir(raw_crop_dir: Path, batch_id: str) -> Path:
    """A crop without batch folders is the single implicit batch
    "<crop>_unbatched" (prepare_dataset.py), living in the crop folder."""
    d = raw_crop_dir / batch_id
    return d if d.is_dir() else raw_crop_dir


def batch_digests(raw_crop_dir: Path, batch_id: str) -> set[str]:
    root = batch_dir(raw_crop_dir, batch_id)
    return {
        file_digest(p)
        for label_dir in root.iterdir() if label_dir.is_dir()
        for p in label_dir.iterdir() if p.suffix.lower() in IMAGE_EXTS
    }


@dataclass(frozen=True)
class SharedPhotos:
    batch_a: str
    batch_b: str
    n_shared: int


def find_shared_photos(raw_crop_dir: Path, batch_ids: Iterable[str]) -> list[SharedPhotos]:
    """Every pair of the given batches that holds identical photos."""
    digests = {b: batch_digests(raw_crop_dir, b) for b in batch_ids}
    return [
        SharedPhotos(a, b, n)
        for a, b in combinations(sorted(digests), 2)
        if (n := len(digests[a] & digests[b]))
    ]


def _row_photo(raw_crop_dir: Path, row: dict, label_dirs: dict) -> Path | None:
    batch_id = row["batch_id"]
    if batch_id not in label_dirs:
        root = batch_dir(raw_crop_dir, batch_id)
        label_dirs[batch_id] = {_normalize_label(d.name): d for d in root.iterdir() if d.is_dir()}
    d = label_dirs[batch_id].get(row["label"])
    p = d / row["source_image"] if d else None
    return p if p is not None and p.is_file() else None


def _csv_digests(raw_crop_dir: Path, csv_path: Path, label_dirs: dict) -> list[str | None]:
    with open(csv_path, newline="", encoding="utf-8") as f:
        rows = list(csv.DictReader(f))
    out = []
    for row in rows:
        p = _row_photo(raw_crop_dir, row, label_dirs)
        out.append(file_digest(p) if p else None)
    return out


def count_test_rows_seen_in_training(raw_crop_dir: Path, split_dir: Path) -> int:
    """How many test rows come from a photo that also appears in train or
    val. Rows whose photo can't be found are not counted."""
    label_dirs: dict = {}
    seen = {
        d
        for name in ("train.csv", "val.csv")
        if (split_dir / name).is_file()
        for d in _csv_digests(raw_crop_dir, split_dir / name, label_dirs)
        if d
    }
    return sum(1 for d in _csv_digests(raw_crop_dir, split_dir / "test.csv", label_dirs) if d and d in seen)

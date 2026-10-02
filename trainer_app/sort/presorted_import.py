"""Import a folder of photos someone has already sorted by hand —
`<folder>/<Label>/*.jpg` — straight into `raw_data_root/<crop>/<batch_id>/<LABEL>/`.

Unlike Sort Mode's import, nothing is segmented or re-labelled here: the
folder names *are* the labels, and the photos are copied as-is (full
photos, not crops). Train Mode's Stage 1 (`prepare_dataset.py`) segments
them later, exactly as it does for any raw photo.

Two steps so a large copy never happens on a misread folder:
`scan_presorted_folder` only reads, and reports how each folder name maps
to a class (or why it was skipped); `import_presorted` then copies.

Folder names are matched leniently (case, spaces/hyphens, singular/plural,
"shrivelled"), because a hand-made folder is rarely named exactly `IMPURITIES`.
A folder that matches nothing is reported and skipped, never guessed at.
"""

from __future__ import annotations

import re
import shutil
from dataclasses import dataclass, field
from pathlib import Path
from typing import Callable, Optional

VALID_LABELS = ("GOOD", "DAMAGED", "BROKEN", "SHRIVELED", "IMPURITIES")
IMAGE_EXTENSIONS = {".jpg", ".jpeg", ".png"}

# Normalized folder name -> class. Only spellings people actually use for
# these classes; anything else is reported rather than mapped.
_ALIASES = {
    "IMPURITY": "IMPURITIES",
    "IMPURE": "IMPURITIES",
    "FOREIGN_MATTER": "IMPURITIES",
    "NON_SEED": "IMPURITIES",
    "SHRIVELLED": "SHRIVELED",
    "SHRIVEL": "SHRIVELED",
    "BROKEN_SEEDS": "BROKEN",
    "DAMAGED_SEEDS": "DAMAGED",
    "GOOD_SEEDS": "GOOD",
}


def normalize_label(name: str) -> Optional[str]:
    key = re.sub(r"[\s-]+", "_", name.strip()).upper()
    if key in VALID_LABELS:
        return key
    return _ALIASES.get(key)


@dataclass
class PresortedClass:
    folder_name: str
    label: str
    files: list[Path]


@dataclass
class PresortedPlan:
    source: Path
    classes: list[PresortedClass] = field(default_factory=list)
    unrecognized_folders: list[str] = field(default_factory=list)
    skipped_files: int = 0  # non-image files inside recognized label folders
    loose_images: int = 0  # images sitting directly in `source`, not in a label folder

    @property
    def total(self) -> int:
        return sum(len(c.files) for c in self.classes)

    @property
    def counts(self) -> dict[str, int]:
        out: dict[str, int] = {}
        for c in self.classes:
            out[c.label] = out.get(c.label, 0) + len(c.files)
        return out

    @property
    def renamed(self) -> list[tuple[str, str]]:
        """(folder name, class) pairs where the folder wasn't already the
        canonical class name — shown so a lenient match is never silent."""
        return [(c.folder_name, c.label) for c in self.classes if c.folder_name.upper() != c.label]


def scan_presorted_folder(source: Path) -> PresortedPlan:
    """Read-only: works out what `import_presorted` would copy."""
    plan = PresortedPlan(source=source)
    for entry in sorted(source.iterdir()):
        if entry.is_file():
            if entry.suffix.lower() in IMAGE_EXTENSIONS:
                plan.loose_images += 1
            continue
        if not entry.is_dir():
            continue
        label = normalize_label(entry.name)
        if label is None:
            plan.unrecognized_folders.append(entry.name)
            continue
        images: list[Path] = []
        for f in sorted(entry.iterdir()):
            if f.is_file() and f.suffix.lower() in IMAGE_EXTENSIONS:
                images.append(f)
            elif f.is_file():
                plan.skipped_files += 1
        if images:
            plan.classes.append(PresortedClass(entry.name, label, images))
    return plan


def default_presorted_batch_id(raw_data_root: Path, crop: str, source: Path) -> str:
    """`sorted_<folder name>`, suffixed if taken. The `sorted_` prefix keeps
    it distinct from Sort Mode's `batch_<date>` and phone exports'
    `app_<date>`, so the three sources never collide."""
    slug = re.sub(r"[^a-z0-9]+", "_", source.name.lower()).strip("_") or "import"
    base = f"sorted_{slug}"
    crop_dir = raw_data_root / crop
    existing = {p.name for p in crop_dir.iterdir() if p.is_dir()} if crop_dir.is_dir() else set()
    if base not in existing:
        return base
    n = 2
    while f"{base}_{n}" in existing:
        n += 1
    return f"{base}_{n}"


class BatchExistsError(ValueError):
    pass


def import_presorted(
    plan: PresortedPlan,
    raw_data_root: Path,
    crop: str,
    batch_id: str,
    on_progress: Optional[Callable[[int, int], None]] = None,
) -> dict[str, int]:
    """Copies every planned photo into `raw/<crop>/<batch_id>/<LABEL>/`.

    Refuses an existing batch folder rather than merging into it: one
    pre-sorted folder is one collection batch, and silently mixing it into
    another would corrupt the leakage-safe split. Copies, never moves —
    the source folder is left untouched.
    """
    batch_dir = raw_data_root / crop / batch_id
    if batch_dir.exists():
        raise BatchExistsError(f"Batch '{batch_id}' already exists — pick a different batch name.")

    total = plan.total
    done = 0
    copied: dict[str, int] = {}
    for cls in plan.classes:
        dest_dir = batch_dir / cls.label
        dest_dir.mkdir(parents=True, exist_ok=True)
        for src in cls.files:
            dest = dest_dir / src.name
            if dest.exists():  # two source folders mapped to one class with clashing names
                dest = dest_dir / f"{src.parent.name}_{src.name}"
            shutil.copy2(src, dest)
            copied[cls.label] = copied.get(cls.label, 0) + 1
            done += 1
            if on_progress:
                on_progress(done, total)
    return copied

"""Sort Mode import/triage — §3 Mode A.1-2.

Two passes over a folder of raw photos, both using the real
preprocessing code (pipeline/scripts.import_preprocessing), never a
reimplementation:

1. `triage_folder` — the same checks `analyze_capture_set.py` runs
   (background-texture gate, segmentation, pile detection) so the import
   summary ("214 photos imported, 198 usable, 12 textured, 4 piled") is
   backed by the real pipeline, not a guess, before any labelling starts.
2. `build_queue_items` — segments each usable (or deliberately
   overridden) photo again and writes one cached crop PNG per detected
   seed, ready to be inserted into the SQLite sort queue.
"""

from __future__ import annotations

import re
from dataclasses import dataclass, field
from pathlib import Path
from typing import Callable, Optional

import cv2
import numpy as np

from core.config import AppConfig
from pipeline.scripts import import_preprocessing
from sort.suggest import suggest_label

IMAGE_EXTENSIONS = {".jpg", ".jpeg", ".png"}


def imread_unicode(path: Path) -> Optional[np.ndarray]:
    data = np.fromfile(str(path), dtype=np.uint8)
    if data.size == 0:
        return None
    return cv2.imdecode(data, cv2.IMREAD_COLOR)


def list_images(folder: Path) -> list[Path]:
    return sorted(p for p in folder.rglob("*") if p.suffix.lower() in IMAGE_EXTENSIONS)


@dataclass
class TriagedPhoto:
    path: Path
    usable: bool
    reason: Optional[str]
    seeds_found: int = 0
    piled: bool = False
    textured: bool = False


@dataclass
class TriageSummary:
    photos: list[TriagedPhoto] = field(default_factory=list)

    @property
    def total(self) -> int:
        return len(self.photos)

    @property
    def usable(self) -> list[TriagedPhoto]:
        return [p for p in self.photos if p.usable]

    @property
    def textured_rejected(self) -> list[TriagedPhoto]:
        return [p for p in self.photos if p.textured]

    @property
    def piled_rejected(self) -> list[TriagedPhoto]:
        return [p for p in self.photos if p.piled]

    @property
    def no_seed_rejected(self) -> list[TriagedPhoto]:
        return [p for p in self.photos if not p.usable and not p.textured and not p.piled]


def triage_folder(
    folder: Path,
    config: AppConfig,
    allow_textured_bg: bool = False,
    on_progress: Optional[Callable[[int, int], None]] = None,
) -> TriageSummary:
    pp = import_preprocessing(config)
    files = list_images(folder)
    summary = TriageSummary()

    for i, path in enumerate(files, 1):
        image = imread_unicode(path)
        if image is None:
            summary.photos.append(TriagedPhoto(path, usable=False, reason="unreadable file"))
            if on_progress:
                on_progress(i, len(files))
            continue

        textured = False
        if not allow_textured_bg:
            tex = pp.assess_background_texture(image)
            textured = tex.is_textured

        if textured:
            summary.photos.append(
                TriagedPhoto(path, usable=False, reason="textured background", textured=True)
            )
            if on_progress:
                on_progress(i, len(files))
            continue

        result = pp.segment(image)
        if result.piled:
            summary.photos.append(
                TriagedPhoto(path, usable=False, reason="seeds piled / touching", piled=True, seeds_found=len(result.seeds))
            )
        elif not result.seeds:
            summary.photos.append(TriagedPhoto(path, usable=False, reason="no seed detected", seeds_found=0))
        else:
            summary.photos.append(TriagedPhoto(path, usable=True, reason=None, seeds_found=len(result.seeds)))

        if on_progress:
            on_progress(i, len(files))

    return summary


def _safe_stem(path: Path) -> str:
    return re.sub(r"[^A-Za-z0-9_.-]+", "_", path.stem)


def build_queue_items(
    photos: list[Path],
    config: AppConfig,
    crops_cache_dir: Path,
    allow_textured_bg: bool = False,
    one_seed: bool = False,
    on_progress: Optional[Callable[[int, int], None]] = None,
) -> list[dict]:
    """Segments each photo and writes one crop PNG per detected seed to
    `crops_cache_dir`. Returns dicts ready for db.add_queue_items, each
    carrying the V0 rule's pre-suggestion (§3 Mode A.4)."""
    pp = import_preprocessing(config)
    crops_cache_dir.mkdir(parents=True, exist_ok=True)
    items: list[dict] = []

    for i, path in enumerate(photos, 1):
        image = imread_unicode(path)
        if image is None:
            continue

        if not allow_textured_bg:
            tex = pp.assess_background_texture(image)
            if tex.is_textured:
                continue

        result = pp.segment(image)
        seeds = result.seeds
        if one_seed:
            primary = pp.pick_primary_seed(seeds)
            seeds = [primary] if primary is not None else []

        for seed in seeds:
            features = pp.extract_all(seed)
            label, reason = suggest_label(features)
            crop_filename = f"{_safe_stem(path)}_{seed.seed_id}.png"
            crop_path = crops_cache_dir / crop_filename
            cv2.imwrite(str(crop_path), seed.crop_bgr)
            items.append(
                {
                    "source_image": path.name,
                    "crop_image_path": str(crop_path),
                    "suggested_label": label,
                    "suggested_reason": reason,
                }
            )

        if on_progress:
            on_progress(i, len(photos))

    return items

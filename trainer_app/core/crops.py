"""Which crop ("kind of seed") the Trainer is working on.

Every crop's data lives in its own `raw_data_root/<crop>/` folder and is
trained separately; the folder name is a lowercase slug of whatever the
user typed ("Wheat" -> "wheat", "Durum wheat" -> "durum_wheat").

The phone app only knows Barley so far, so only crops in PHONE_APP_CROPS
can be promoted into it — a wheat model must never be wired into an app
that will run it on barley photos. Other crops can still be sorted,
trained and evaluated here.
"""

from __future__ import annotations

import re
from pathlib import Path

DEFAULT_CROP = "barley"
PHONE_APP_CROPS = frozenset({"barley"})


def normalize_crop(name: str) -> str:
    """Folder-safe slug, or "" if nothing usable was typed."""
    return re.sub(r"[^a-z0-9]+", "_", name.strip().lower()).strip("_")


def crop_label(slug: str) -> str:
    return slug.replace("_", " ").capitalize()


def known_crops(raw_data_root: Path, current: str) -> list[str]:
    """Crops that already have a data folder, plus the current one and the
    default, so a brand-new install still offers Barley."""
    found = set()
    if raw_data_root.is_dir():
        found = {p.name for p in raw_data_root.iterdir() if p.is_dir() and normalize_crop(p.name) == p.name}
    return sorted(found | {current, DEFAULT_CROP})


def can_promote_to_phone_app(crop: str) -> bool:
    return crop in PHONE_APP_CROPS

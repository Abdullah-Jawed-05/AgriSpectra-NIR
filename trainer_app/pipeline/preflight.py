"""Train Mode pre-flight summary — §3 Mode B.1.

A pure filesystem scan (no subprocess, no segmentation) over
`raw_data_root/<crop>/`, mirroring `prepare_dataset.py`'s own layout
auto-detection (3-level `batch/<LABEL>` or 2-level `<LABEL>` directly)
so the counts shown before a run match what Stage 1 will actually see.
"""

from __future__ import annotations

from dataclasses import dataclass, field
from pathlib import Path

VALID_LABELS = {"GOOD", "DAMAGED", "BROKEN", "SHRIVELED", "IMPURITIES", "UNKNOWN"}

# A class is flagged imbalanced if it has fewer than this many seeds, or
# fewer than this fraction of the largest class's count.
MIN_CLASS_SEEDS = 20
MIN_CLASS_RATIO = 0.1

# Rough per-image wall-clock budget for the "estimated run time" figure —
# generous, since this is only ever shown as an estimate, never a promise.
EST_SECONDS_PER_IMAGE = 0.6
EST_TRAIN_EVAL_SECONDS = 20


@dataclass
class PreflightSummary:
    class_counts: dict[str, int] = field(default_factory=dict)
    batch_ids: list[str] = field(default_factory=list)
    total_images: int = 0
    warnings: list[str] = field(default_factory=list)

    @property
    def n_batches(self) -> int:
        return len(self.batch_ids)

    @property
    def leakage_safe_possible(self) -> bool:
        return self.n_batches >= 2

    @property
    def estimated_seconds(self) -> float:
        return self.total_images * EST_SECONDS_PER_IMAGE + EST_TRAIN_EVAL_SECONDS

    @property
    def is_ready(self) -> bool:
        return self.total_images > 0 and len(self.class_counts) >= 2


def _normalize_label(name: str) -> str:
    import re

    return re.sub(r"[\s-]+", "_", name.strip()).upper()


def scan_raw_data(raw_data_root: Path, crop: str) -> PreflightSummary:
    summary = PreflightSummary()
    crop_dir = raw_data_root / crop
    if not crop_dir.is_dir():
        summary.warnings.append(f"No data yet under {crop_dir}. Sort some photos first.")
        return summary

    subdirs = sorted(p for p in crop_dir.iterdir() if p.is_dir())
    if not subdirs:
        summary.warnings.append(f"{crop_dir} exists but is empty.")
        return summary

    if all(_normalize_label(d.name) in VALID_LABELS for d in subdirs):
        batches = [(f"{crop}_unbatched", subdirs)]
    else:
        batches = [(b.name, sorted(p for p in b.iterdir() if p.is_dir())) for b in subdirs]

    image_exts = {".jpg", ".jpeg", ".png"}
    for batch_id, label_dirs in batches:
        batch_has_images = False
        for label_dir in label_dirs:
            label = _normalize_label(label_dir.name)
            if label not in VALID_LABELS:
                continue
            n = sum(1 for p in label_dir.iterdir() if p.suffix.lower() in image_exts)
            if n == 0:
                continue
            batch_has_images = True
            summary.class_counts[label] = summary.class_counts.get(label, 0) + n
            summary.total_images += n
        if batch_has_images:
            summary.batch_ids.append(batch_id)

    if not summary.class_counts:
        summary.warnings.append("No labelled photos found under any recognized class folder.")
        return summary

    if len(summary.class_counts) < 2:
        summary.warnings.append(
            "Only one class has any photos — training needs at least two classes to learn a distinction."
        )

    if summary.n_batches < 2:
        summary.warnings.append(
            "Only 1 collection batch exists. The train/test split cannot hold out a whole "
            "session, so the test metrics will NOT be leakage-safe — treat them as a sanity "
            "check only, not a generalization estimate."
        )

    biggest = max(summary.class_counts.values())
    for label, n in summary.class_counts.items():
        if n < MIN_CLASS_SEEDS or n < biggest * MIN_CLASS_RATIO:
            summary.warnings.append(
                f"{label} has only {n} labelled seed(s) — badly imbalanced against the largest "
                f"class ({biggest}). The model will likely underperform on {label}."
            )

    return summary

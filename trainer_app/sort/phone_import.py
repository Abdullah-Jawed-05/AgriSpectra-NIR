"""Import a phone-app training-data export (zip) straight into
`raw_data_root/<crop>/` — closes the "Make Our App Better" -> Trainer gap.

`app/lib/export/training_data_export.dart` builds a zip laid out exactly
as `<crop>/<batch_id>/<LABEL>/<seed_id>.png` (batch_id = `app_YYYY-MM-DD`,
one per day of app usage) — the SAME layout Sort Mode writes to and Train
Mode reads from. So importing is a direct, merging extraction: no
segmentation, no triage, no re-labelling, since every seed in the export
was already human-verified in the app.

Merging is safe without extra bookkeeping because the two batch-naming
schemes never collide: Sort Mode writes `batch_<date>[_n]`, phone exports
always write `app_<date>`. Re-importing the same day's export again just
overwrites that day's files in place (the phone app always exports its
*entire* verified set, per that file's own docstring) — it never touches
any other batch folder, so nothing already sorted or previously imported
is ever lost.
"""

from __future__ import annotations

import re
import zipfile
from dataclasses import dataclass, field
from pathlib import Path

VALID_LABELS = {"GOOD", "DAMAGED", "BROKEN", "SHRIVELED", "IMPURITIES", "UNKNOWN"}

# <crop>/<batch_id>/<LABEL>/<filename>, exactly as TrainingDataExport.buildZip writes it.
_ENTRY_RE = re.compile(r"^([^/]+)/([^/]+)/([^/]+)/([^/]+\.(?:png|jpg|jpeg))$", re.IGNORECASE)


def _normalize_label(name: str) -> str:
    return re.sub(r"[\s-]+", "_", name.strip()).upper()


@dataclass
class PhoneImportSummary:
    added: dict[str, int] = field(default_factory=dict)  # label -> count
    batches: set[str] = field(default_factory=set)
    skipped: list[str] = field(default_factory=list)  # human-readable reasons, never silent

    @property
    def total_added(self) -> int:
        return sum(self.added.values())


def import_phone_export(zip_path: Path, raw_data_root: Path, expected_crop: str) -> PhoneImportSummary:
    """Extracts every entry matching `<expected_crop>/<batch_id>/<LABEL>/<file>`
    into `raw_data_root/<expected_crop>/<batch_id>/<LABEL>/<file>`. Anything
    that doesn't match the expected shape, names a different crop, or
    names a label outside the fixed taxonomy is skipped with a reason
    (§6 "don't hide a rejection") rather than guessed at or silently
    dropped."""
    summary = PhoneImportSummary()

    with zipfile.ZipFile(zip_path) as zf:
        names = [n for n in zf.namelist() if not n.endswith("/")]
        if not names:
            summary.skipped.append("Zip is empty.")
            return summary

        for name in names:
            match = _ENTRY_RE.match(name)
            if not match:
                summary.skipped.append(f"{name}: unexpected path (expected <crop>/<batch>/<LABEL>/<file>)")
                continue

            crop, batch_id, label_raw, filename = match.groups()
            if crop.lower() != expected_crop.lower():
                summary.skipped.append(f"{name}: crop '{crop}' doesn't match current crop '{expected_crop}' — skipped")
                continue

            label = _normalize_label(label_raw)
            if label not in VALID_LABELS:
                summary.skipped.append(f"{name}: unrecognized label '{label_raw}'")
                continue

            dest_dir = raw_data_root / expected_crop / batch_id / label
            dest_dir.mkdir(parents=True, exist_ok=True)
            dest = dest_dir / filename
            with zf.open(name) as src, open(dest, "wb") as out:
                out.write(src.read())

            summary.batches.add(batch_id)
            summary.added[label] = summary.added.get(label, 0) + 1

    return summary

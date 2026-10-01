"""AgriSpectra brand palette and the class-colour mapping.

Mirrors app/lib/presentation/theme (phone app) and badges.dart's
qualityClassColor — keep these hex values identical to the phone app so
the two tools read as siblings.
"""

from __future__ import annotations

# Brand
ACCENT = "#0E6E5D"          # primary teal
ACCENT_MUTED = "#DCEEE9"
INK = "#171E1B"
INK_FAINT = "#8B968F"
SURFACE = "#FFFFFF"
SURFACE_ALT = "#EFF2F0"

# Class colours (docs/TRAINER_APP_BUILD_PROMPT.md §1) — same hues as the
# phone app's qualityClassColor for the same classes.
CLASS_COLORS: dict[str, str] = {
    "GOOD": "#1B7A4C",
    "DAMAGED": "#B07A12",
    "BROKEN": "#B0401E",
    "SHRIVELED": "#B07A12",
    "IMPURITIES": "#8B968F",
    "UNKNOWN": "#8B968F",
}

CLASS_LABELS: dict[str, str] = {
    "GOOD": "Good",
    "DAMAGED": "Damaged",
    "BROKEN": "Broken",
    "SHRIVELED": "Shriveled",
    "IMPURITIES": "Impurities",
    "UNKNOWN": "Unknown",
}

# Order classes are shown/sorted in across the app. UNKNOWN is a fallback,
# not a deliberate label a human assigns during sorting (§1), so it's last
# and excluded from the sort-mode button row entirely.
CLASS_ORDER = ["GOOD", "DAMAGED", "BROKEN", "SHRIVELED", "IMPURITIES", "UNKNOWN"]
SORTABLE_CLASSES = ["GOOD", "DAMAGED", "BROKEN", "SHRIVELED", "IMPURITIES"]

# Keyboard shortcuts for the sort loop, 1-5 in the same order as the buttons.
SORT_SHORTCUTS: dict[str, str] = {
    "1": "GOOD",
    "2": "DAMAGED",
    "3": "BROKEN",
    "4": "SHRIVELED",
    "5": "IMPURITIES",
}

FONT_FAMILY = "Inter"

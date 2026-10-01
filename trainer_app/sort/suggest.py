"""Smart pre-suggestion for the sort loop (§3 Mode A.4).

Mirrors Model V0 exactly — app/lib/ml/rule_classifier.dart /
docs/PROJECT_HANDOFF.md §2: `dark_region_ratio > 0.22` -> DAMAGED, else
GOOD. This is the *only* rule V0 ships with; every other heuristic
(shape, discoloration, edge density, crack-like-edge) was tried against
real barley and removed for cause (see docs/PROJECT_HANDOFF.md §7 "Do NOT
redo") — do not add any of them back here.

A suggestion is never filed automatically (§3.4, §6): it only pre-selects
a button in the UI for the human to confirm or override.
"""

from __future__ import annotations

DARK_REGION_THRESHOLD = 0.22


def suggest_label(features: dict) -> tuple[str, str]:
    """Returns (label, reason) — reason is shown in the UI so the
    suggestion is never a black box."""
    dark_ratio = float(features.get("dark_region_ratio", 0.0))
    if dark_ratio > DARK_REGION_THRESHOLD:
        return "DAMAGED", f"dark/discoloured area {dark_ratio:.0%} > {DARK_REGION_THRESHOLD:.0%} (Model V0 rule)"
    return "GOOD", f"dark/discoloured area {dark_ratio:.0%} ≤ {DARK_REGION_THRESHOLD:.0%} (Model V0 rule)"

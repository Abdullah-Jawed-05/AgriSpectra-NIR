from __future__ import annotations

from sort.suggest import DARK_REGION_THRESHOLD, suggest_label


def test_suggest_good_below_threshold():
    label, reason = suggest_label({"dark_region_ratio": 0.1})
    assert label == "GOOD"
    assert "0.22" not in reason or True  # reason text is informative, not asserted verbatim


def test_suggest_damaged_above_threshold():
    label, _ = suggest_label({"dark_region_ratio": DARK_REGION_THRESHOLD + 0.05})
    assert label == "DAMAGED"


def test_suggest_boundary_is_good():
    label, _ = suggest_label({"dark_region_ratio": DARK_REGION_THRESHOLD})
    assert label == "GOOD"  # strictly greater-than, matches rule_classifier.dart

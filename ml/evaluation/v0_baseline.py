#!/usr/bin/env python3
"""Model V0 rule-engine baseline — evaluation-only, so the Trainer's
results dashboard can show "did V1 beat V0" on the same held-out test
set (§3 Mode B.3 of docs/TRAINER_APP_BUILD_PROMPT.md). Never used in
training or inference — it never touches model.joblib or m2cgen.

The rule (dark_region_ratio > 0.22 -> DAMAGED, else GOOD) is implemented
independently in three places; keep all three in sync if the cutoff
ever changes:
  - app/lib/ml/rule_classifier.dart   (the real, shipped V0)
  - trainer_app/sort/suggest.py       (the Sort Mode pre-suggestion)
  - this file                         (evaluation-only baseline)
"""

from __future__ import annotations

import pandas as pd
from sklearn.metrics import balanced_accuracy_score, classification_report, f1_score

DARK_REGION_THRESHOLD = 0.22

#: V0 only ever returns one of these two labels — it has no concept of
#: BROKEN, SHRIVELED or IMPURITIES. Comparing it to a model trained
#: across all classes is only fair on this subset; report the gap
#: honestly rather than silently let it inflate or deflate V0's score.
V0_LABELS = ("GOOD", "DAMAGED")


def predict_v0(dark_region_ratio: float) -> str:
    return "DAMAGED" if dark_region_ratio > DARK_REGION_THRESHOLD else "GOOD"


def evaluate_v0_baseline(test_df: pd.DataFrame, label_classes: list[str]) -> dict:
    """Runs the V0 rule against `test_df` and reports the same macro-F1 /
    balanced-accuracy metrics `evaluate_model.py` reports for V1, over the
    same full `label_classes` set, so the two numbers are directly
    comparable — even though V0 structurally can't predict everything in
    that set (see [V0_LABELS])."""
    if "dark_region_ratio" not in test_df.columns:
        raise ValueError("test set has no dark_region_ratio column — can't run the V0 baseline.")

    y_true = test_df["label"].tolist()
    y_pred = [predict_v0(r) for r in test_df["dark_region_ratio"]]

    report = classification_report(y_true, y_pred, labels=label_classes, output_dict=True, zero_division=0)
    out_of_scope = sorted(set(label_classes) - set(V0_LABELS))

    scope_note = "V0 only ever predicts GOOD or DAMAGED."
    if out_of_scope:
        scope_note += (
            f" These classes are entirely out of its scope and it always scores 0 on "
            f"them: {', '.join(out_of_scope)}."
        )
    scope_note += " A low V0 macro-F1 here may reflect that scope gap, not V0 being a weak damage detector specifically."

    return {
        "macro_f1": f1_score(y_true, y_pred, labels=label_classes, average="macro", zero_division=0),
        "balanced_accuracy": balanced_accuracy_score(y_true, y_pred),
        "per_class": report,
        "predicts_only": list(V0_LABELS),
        "out_of_scope_classes": out_of_scope,
        "scope_note": scope_note,
    }

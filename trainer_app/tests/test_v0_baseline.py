from __future__ import annotations

import pandas as pd

from pipeline.scripts import import_v0_baseline


def test_predict_v0_matches_the_shipped_dart_rule(config):
    v0 = import_v0_baseline(config)
    assert v0.evaluate_v0_baseline is not None

    from evaluation.v0_baseline import predict_v0

    assert predict_v0(0.45) == "DAMAGED"  # above the 0.22 cutoff
    assert predict_v0(0.12) == "GOOD"  # below it (natural furrow shadow territory)
    assert predict_v0(0.22) == "GOOD"  # the cutoff itself is exclusive (`>`, not `>=`)


def test_evaluate_v0_baseline_scores_only_what_it_can_predict(config):
    from evaluation.v0_baseline import evaluate_v0_baseline

    test_df = pd.DataFrame(
        {
            "label": ["GOOD", "GOOD", "DAMAGED", "DAMAGED", "BROKEN", "BROKEN"],
            "dark_region_ratio": [0.05, 0.10, 0.50, 0.60, 0.05, 0.05],
        }
    )
    label_classes = ["GOOD", "DAMAGED", "BROKEN"]

    result = evaluate_v0_baseline(test_df, label_classes)

    assert result["predicts_only"] == ["GOOD", "DAMAGED"]
    assert result["out_of_scope_classes"] == ["BROKEN"]
    assert "BROKEN" in result["scope_note"]
    # Perfect on the 4 rows it can actually distinguish; BROKEN rows are
    # always misclassified as GOOD (low dark_region_ratio), so macro-F1 is
    # structurally capped below 1.0 -- the point of the scope_note.
    assert 0.0 < result["macro_f1"] < 1.0
    assert result["per_class"]["BROKEN"]["recall"] == 0.0


def test_evaluate_v0_baseline_requires_dark_region_ratio_column(config):
    from evaluation.v0_baseline import evaluate_v0_baseline

    bad_df = pd.DataFrame({"label": ["GOOD"]})
    try:
        evaluate_v0_baseline(bad_df, ["GOOD", "DAMAGED"])
        assert False, "expected ValueError"
    except ValueError as exc:
        assert "dark_region_ratio" in str(exc)

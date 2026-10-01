from __future__ import annotations

import pytest

from pipeline.runner import PipelineRunner

pytestmark = pytest.mark.slow  # spawns 4 real subprocesses against ml/


def test_full_pipeline_run_against_real_scripts(config, db, two_batch_raw_dataset):
    run_id = db.create_run(str(config.work_root))
    runner = PipelineRunner(config, db, run_id)

    lines: list[str] = []
    stages: list[str] = []

    result = runner.run(
        "barley",
        on_line=lambda stage, line: lines.append((stage, line)),
        on_stage_change=lambda stage: stages.append(stage),
    )

    assert stages == ["prepare", "split", "train", "evaluate"]
    assert lines  # real stdout was captured

    split_summary = result["split_summary"]
    assert split_summary["test_leakage_safe"] is True  # 2 batches -> held-out batch test

    evaluation_report = result["evaluation_report"]
    assert "macro_f1" in evaluation_report
    assert len(result["confusion_matrix"]) == len(evaluation_report["label_classes"])

    row = db.get_run(run_id)
    assert row["current_stage"] == "evaluate"

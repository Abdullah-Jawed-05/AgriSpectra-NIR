"""Subprocess orchestration for the four training stages — §3 Mode B.2,
§5 "Calling the pipeline": every stage is a plain `subprocess.Popen`
call to the real, unmodified ml/ script, stdout/stderr streamed
line-by-line to a callback. This is deliberate (§5/§6): it guarantees
zero behavioural drift from the already-correct pipeline.
"""

from __future__ import annotations

import json
import subprocess
import threading
import time
from dataclasses import dataclass
from pathlib import Path
from typing import Callable, Optional

import pandas as pd

from core.config import AppConfig
from pipeline.scripts import import_v0_baseline

OnLine = Callable[[str, str], None]  # (stage_name, line)
OnProgress = Callable[[str, float], None]  # (stage_name, 0..1)


class StageFailed(RuntimeError):
    def __init__(self, stage: str, returncode: int, tail: str):
        super().__init__(f"{stage} failed (exit {returncode}):\n{tail}")
        self.stage = stage
        self.returncode = returncode
        self.tail = tail


@dataclass
class StageResult:
    name: str
    returncode: int
    log: str
    duration_s: float


def _run_subprocess(
    argv: list[str],
    cwd: Optional[Path],
    stage_name: str,
    on_line: Optional[OnLine],
) -> StageResult:
    start = time.monotonic()
    proc = subprocess.Popen(
        argv,
        cwd=str(cwd) if cwd else None,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        bufsize=1,
        universal_newlines=True,
    )
    lines: list[str] = []
    assert proc.stdout is not None
    for raw_line in proc.stdout:
        line = raw_line.rstrip("\n")
        lines.append(line)
        if on_line:
            on_line(stage_name, line)
    proc.wait()
    duration = time.monotonic() - start
    return StageResult(stage_name, proc.returncode, "\n".join(lines), duration)


def _count_images(raw_dir: Path) -> int:
    exts = {".jpg", ".jpeg", ".png"}
    return sum(1 for p in raw_dir.rglob("*") if p.suffix.lower() in exts)


def _watch_output_dir(stop: threading.Event, out_dir: Path, subfolder: str, total: int, stage_name: str, on_progress: Optional[OnProgress]) -> None:
    """Polls a growing output folder (e.g. Stage 1's crops/) to drive a
    best-effort progress bar while the real script runs — the script
    itself doesn't print a parseable per-image counter, so this is an
    estimate, never exact, and always finishes at 1.0 when the stage
    actually completes (set by the caller after the subprocess exits)."""
    if not on_progress or total <= 0:
        return
    target = out_dir / subfolder
    while not stop.wait(0.3):
        try:
            n = sum(1 for _ in target.iterdir()) if target.is_dir() else 0
        except OSError:
            n = 0
        on_progress(stage_name, min(0.95, n / total))


class PipelineRunner:
    """Runs Prepare -> Split -> Train -> Evaluate against one run's
    work directory, writing to the SQLite run row as it goes."""

    def __init__(self, config: AppConfig, db, run_id: str):
        self.config = config
        self.db = db
        self.run_id = run_id

    def _argv(self, *parts: str) -> list[str]:
        return [self.config.python_exe, *parts]

    def _log(self, stage: str, line: str) -> None:
        self.db.append_log(self.run_id, f"[{stage}] {line}\n")

    def run(
        self,
        crop: str,
        test_fraction: float = 0.2,
        val_fraction: float = 0.15,
        split_seed: int = 42,
        test_batch: Optional[str] = None,
        model_kind: Optional[str] = None,
        on_line: Optional[OnLine] = None,
        on_progress: Optional[OnProgress] = None,
        on_stage_change: Optional[Callable[[str], None]] = None,
    ) -> dict:
        def line_cb(stage: str, line: str) -> None:
            self._log(stage, line)
            if on_line:
                on_line(stage, line)

        work_dir = Path(self.config.work_root) / "runs" / self.run_id
        dataset_dir = work_dir / "dataset"
        split_dir = work_dir / "split"
        model_dir = work_dir / "model"
        eval_dir = work_dir / "eval"
        for d in (dataset_dir, split_dir, model_dir, eval_dir):
            d.mkdir(parents=True, exist_ok=True)

        raw_crop_dir = Path(self.config.raw_data_root) / crop
        pipeline_dir = Path(self.config.pipeline_dir)

        # --- Stage 1: prepare_dataset.py --------------------------------
        self._stage(on_stage_change, "prepare")
        total_images = _count_images(raw_crop_dir)
        stop = threading.Event()
        watcher = threading.Thread(
            target=_watch_output_dir,
            args=(stop, dataset_dir, "crops", total_images, "prepare", on_progress),
            daemon=True,
        )
        watcher.start()
        try:
            result = _run_subprocess(
                self._argv(
                    str(self.config.scripts_dir() / "prepare_dataset.py"),
                    "--raw-dir", str(Path(self.config.raw_data_root)),
                    "--out", str(dataset_dir),
                ),
                pipeline_dir,
                "prepare",
                line_cb,
            )
        finally:
            stop.set()
            watcher.join(timeout=2)
        if on_progress:
            on_progress("prepare", 1.0)
        if result.returncode != 0:
            raise StageFailed("prepare", result.returncode, result.log[-2000:])

        features_csv = dataset_dir / "features.csv"
        if not features_csv.is_file():
            raise StageFailed("prepare", 0, "features.csv was not produced — see log above.")

        # --- Stage 2: split_dataset.py -----------------------------------
        self._stage(on_stage_change, "split")
        argv = self._argv(
            str(self.config.scripts_dir() / "split_dataset.py"),
            "--features", str(features_csv),
            "--out", str(split_dir),
            "--test-fraction", str(test_fraction),
            "--val-fraction", str(val_fraction),
            "--seed", str(split_seed),
        )
        if test_batch:
            argv += ["--test-batch", test_batch]
        result = _run_subprocess(argv, pipeline_dir, "split", line_cb)
        if on_progress:
            on_progress("split", 1.0)
        if result.returncode != 0:
            raise StageFailed("split", result.returncode, result.log[-2000:])

        split_summary = json.loads((split_dir / "split_summary.json").read_text())

        # --- Stage 3: train_baseline.py -----------------------------------
        self._stage(on_stage_change, "train")
        argv = self._argv(
            str(self.config.training_dir() / "train_baseline.py"),
            "--train", str(split_dir / "train.csv"),
            "--val", str(split_dir / "val.csv"),
            "--out", str(model_dir),
        )
        if model_kind:
            argv += ["--model", model_kind]
        result = _run_subprocess(argv, pipeline_dir, "train", line_cb)
        if on_progress:
            on_progress("train", 1.0)
        if result.returncode != 0:
            raise StageFailed("train", result.returncode, result.log[-2000:])

        training_metadata = json.loads((model_dir / "training_metadata.json").read_text())

        # --- Stage 4: evaluate_model.py -----------------------------------
        self._stage(on_stage_change, "evaluate")
        result = _run_subprocess(
            self._argv(
                str(self.config.evaluation_dir() / "evaluate_model.py"),
                "--model", str(model_dir),
                "--test", str(split_dir / "test.csv"),
                "--out", str(eval_dir),
            ),
            pipeline_dir,
            "evaluate",
            line_cb,
        )
        if on_progress:
            on_progress("evaluate", 1.0)
        if result.returncode != 0:
            raise StageFailed("evaluate", result.returncode, result.log[-2000:])

        evaluation_report = json.loads((eval_dir / "evaluation_report.json").read_text())
        confusion_matrix = _read_confusion_matrix(eval_dir / "confusion_matrix.csv")

        # --- V0 baseline comparison (in-process, no subprocess) -----------
        # Not a pipeline "stage" in its own right (no separate stepper
        # entry) -- just a same-test-set comparison so "did V1 beat V0"
        # is a number on the results dashboard instead of manual analysis
        # against docs/VALIDATION.md. Never fails the run: a problem here
        # only means the comparison is unavailable, not that training failed.
        v0_baseline = None
        try:
            v0 = import_v0_baseline(self.config)
            test_df = pd.read_csv(split_dir / "test.csv")
            v0_baseline = v0.evaluate_v0_baseline(test_df, evaluation_report["label_classes"])
            line_cb("evaluate", f"V0 baseline on the same test set: macro-F1 {v0_baseline['macro_f1']:.3f}")
        except Exception as exc:  # noqa: BLE001
            line_cb("evaluate", f"V0 baseline comparison skipped: {exc}")

        return {
            "work_dir": str(work_dir),
            "model_dir": str(model_dir),
            "eval_dir": str(eval_dir),
            "split_summary": split_summary,
            "training_metadata": training_metadata,
            "evaluation_report": evaluation_report,
            "confusion_matrix": confusion_matrix,
            "v0_baseline": v0_baseline,
        }

    def _stage(self, on_stage_change: Optional[Callable[[str], None]], name: str) -> None:
        self.db.set_stage(self.run_id, name)
        if on_stage_change:
            on_stage_change(name)


def _read_confusion_matrix(path: Path) -> list[list[int]]:
    rows = []
    for line in path.read_text().splitlines():
        line = line.strip()
        if not line:
            continue
        rows.append([int(v) for v in line.split(",")])
    return rows

"""Train Mode — §3 Mode B. Pre-flight -> live pipeline stepper -> results
dashboard -> (optional) Promote to App."""

from __future__ import annotations

import json
from pathlib import Path

import flet as ft

from core import theme
from core.crops import can_promote_to_phone_app, crop_label
from pipeline.preflight import scan_raw_data
from pipeline.runner import PipelineRunner, StageFailed
from promote.activate import PredictorFileError, build_apk, enable_model_v1, install_apk, list_connected_devices
from promote.export import copy_promoted_to, promote_model
from ui.components import card, class_counts_row, confusion_matrix_grid, leakage_badge, pipeline_stepper, section_title, stat_tile, test_overlap_text, trained_on_text

STAGES = ["prepare", "split", "train", "evaluate"]
MAX_LOG_LINES = 400


class TrainScreen:
    def __init__(self, ctx):
        self.ctx = ctx
        self.running = False
        self.current_run_id: str | None = None
        self.log_lines: list[str] = []
        self.failed_stage: str | None = None

        self.root_column = ft.Column(spacing=20, scroll=ft.ScrollMode.AUTO, expand=True)
        self.preflight_panel = ft.Container()
        self.run_panel = ft.Container(visible=False)
        self.stepper_row = ft.Row()
        self.log_view = ft.Column(spacing=1, scroll=ft.ScrollMode.AUTO, height=220)
        self.log_expansion = ft.ExpansionTile(title=ft.Text("Live log"), controls=[ft.Container(content=self.log_view, bgcolor="#0B1210", border_radius=8, padding=10)])
        self.results_panel = ft.Container(visible=False)
        self.start_button = ft.FilledButton(
            "Start training run",
            icon=ft.Icons.PLAY_ARROW_ROUNDED,
            # A plain bgcolor would also paint the disabled state, making a
            # dead button look clickable.
            style=ft.ButtonStyle(
                bgcolor={ft.ControlState.DISABLED: theme.SURFACE_ALT, ft.ControlState.DEFAULT: theme.ACCENT},
                color={ft.ControlState.DISABLED: theme.INK_FAINT, ft.ControlState.DEFAULT: "#FFFFFF"},
            ),
        )
        self.test_batch_dropdown = ft.Dropdown(label="Force test batch (optional)", options=[], width=280)
        self.test_fraction_field = ft.TextField(label="Test fraction", value="0.2", width=140, dense=True)
        self.val_fraction_field = ft.TextField(label="Val fraction", value="0.15", width=140, dense=True)
        self.one_seed_cb = ft.Checkbox(
            label="One seed per photo",
            value=True,
            tooltip="Keep only the best seed in each photo. Right for Sort Mode crops, phone exports "
            "and single-seed photos; turn off only for pre-sorted photos with several seeds each.",
        )
        self.version_label_field = ft.TextField(label="Version label", hint_text="e.g. v1_2026-10-01", width=260, dense=True)
        self.promote_status = ft.Column(spacing=8)
        self.copy_status = ft.Column(spacing=6)
        self.activate_status = ft.Column(spacing=8)
        self.build_log_lines: list[str] = []
        self.build_log_view = ft.Column(spacing=1, scroll=ft.ScrollMode.AUTO, height=180)

    def on_show(self) -> None:
        self._rebuild_preflight()

    def build(self) -> ft.Control:
        self.root_column.controls = [
            ft.Text(f"Train · {crop_label(self.ctx.crop)}", size=24, weight=ft.FontWeight.BOLD, color=theme.INK),
            self.preflight_panel,
            self.run_panel,
            self.results_panel,
        ]
        self._rebuild_preflight()
        return self.root_column

    # ---- pre-flight -----------------------------------------------------

    def _scan(self):
        return scan_raw_data(
            Path(self.ctx.config.raw_data_root),
            self.ctx.crop,
            self.ctx.config.excluded_batches_for(self.ctx.crop),
        )

    def _set_batches_included(self, batch_ids: list[str], included: bool) -> None:
        if self.running:
            return
        for batch_id in batch_ids:
            self.ctx.config.set_batch_included(self.ctx.crop, batch_id, included)
        try:
            self.ctx.config.save()
        except OSError as exc:
            self.ctx.notify(f"Couldn't save the batch selection: {exc}", error=True)
        self._rebuild_preflight()

    def _batch_picker(self, summary) -> ft.Control:
        if not summary.batches:
            return ft.Container()
        all_ids = [b.batch_id for b in summary.batches]

        def row(info) -> ft.Control:
            breakdown = " · ".join(f"{label.title()} {n}" for label, n in sorted(info.class_counts.items()))
            return ft.Row(
                spacing=4,
                vertical_alignment=ft.CrossAxisAlignment.CENTER,
                controls=[
                    ft.Checkbox(
                        value=info.included,
                        disabled=self.running,
                        on_change=lambda e, b=info.batch_id: self._set_batches_included([b], bool(e.control.value)),
                    ),
                    ft.Column(
                        spacing=0,
                        expand=True,
                        controls=[
                            ft.Text(info.batch_id, size=13, weight=ft.FontWeight.W_600,
                                    color=theme.INK if info.included else theme.INK_FAINT),
                            ft.Text(f"{info.n_images} photos  ·  {breakdown}", size=11, color=theme.INK_MUTED),
                        ],
                    ),
                ],
            )

        n_on = len(summary.batch_ids)
        return ft.Column(
            spacing=4,
            controls=[
                ft.Row(
                    alignment=ft.MainAxisAlignment.SPACE_BETWEEN,
                    controls=[
                        ft.Text(f"Batches to train on ({n_on} of {len(all_ids)})", size=14,
                                weight=ft.FontWeight.W_600, color=theme.INK),
                        ft.Row(
                            spacing=0,
                            controls=[
                                ft.TextButton("All", disabled=self.running,
                                              on_click=lambda e: self._set_batches_included(all_ids, True)),
                                ft.TextButton("None", disabled=self.running,
                                              on_click=lambda e: self._set_batches_included(all_ids, False)),
                            ],
                        ),
                    ],
                ),
                *[row(b) for b in summary.batches],
            ],
        )

    def _rebuild_preflight(self) -> None:
        summary = self._scan()
        self.test_batch_dropdown.options = [ft.DropdownOption(key=b, text=b) for b in summary.batch_ids]
        if self.test_batch_dropdown.value not in summary.batch_ids:
            self.test_batch_dropdown.value = None

        warnings = ft.Column(
            spacing=6,
            controls=[
                ft.Row(
                    spacing=8,
                    controls=[ft.Icon(ft.Icons.WARNING_AMBER_ROUNDED, size=16, color=theme.CLASS_COLORS["DAMAGED"]), ft.Text(w, size=12, color=theme.INK, expand=True)],
                )
                for w in summary.warnings
            ],
        )

        minutes = summary.estimated_seconds / 60
        self.start_button.disabled = not summary.is_ready or self.running
        self.start_button.on_click = self._on_start

        self.preflight_panel.content = card(
            ft.Column(
                spacing=14,
                controls=[
                    section_title("Pre-flight"),
                    self._batch_picker(summary),
                    class_counts_row(summary.class_counts)
                    if summary.class_counts
                    else ft.Text("No labelled data yet." if not summary.batches else "", color=theme.INK_FAINT),
                    ft.Row(
                        spacing=12,
                        controls=[
                            stat_tile("Selected batches", str(summary.n_batches)),
                            stat_tile("Total labelled seeds", str(sum(summary.class_counts.values()))),
                            stat_tile("Est. run time", f"~{minutes:.1f} min"),
                        ],
                    ),
                    warnings if summary.warnings else ft.Container(),
                    ft.ExpansionTile(
                        title=ft.Text("Advanced options", size=13),
                        controls=[
                            ft.Row(
                                wrap=True,
                                spacing=12,
                                controls=[self.test_fraction_field, self.val_fraction_field, self.test_batch_dropdown, self.one_seed_cb],
                            )
                        ],
                    ),
                    self.start_button,
                ],
            )
        )
        self._safe_update()

    # ---- run -----------------------------------------------------------

    def _on_start(self, e) -> None:
        if self.running:
            return
        # Re-scan rather than trust what's on screen: folders may have
        # changed since the panel was drawn.
        summary = self._scan()
        if not summary.is_ready:
            self._rebuild_preflight()
            return
        batches = list(summary.batch_ids)
        self.running = True
        self._rebuild_preflight()  # lock the batch checkboxes for the run
        self.failed_stage = None
        self.log_lines = []
        self.log_view.controls = []
        self.results_panel.visible = False
        self.run_panel.visible = True
        self.stepper_row = pipeline_stepper(STAGES, None, None)
        self._rebuild_run_panel()

        try:
            test_fraction = float(self.test_fraction_field.value or 0.2)
            val_fraction = float(self.val_fraction_field.value or 0.15)
        except ValueError:
            test_fraction, val_fraction = 0.2, 0.15

        test_batch = self.test_batch_dropdown.value or None
        self.ctx.page.run_thread(self._do_run, test_fraction, val_fraction, test_batch, batches)

    def _rebuild_run_panel(self) -> None:
        self.run_panel.content = card(
            ft.Column(
                spacing=14,
                controls=[
                    section_title("Training run in progress" if self.running else ("Run failed" if self.failed_stage else "Last run")),
                    self.stepper_row,
                    self.log_expansion,
                ],
            )
        )
        self._safe_update()

    def _append_log(self, stage: str, line: str) -> None:
        self.log_lines.append(f"[{stage}] {line}")
        self.log_lines = self.log_lines[-MAX_LOG_LINES:]
        self.log_view.controls = [ft.Text(ln, size=10, color="#D7E8E2", font_family="Consolas, monospace") for ln in self.log_lines[-200:]]
        self._safe_update()

    def stepper_row_controls_update(self, current_stage, failed_stage) -> None:
        new_row = pipeline_stepper(STAGES, current_stage, failed_stage)
        self.stepper_row.controls = new_row.controls
        self._safe_update()

    def _do_run(self, test_fraction: float, val_fraction: float, test_batch: str | None, batches: list[str]) -> None:
        try:
            self._run_pipeline(test_fraction, val_fraction, test_batch, batches)
        finally:
            self.running = False
            self._rebuild_preflight()  # unlock the batch checkboxes / Start button

    def _run_pipeline(self, test_fraction: float, val_fraction: float, test_batch: str | None, batches: list[str]) -> None:
        row_id = self.ctx.db.create_run("", crop=self.ctx.crop, batches=batches)
        self.current_run_id = row_id
        self.ctx.db.set_work_dir(row_id, str(Path(self.ctx.config.work_root) / "runs" / row_id))

        runner = PipelineRunner(self.ctx.config, self.ctx.db, row_id)
        try:
            result = runner.run(
                self.ctx.crop,
                test_fraction=test_fraction,
                val_fraction=val_fraction,
                test_batch=test_batch,
                one_seed=bool(self.one_seed_cb.value),
                batches=batches,
                on_line=self._append_log,
                on_progress=lambda stage, frac: None,
                on_stage_change=lambda stage: self.stepper_row_controls_update(stage, None),
            )
        except StageFailed as exc:
            self.running = False
            self.failed_stage = exc.stage
            self.ctx.db.fail_run(row_id, str(exc))
            self.stepper_row_controls_update(exc.stage, exc.stage)
            self._rebuild_run_panel()
            self.ctx.notify(f"Training run failed at {exc.stage}: {exc.tail[:200]}", error=True)
            return
        except Exception as exc:  # noqa: BLE001
            self.running = False
            self.failed_stage = "prepare"
            self.ctx.db.fail_run(row_id, str(exc))
            self._rebuild_run_panel()
            self.ctx.notify(f"Training run failed: {exc}", error=True)
            return

        self.running = False
        split_summary = result["split_summary"]
        evaluation_report = result["evaluation_report"]

        self.ctx.db.finish_run(
            row_id,
            model_dir=result["model_dir"],
            eval_dir=result["eval_dir"],
            n_train_rows=split_summary["train"]["rows"],
            n_val_rows=split_summary["val"]["rows"],
            n_test_rows=split_summary["test"]["rows"],
            n_batches=len(set(split_summary["train"]["batches"]) | set(split_summary["val"]["batches"]) | set(split_summary["test"]["batches"])),
            test_leakage_safe=int(split_summary["test_leakage_safe"]),
            val_leakage_safe=int(split_summary["val_leakage_safe"]),
            test_rows_seen_in_training=split_summary.get("test_rows_seen_in_training"),
            macro_f1=evaluation_report["macro_f1"],
            balanced_accuracy=evaluation_report["balanced_accuracy"],
            roc_auc=evaluation_report.get("roc_auc_ovr_macro"),
            confusion_matrix_json=json.dumps(result["confusion_matrix"]),
            per_class_json=json.dumps(evaluation_report["per_class"]),
            label_classes_json=json.dumps(evaluation_report["label_classes"]),
            v0_baseline_json=json.dumps(result.get("v0_baseline")),
        )
        self.stepper_row_controls_update("evaluate", None)
        self._show_results(row_id)

    # ---- results ---------------------------------------------------------

    def _show_results(self, run_id: str) -> None:
        run = self.ctx.db.get_run(run_id)
        best = self.ctx.db.best_run_before(run_id, metric="macro_f1")

        macro_f1 = run["macro_f1"] or 0.0
        balanced_acc = run["balanced_accuracy"] or 0.0
        confusion = json.loads(run["confusion_matrix_json"] or "[]")
        label_classes = json.loads(run["label_classes_json"] or "[]")

        delta_control = ft.Container()
        if best is not None and best["macro_f1"] is not None:
            delta = macro_f1 - best["macro_f1"]
            arrow = "↑" if delta >= 0 else "↓"
            color = theme.CLASS_COLORS["GOOD"] if delta >= 0 else theme.CLASS_COLORS["BROKEN"]
            delta_control = ft.Text(f"{arrow} {abs(delta):.1%} vs previous best (macro-F1 {best['macro_f1']:.1%})", size=13, weight=ft.FontWeight.W_600, color=color)
        else:
            delta_control = ft.Text("First completed run — no previous best to compare yet.", size=12, color=theme.INK_FAINT)

        v0_baseline = json.loads(run["v0_baseline_json"] or "null")
        if v0_baseline is not None:
            beats_v0 = macro_f1 > v0_baseline["macro_f1"]
            arrow = "↑" if beats_v0 else "↓"
            color = theme.CLASS_COLORS["GOOD"] if beats_v0 else theme.CLASS_COLORS["BROKEN"]
            v0_control = ft.Column(
                spacing=4,
                controls=[
                    ft.Text(
                        f"{arrow} V1 macro-F1 {macro_f1:.1%} vs V0 rule-engine baseline "
                        f"{v0_baseline['macro_f1']:.1%} on this same held-out test set",
                        size=13,
                        weight=ft.FontWeight.W_600,
                        color=color,
                    ),
                    ft.Text(v0_baseline["scope_note"], size=11, color=theme.INK_FAINT),
                ],
            )
        else:
            v0_control = ft.Text("V0 baseline comparison unavailable for this run.", size=12, color=theme.INK_FAINT)

        self.version_label_field.value = f"run_{run_id}"
        self.promote_status.controls = []
        self.copy_status.controls = []
        self.activate_status.controls = []
        self.build_log_lines = []
        self.build_log_view.controls = []

        def do_promote(e) -> None:
            self.ctx.page.run_thread(self._do_promote, run_id)

        self.results_panel.content = card(
            ft.Column(
                spacing=16,
                controls=[
                    ft.Row(
                        alignment=ft.MainAxisAlignment.SPACE_BETWEEN,
                        controls=[section_title("Results"), leakage_badge(bool(run["test_leakage_safe"]))],
                    ),
                    ft.Row(
                        spacing=12,
                        wrap=True,
                        controls=[
                            stat_tile("Macro-F1", f"{macro_f1:.1%}"),
                            stat_tile("Balanced accuracy", f"{balanced_acc:.1%}"),
                            stat_tile("Test rows", str(run["n_test_rows"])),
                            stat_tile("Batches", str(run["n_batches"])),
                        ],
                    ),
                    ft.Text(trained_on_text(run), size=12, color=theme.INK_MUTED),
                    *(
                        [ft.Text(overlap, size=12, weight=ft.FontWeight.W_600, color=theme.CLASS_COLORS["BROKEN"])]
                        if (overlap := test_overlap_text(run))
                        else []
                    ),
                    delta_control,
                    v0_control,
                    section_title("Confusion matrix"),
                    confusion_matrix_grid(confusion, label_classes),
                    ft.Divider(),
                    section_title("Promote to App"),
                    *self._promote_controls(run, do_promote),
                ],
            )
        )
        self.results_panel.visible = True
        self._safe_update()

    def _promote_controls(self, run, do_promote) -> list[ft.Control]:
        if not can_promote_to_phone_app(run["crop"]):
            return [
                ft.Text(
                    f"The phone app only supports Barley so far, so this {crop_label(run['crop']).lower()} "
                    "model can be trained and evaluated here but not promoted into it.",
                    size=12,
                    color=theme.INK_MUTED,
                )
            ]
        return [
            ft.Text(
                "Exports this model as dependency-free Dart you can drop into the Flutter app. "
                "Never wired in automatically.",
                size=12,
                color=theme.INK_FAINT,
            ),
            ft.Row(
                spacing=10,
                controls=[
                    self.version_label_field,
                    ft.FilledButton(
                        "Promote to App",
                        icon=ft.Icons.UPLOAD_OUTLINED,
                        on_click=do_promote,
                        style=ft.ButtonStyle(bgcolor=theme.ACCENT, color="#FFFFFF"),
                    ),
                ],
            ),
            self.promote_status,
        ]

    def _do_promote(self, run_id: str) -> None:
        run = self.ctx.db.get_run(run_id)
        if not can_promote_to_phone_app(run["crop"]):
            self.ctx.notify(f"Only Barley models can go into the phone app (this run is {crop_label(run['crop'])}).", error=True)
            return
        try:
            result = promote_model(
                self.ctx.config,
                Path(run["model_dir"]),
                Path(self.ctx.config.export_root),
                run_id,
                self.version_label_field.value or None,
            )
        except Exception as exc:  # noqa: BLE001
            self.ctx.notify(f"Promote failed: {exc}", error=True)
            return

        self.ctx.db.mark_promoted(run_id)

        feature_text = "\n".join(f"{i}: {c}" for i, c in enumerate(result.feature_columns))
        label_text = "\n".join(f"{i}: {c}" for i, c in enumerate(result.label_classes))

        def do_copy(e) -> None:
            self._do_copy_to_app(result.export_dir, run_id)

        self.promote_status.controls = [
            ft.Text(f"Exported ({result.method}) to {result.export_dir}", size=12, color=theme.CLASS_COLORS["GOOD"]),
            ft.Text("Feature order (copy exactly into FeatureExtractor wiring):", size=12, weight=ft.FontWeight.W_600),
            ft.Container(bgcolor=theme.SURFACE_ALT, border_radius=8, padding=10, content=ft.Text(feature_text, size=11, selectable=True, font_family="Consolas, monospace")),
            ft.Text("Label order:", size=12, weight=ft.FontWeight.W_600),
            ft.Container(bgcolor=theme.SURFACE_ALT, border_radius=8, padding=10, content=ft.Text(label_text, size=11, selectable=True, font_family="Consolas, monospace")),
            ft.Divider(),
            ft.Text(
                f"Copy destination: {self.ctx.config.app_lib_ml_dir or '(not set — see Settings)'}",
                size=11,
                color=theme.INK_FAINT,
            ),
            ft.OutlinedButton(
                "Copy to app",
                icon=ft.Icons.DRIVE_FILE_MOVE_OUTLINED,
                on_click=do_copy,
                disabled=not self.ctx.config.is_app_lib_ml_dir_configured(),
            ),
            self.copy_status,
        ]
        self._safe_update()

    def _do_copy_to_app(self, export_dir: Path, run_id: str) -> None:
        try:
            copied = copy_promoted_to(export_dir, Path(self.ctx.config.app_lib_ml_dir))
        except Exception as exc:  # noqa: BLE001
            self.copy_status.controls = [ft.Text(f"Copy failed: {exc}", size=12, color=theme.CLASS_COLORS["BROKEN"])]
            self._safe_update()
            return

        names = "\n".join(f"  {p.name}" for p in copied)

        def open_confirm(e) -> None:
            self._open_activate_confirm(run_id)

        self.copy_status.controls = [
            ft.Text(f"Copied to {self.ctx.config.app_lib_ml_dir}:\n{names}", size=12, color=theme.CLASS_COLORS["GOOD"]),
            ft.Text(
                "This only makes the model available, not active — useModelV1 in "
                "app/lib/ml/model_v1_predictor.dart is still false.",
                size=11,
                color=theme.INK_FAINT,
            ),
            ft.Divider(),
            ft.FilledButton(
                "Enable Model V1 & rebuild APK",
                icon=ft.Icons.ROCKET_LAUNCH_OUTLINED,
                on_click=open_confirm,
                style=ft.ButtonStyle(bgcolor=theme.ACCENT, color="#FFFFFF"),
            ),
            self.activate_status,
        ]
        self._safe_update()

    # ---- enable Model V1 & rebuild APK -----------------------------------

    def _open_activate_confirm(self, run_id: str) -> None:
        run = self.ctx.db.get_run(run_id)
        macro_f1 = run["macro_f1"] or 0.0
        v0_baseline = json.loads(run["v0_baseline_json"] or "null")

        if v0_baseline is None:
            comparison = ft.Text(
                "No V0 baseline comparison is available for this run — proceeding without it.",
                size=12,
                color=theme.CLASS_COLORS["DAMAGED"],
            )
        else:
            beats_v0 = macro_f1 > v0_baseline["macro_f1"]
            comparison = ft.Column(
                spacing=4,
                controls=[
                    ft.Text(
                        f"V1 macro-F1 {macro_f1:.1%} vs V0 {v0_baseline['macro_f1']:.1%}",
                        size=13,
                        weight=ft.FontWeight.W_600,
                        color=theme.CLASS_COLORS["GOOD"] if beats_v0 else theme.CLASS_COLORS["BROKEN"],
                    ),
                    ft.Text(
                        "This run beats the V0 baseline on held-out data."
                        if beats_v0
                        else "This run does NOT beat the V0 baseline — enabling it would make on-device "
                        "predictions worse by this run's own numbers.",
                        size=12,
                        color=theme.INK_FAINT if beats_v0 else theme.CLASS_COLORS["BROKEN"],
                    ),
                ],
            )

        if not run["test_leakage_safe"]:
            comparison = ft.Column(
                spacing=8,
                controls=[
                    comparison,
                    ft.Text(
                        (test_overlap_text(run) or "This run's test split is NOT leakage-safe.")
                        + " Both numbers above come from that test, so they don't show how V1 does on new seeds.",
                        size=12,
                        color=theme.CLASS_COLORS["BROKEN"],
                    ),
                ],
            )

        def do_confirm(e) -> None:
            self.ctx.page.pop_dialog()
            self.ctx.page.run_thread(self._do_enable_and_build, run_id)

        def do_cancel(e) -> None:
            self.ctx.page.pop_dialog()

        dialog = ft.AlertDialog(
            title=ft.Text("Enable Model V1 on-device?"),
            content=ft.Column(
                tight=True,
                spacing=12,
                controls=[
                    comparison,
                    ft.Text(
                        "This flips useModelV1 to true in model_v1_predictor.dart and runs "
                        "flutter build apk. The new APK replaces the current one only once you "
                        "install it.",
                        size=12,
                        color=theme.INK_FAINT,
                    ),
                ],
            ),
            actions=[
                ft.TextButton("Cancel", on_click=do_cancel),
                ft.FilledButton("Enable & build", on_click=do_confirm, style=ft.ButtonStyle(bgcolor=theme.ACCENT, color="#FFFFFF")),
            ],
        )
        self.ctx.page.show_dialog(dialog)

    def _append_build_log(self, stage: str, line: str) -> None:
        self.build_log_lines.append(line)
        self.build_log_lines = self.build_log_lines[-MAX_LOG_LINES:]
        self.build_log_view.controls = [ft.Text(ln, size=10, color="#D7E8E2", font_family="Consolas, monospace") for ln in self.build_log_lines[-200:]]
        self._safe_update()

    def _do_enable_and_build(self, run_id: str) -> None:
        app_lib_ml_dir = Path(self.ctx.config.app_lib_ml_dir)
        try:
            enable_model_v1(app_lib_ml_dir)
        except PredictorFileError as exc:
            self.activate_status.controls = [ft.Text(f"Could not enable Model V1: {exc}", size=12, color=theme.CLASS_COLORS["BROKEN"])]
            self._safe_update()
            return

        if not self.ctx.config.is_flutter_configured():
            self.activate_status.controls = [
                ft.Text("useModelV1 is now true.", size=12, color=theme.CLASS_COLORS["GOOD"]),
                ft.Text(
                    "But the Flutter SDK isn't configured — set it in Settings, then rebuild the "
                    "APK yourself with `flutter build apk` from the app/ directory.",
                    size=12,
                    color=theme.CLASS_COLORS["BROKEN"],
                ),
            ]
            self._safe_update()
            return

        self.build_log_lines = []
        self.build_log_view.controls = []
        self.activate_status.controls = [
            ft.Text("useModelV1 is now true. Running flutter build apk — this can take a few minutes…", size=12, color=theme.CLASS_COLORS["GOOD"]),
            ft.ExpansionTile(title=ft.Text("Build log", size=13), controls=[ft.Container(content=self.build_log_view, bgcolor="#0B1210", border_radius=8, padding=10)]),
        ]
        self._safe_update()

        app_root = self.ctx.config.app_root()
        result = build_apk(self.ctx.config.flutter_exe, app_root, on_line=self._append_build_log)

        if not result.success:
            self.activate_status.controls.append(
                ft.Text(f"Build failed after {result.duration_s:.0f}s: {result.log[-300:]}", size=12, color=theme.CLASS_COLORS["BROKEN"])
            )
            self._safe_update()
            return

        def do_install(e) -> None:
            self.ctx.page.run_thread(self._do_install, app_root)

        devices = list_connected_devices(self.ctx.config.flutter_exe)
        self.activate_status.controls.append(
            ft.Text(f"Built in {result.duration_s:.0f}s: {result.apk_path}", size=12, color=theme.CLASS_COLORS["GOOD"])
        )
        if devices:
            self.activate_status.controls.append(
                ft.Row(
                    spacing=10,
                    controls=[
                        ft.Text(f"Connected: {', '.join(devices)}", size=11, color=theme.INK_FAINT),
                        ft.OutlinedButton("Install to connected device", icon=ft.Icons.INSTALL_MOBILE_OUTLINED, on_click=do_install),
                    ],
                )
            )
        else:
            self.activate_status.controls.append(
                ft.Text("No connected device found — install the APK above manually when ready.", size=11, color=theme.INK_FAINT)
            )
        self._safe_update()

    def _do_install(self, app_root: Path) -> None:
        result = install_apk(self.ctx.config.flutter_exe, app_root, on_line=self._append_build_log)
        ok = result.returncode == 0
        self.activate_status.controls.append(
            ft.Text(
                "Installed." if ok else f"Install failed: {result.log[-300:]}",
                size=12,
                color=theme.CLASS_COLORS["GOOD"] if ok else theme.CLASS_COLORS["BROKEN"],
            )
        )
        self._safe_update()

    def _safe_update(self) -> None:
        try:
            self.root_column.update()
        except (AssertionError, RuntimeError):
            pass

"""History — every training run, browsable (§3 Mode B.4)."""

from __future__ import annotations

import json
from datetime import datetime

import flet as ft

from core import theme
from core.crops import crop_label
from ui.components import card, confusion_matrix_grid, leakage_badge, trained_on_text


class HistoryScreen:
    def __init__(self, ctx):
        self.ctx = ctx
        self.root_column = ft.Column(spacing=16, scroll=ft.ScrollMode.AUTO, expand=True)

    def on_show(self) -> None:
        self._rebuild()

    def build(self) -> ft.Control:
        self._rebuild()
        return self.root_column

    def _rebuild(self) -> None:
        runs = self.ctx.db.list_runs(limit=100)
        if not runs:
            self.root_column.controls = [
                ft.Text("History", size=24, weight=ft.FontWeight.BOLD, color=theme.INK),
                card(ft.Text("No training runs yet. Head to Train to run the pipeline.", color=theme.INK_FAINT)),
            ]
            self._safe_update()
            return

        rows = []
        for run in runs:
            when = datetime.fromtimestamp(run["created_at"]).strftime("%Y-%m-%d %H:%M")
            status = run["status"]
            if status == "succeeded":
                metric = f"macro-F1 {run['macro_f1']:.1%}" if run["macro_f1"] is not None else ""
                status_color = theme.CLASS_COLORS["GOOD"]
            elif status == "failed":
                metric = (run["error"] or "")[:80]
                status_color = theme.CLASS_COLORS["BROKEN"]
            else:
                metric = run["current_stage"] or ""
                status_color = theme.INK_FAINT

            header = ft.Row(
                alignment=ft.MainAxisAlignment.SPACE_BETWEEN,
                controls=[
                    ft.Column(
                        spacing=2,
                        controls=[
                            ft.Text(f"{when} · {crop_label(run['crop'])}", size=13, weight=ft.FontWeight.W_600),
                            ft.Text(f"{status} — {metric}", size=12, color=status_color),
                        ],
                    ),
                    ft.Row(
                        spacing=8,
                        controls=[
                            leakage_badge(bool(run["test_leakage_safe"])) if status == "succeeded" else ft.Container(),
                            ft.Icon(ft.Icons.CHECK_CIRCLE, size=16, color=theme.ACCENT) if run["promoted"] else ft.Container(),
                        ],
                    ),
                ],
            )

            body_controls = [header]
            if status == "succeeded":
                confusion = json.loads(run["confusion_matrix_json"] or "[]")
                label_classes = json.loads(run["label_classes_json"] or "[]")
                body_controls.append(
                    ft.ExpansionTile(
                        title=ft.Text("Details", size=12),
                        controls=[
                            ft.Column(
                                spacing=8,
                                controls=[
                                    ft.Text(
                                        f"train {run['n_train_rows']} / val {run['n_val_rows']} / test {run['n_test_rows']} rows "
                                        f"· {run['n_batches']} batches · balanced accuracy {run['balanced_accuracy']:.1%}",
                                        size=12,
                                        color=theme.INK_FAINT,
                                    ),
                                    ft.Text(trained_on_text(run), size=12, color=theme.INK_FAINT),
                                    confusion_matrix_grid(confusion, label_classes),
                                ],
                            )
                        ],
                    )
                )

            rows.append(card(ft.Column(spacing=10, controls=body_controls)))

        self.root_column.controls = [
            ft.Text("History", size=24, weight=ft.FontWeight.BOLD, color=theme.INK),
            *rows,
        ]
        self._safe_update()

    def _safe_update(self) -> None:
        try:
            self.root_column.update()
        except (AssertionError, RuntimeError):
            pass

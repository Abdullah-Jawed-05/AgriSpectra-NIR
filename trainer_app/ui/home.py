"""Home — the landing screen and "shared chrome" status strip (§3)."""

from __future__ import annotations

from pathlib import Path

import flet as ft

from core import theme
from pipeline.preflight import scan_raw_data
from ui.components import card, class_counts_row, section_title, stat_tile


class HomeScreen:
    def __init__(self, ctx):
        self.ctx = ctx

    def build(self) -> ft.Control:
        ctx = self.ctx
        summary = scan_raw_data(Path(ctx.config.raw_data_root), ctx.crop)

        config_warning = None
        if not ctx.config.is_pipeline_configured():
            config_warning = ft.Container(
                bgcolor=theme.CLASS_COLORS["BROKEN"],
                border_radius=10,
                padding=ft.Padding(14, 10, 14, 10),
                content=ft.Row(
                    spacing=8,
                    controls=[
                        ft.Icon(ft.Icons.WARNING_AMBER_ROUNDED, color="#FFFFFF", size=18),
                        ft.Text(
                            "The ML pipeline scripts weren't found. Set the pipeline location in Settings.",
                            color="#FFFFFF",
                            size=13,
                        ),
                        ft.TextButton("Open Settings", on_click=lambda e: ctx.navigate("settings"), style=ft.ButtonStyle(color="#FFFFFF")),
                    ],
                ),
            )

        total_seeds = sum(summary.class_counts.values())

        stats_row = ft.Row(
            spacing=12,
            wrap=True,
            controls=[
                stat_tile("Total labelled seeds", str(total_seeds)),
                stat_tile("Collection batches", str(summary.n_batches)),
                stat_tile(
                    "Leakage-safe split possible",
                    "Yes" if summary.leakage_safe_possible else "No",
                    color=theme.CLASS_COLORS["GOOD"] if summary.leakage_safe_possible else theme.CLASS_COLORS["BROKEN"],
                ),
            ],
        )

        warnings_col = ft.Column(
            spacing=6,
            controls=[
                ft.Row(
                    spacing=8,
                    controls=[
                        ft.Icon(ft.Icons.INFO_OUTLINE, size=16, color=theme.INK_FAINT),
                        ft.Text(w, size=12, color=theme.INK_FAINT, expand=True),
                    ],
                )
                for w in summary.warnings
            ],
        )

        actions = ft.Row(
            spacing=12,
            controls=[
                ft.FilledButton(
                    "Start sorting",
                    icon=ft.Icons.GRID_VIEW_OUTLINED,
                    on_click=lambda e: ctx.navigate("sort"),
                    style=ft.ButtonStyle(bgcolor=theme.ACCENT, color="#FFFFFF"),
                ),
                ft.OutlinedButton(
                    "Train a model",
                    icon=ft.Icons.MODEL_TRAINING_OUTLINED,
                    on_click=lambda e: ctx.navigate("train"),
                    disabled=not summary.is_ready,
                ),
            ],
        )

        content = ft.Column(
            spacing=20,
            scroll=ft.ScrollMode.AUTO,
            controls=[
                ft.Text("AgriSpectra Trainer", size=26, weight=ft.FontWeight.BOLD, color=theme.INK),
                ft.Text(
                    "Sort seed photos, then train and evaluate Model V1 — entirely offline.",
                    size=14,
                    color=theme.INK_FAINT,
                ),
                *([config_warning] if config_warning else []),
                stats_row,
                card(
                    ft.Column(
                        spacing=10,
                        controls=[
                            section_title("Library — labelled seeds by class"),
                            class_counts_row(summary.class_counts) if summary.class_counts else ft.Text(
                                "No labelled photos yet. Start sorting to build your dataset.", color=theme.INK_FAINT
                            ),
                        ],
                    )
                ),
                card(ft.Column(spacing=8, controls=[section_title("Notes"), warnings_col])) if summary.warnings else ft.Container(),
                actions,
            ],
        )
        return content

"""Small reusable UI pieces shared across screens — kept dependency-free
of any single screen's state so Home/Sort/Train can all use them."""

from __future__ import annotations

import json

import flet as ft

from core import theme


def file_picker(ctx) -> ft.FilePicker:
    """The app's single FilePicker, created on first use.

    In Flet 1.0 FilePicker is a Service: constructing it registers it with
    the current page (so call this from inside an event handler, where
    `ft.context.page` is set). It must NOT also be added to `page.overlay`
    -- the old pre-1.0 pattern -- or the desktop client never gets a method
    listener and every call fails with "Timeout waiting for invoke method
    listener" after 10s. Reused rather than constructed per click, since
    each construction registers another service with the page.
    """
    picker = getattr(ctx, "_file_picker", None)
    if picker is None:
        picker = ft.FilePicker()
        ctx._file_picker = picker
    return picker


def stat_tile(label: str, value: str, color: str = theme.ACCENT) -> ft.Container:
    return ft.Container(
        bgcolor=theme.SURFACE_ALT,
        border_radius=10,
        padding=ft.Padding(16, 14, 16, 14),
        content=ft.Column(
            spacing=2,
            controls=[
                ft.Text(value, size=24, weight=ft.FontWeight.BOLD, color=color),
                ft.Text(label, size=12, color=theme.INK_FAINT),
            ],
        ),
    )


def class_chip(label: str, count: int) -> ft.Container:
    color = theme.CLASS_COLORS.get(label, theme.INK_FAINT)
    return ft.Container(
        padding=ft.Padding(10, 6, 10, 6),
        border_radius=20,
        bgcolor=color,
        content=ft.Text(
            f"{theme.CLASS_LABELS.get(label, label)} · {count}",
            size=12,
            weight=ft.FontWeight.W_600,
            color="#FFFFFF",
        ),
    )


def class_counts_row(counts: dict[str, int]) -> ft.Row:
    return ft.Row(
        wrap=True,
        spacing=8,
        run_spacing=8,
        controls=[class_chip(label, counts.get(label, 0)) for label in theme.CLASS_ORDER if label in counts or True],
    )


def trained_on_text(run) -> str:
    """Which batch folders a run used, for Results and History."""
    raw = run["batches_json"] if "batches_json" in run.keys() else None
    batches = json.loads(raw) if raw else None
    if not batches:
        return "Trained on: every batch (recorded before batches could be chosen)"
    return f"Trained on {len(batches)} batch{'es' if len(batches) != 1 else ''}: {', '.join(batches)}"


def section_title(text: str) -> ft.Text:
    return ft.Text(text, size=16, weight=ft.FontWeight.W_700, color=theme.INK)


def card(content: ft.Control, padding: int = 20) -> ft.Container:
    return ft.Container(
        bgcolor=theme.SURFACE,
        border_radius=14,
        padding=ft.Padding(padding, padding, padding, padding),
        border=ft.Border.all(1, theme.SURFACE_ALT),
        content=content,
    )


def leakage_badge(safe: bool) -> ft.Container:
    if safe:
        return ft.Container(
            padding=ft.Padding(10, 6, 10, 6),
            border_radius=20,
            bgcolor=theme.CLASS_COLORS["GOOD"],
            content=ft.Text("Leakage-safe test split", size=12, weight=ft.FontWeight.W_600, color="#FFFFFF"),
        )
    return ft.Container(
        padding=ft.Padding(10, 6, 10, 6),
        border_radius=20,
        bgcolor=theme.CLASS_COLORS["BROKEN"],
        content=ft.Text(
            "NOT leakage-safe — sanity check only, not a generalization estimate",
            size=12,
            weight=ft.FontWeight.W_600,
            color="#FFFFFF",
        ),
    )


def confusion_matrix_grid(matrix: list[list[int]], labels: list[str]) -> ft.Control:
    """A coloured heatmap grid, not a wall of numbers (§3 Mode B.3)."""
    if not matrix:
        return ft.Text("No confusion matrix available.", color=theme.INK_FAINT)

    max_val = max((v for row in matrix for v in row), default=1) or 1

    def cell_color(v: int, is_diag: bool) -> str:
        intensity = v / max_val
        base = theme.ACCENT if is_diag else "#B0401E"
        if intensity <= 0:
            return theme.SURFACE_ALT
        # blend base colour with white by intensity for a heatmap feel
        r = int(base[1:3], 16)
        g = int(base[3:5], 16)
        b = int(base[5:7], 16)
        blend = 0.15 + 0.85 * intensity
        r = int(255 * (1 - blend) + r * blend)
        g = int(255 * (1 - blend) + g * blend)
        b = int(255 * (1 - blend) + b * blend)
        return f"#{r:02X}{g:02X}{b:02X}"

    header_row = ft.Row(
        controls=[ft.Container(width=90)]
        + [ft.Container(width=70, content=ft.Text(lbl[:3], size=11, weight=ft.FontWeight.W_600), alignment=ft.Alignment.CENTER) for lbl in labels],
        spacing=4,
    )
    rows = [header_row]
    for i, row in enumerate(matrix):
        cells = [
            ft.Container(
                width=90,
                content=ft.Text(labels[i][:10], size=11, weight=ft.FontWeight.W_600),
            )
        ]
        for j, v in enumerate(row):
            cells.append(
                ft.Container(
                    width=70,
                    height=44,
                    bgcolor=cell_color(v, i == j),
                    border_radius=6,
                    alignment=ft.Alignment.CENTER,
                    content=ft.Text(str(v), size=13, weight=ft.FontWeight.W_700, color=theme.INK if v < max_val * 0.6 else "#FFFFFF"),
                )
            )
        rows.append(ft.Row(controls=cells, spacing=4))

    return ft.Column(
        spacing=6,
        controls=[ft.Text("Predicted → (rows = true label)", size=11, color=theme.INK_FAINT), *rows],
    )


def pipeline_stepper(stage_names: list[str], current_stage: str | None, failed_stage: str | None) -> ft.Row:
    order = {name: i for i, name in enumerate(stage_names)}
    current_idx = order.get(current_stage, -1) if current_stage else -1

    chips = []
    for i, name in enumerate(stage_names):
        if failed_stage == name:
            color, icon = theme.CLASS_COLORS["BROKEN"], ft.Icons.CLOSE
        elif i < current_idx or (current_idx == len(stage_names) - 1 and failed_stage is None and current_stage == name):
            color, icon = theme.ACCENT, ft.Icons.CHECK
        elif i == current_idx:
            color, icon = theme.ACCENT, None
        else:
            color, icon = theme.INK_FAINT, None

        chips.append(
            ft.Container(
                padding=ft.Padding(14, 8, 14, 8),
                border_radius=20,
                bgcolor=color if (i <= current_idx or failed_stage == name) else theme.SURFACE_ALT,
                content=ft.Row(
                    spacing=6,
                    controls=[
                        ft.ProgressRing(width=12, height=12, stroke_width=2, color="#FFFFFF")
                        if i == current_idx and icon is None and failed_stage is None
                        else (ft.Icon(icon, size=14, color="#FFFFFF") if icon else ft.Container(width=12)),
                        ft.Text(
                            name.capitalize(),
                            size=12,
                            weight=ft.FontWeight.W_600,
                            color="#FFFFFF" if (i <= current_idx or failed_stage == name) else theme.INK_FAINT,
                        ),
                    ],
                ),
            )
        )
        if i < len(stage_names) - 1:
            chips.append(ft.Container(width=18, height=2, bgcolor=theme.SURFACE_ALT, margin=ft.Margin(0, 14, 0, 0)))

    return ft.Row(controls=chips, spacing=4)

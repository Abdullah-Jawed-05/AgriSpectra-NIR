"""Sort Mode — §3 Mode A. Import/triage, the fast sort loop (buttons +
keyboard shortcuts + pre-suggestion + undo), and the review filmstrip.
"""

from __future__ import annotations

from pathlib import Path

import flet as ft

from core import theme
from sort.session import SortSession, default_batch_id
from ui.components import card, class_counts_row, section_title

MILESTONE_STEP = 40


class SortScreen:
    def __init__(self, ctx):
        self.ctx = ctx
        self.session: SortSession | None = None
        self.importing = False

        # Controls kept as attributes so event handlers can mutate them in place.
        self.root_column = ft.Column(spacing=18, scroll=ft.ScrollMode.AUTO, expand=True)
        self.batch_field = ft.TextField(dense=True, width=240)
        self.crop_image = ft.Image(src=None, fit=ft.BoxFit.CONTAIN, border_radius=12, width=360, height=360)
        self.source_label = ft.Text("", size=12, color=theme.INK_FAINT)
        self.suggestion_text = ft.Text("", size=13, weight=ft.FontWeight.W_600)
        self.progress_text = ft.Text("", size=13, color=theme.INK_FAINT)
        self.milestone_bar = ft.ProgressBar(value=0, color=theme.ACCENT, bgcolor=theme.SURFACE_ALT, height=8, border_radius=4)
        self.milestone_text = ft.Text("", size=11, color=theme.INK_FAINT)
        self.class_counts_container = ft.Row(wrap=True, spacing=8)
        self.class_buttons: dict[str, ft.Container] = {}
        self.sort_loop_panel = ft.Container(visible=False)
        self.import_panel = ft.Container()
        self.empty_state = ft.Container(visible=False)
        self.filmstrip_container = ft.Column(spacing=10)
        self.import_progress_text = ft.Text("", size=12, color=theme.INK_FAINT)
        self.import_progress_bar = ft.ProgressBar(value=0, visible=False, color=theme.ACCENT, bgcolor=theme.SURFACE_ALT)
        self.triage_summary_container = ft.Column(spacing=10)
        self.allow_textured_cb = ft.Checkbox(label="Allow textured background", value=False)
        self.one_seed_cb = ft.Checkbox(label="One seed per photo (macro shots)", value=False)

    # ---- lifecycle ------------------------------------------------

    def on_show(self) -> None:
        existing = SortSession.find_active(self.ctx.db, self.ctx.config, self.ctx.crop)
        self.session = existing
        self._rebuild()

    def build(self) -> ft.Control:
        self._build_static_layout()
        self._rebuild()
        return self.root_column

    def _build_static_layout(self) -> None:
        self.import_panel = card(
            ft.Column(
                spacing=14,
                controls=[
                    section_title("Import photos"),
                    ft.Text(
                        "Drop in a folder of raw barley photos. Each usable photo is segmented into "
                        "individual seed crops you sort one at a time.",
                        size=12,
                        color=theme.INK_FAINT,
                    ),
                    ft.Row(
                        controls=[
                            ft.Text("Batch:", size=12, color=theme.INK_FAINT),
                            self.batch_field,
                        ]
                    ),
                    ft.Row(controls=[self.allow_textured_cb, self.one_seed_cb]),
                    ft.FilledButton(
                        "Choose folder…",
                        icon=ft.Icons.FOLDER_OPEN_OUTLINED,
                        on_click=self._on_choose_folder,
                        style=ft.ButtonStyle(bgcolor=theme.ACCENT, color="#FFFFFF"),
                    ),
                    self.import_progress_text,
                    self.import_progress_bar,
                    self.triage_summary_container,
                ],
            )
        )

        for label in theme.SORTABLE_CLASSES:
            shortcut = next(k for k, v in theme.SORT_SHORTCUTS.items() if v == label)
            btn = ft.Container(
                padding=ft.Padding(16, 14, 16, 14),
                border_radius=10,
                bgcolor=theme.CLASS_COLORS[label],
                border=ft.Border.all(3, theme.CLASS_COLORS[label]),
                on_click=lambda e, lb=label: self._file(lb),
                content=ft.Column(
                    spacing=2,
                    horizontal_alignment=ft.CrossAxisAlignment.CENTER,
                    controls=[
                        ft.Text(theme.CLASS_LABELS[label], size=14, weight=ft.FontWeight.W_700, color="#FFFFFF"),
                        ft.Text(f"key {shortcut}", size=10, color="#FFFFFFCC"),
                    ],
                ),
            )
            self.class_buttons[label] = btn

        button_row = ft.Row(spacing=10, wrap=True, controls=list(self.class_buttons.values()))

        self.sort_loop_panel = ft.Container(
            visible=False,
            content=ft.Column(
                spacing=16,
                controls=[
                    ft.Row(
                        alignment=ft.MainAxisAlignment.SPACE_BETWEEN,
                        controls=[
                            ft.Row(spacing=10, controls=[ft.Text("Batch:", size=12, color=theme.INK_FAINT), self.batch_field]),
                            ft.OutlinedButton("Undo last", icon=ft.Icons.UNDO, on_click=self._on_undo),
                        ],
                    ),
                    self.progress_text,
                    ft.Column(spacing=4, controls=[self.milestone_bar, self.milestone_text]),
                    card(
                        ft.Column(
                            horizontal_alignment=ft.CrossAxisAlignment.CENTER,
                            spacing=14,
                            controls=[
                                self.crop_image,
                                self.source_label,
                                self.suggestion_text,
                                button_row,
                            ],
                        )
                    ),
                    section_title("This session"),
                    self.class_counts_container,
                    section_title("Review — click any seed to re-file it"),
                    self.filmstrip_container,
                ],
            ),
        )

        self.empty_state = ft.Container(
            visible=False,
            content=card(
                ft.Column(
                    horizontal_alignment=ft.CrossAxisAlignment.CENTER,
                    spacing=10,
                    controls=[
                        ft.Icon(ft.Icons.CHECK_CIRCLE_OUTLINE, size=40, color=theme.ACCENT),
                        ft.Text("All sorted for this batch.", size=16, weight=ft.FontWeight.W_700),
                        ft.Text("Import more photos above, or head to Train once you have enough labelled seeds.", size=12, color=theme.INK_FAINT),
                    ],
                )
            ),
        )

        self.root_column.controls = [
            ft.Text("Sort", size=24, weight=ft.FontWeight.BOLD, color=theme.INK),
            self.import_panel,
            self.sort_loop_panel,
            self.empty_state,
        ]

    # ---- import ------------------------------------------------------

    async def _on_choose_folder(self, e) -> None:
        picker = ft.FilePicker()
        self.ctx.page.overlay.append(picker)
        self.ctx.page.update()
        path = await picker.get_directory_path(dialog_title="Choose a folder of raw seed photos")
        self.ctx.page.overlay.remove(picker)
        self.ctx.page.update()
        if not path:
            return
        self.ctx.page.run_thread(self._do_import, path)

    def _do_import(self, folder: str) -> None:
        self.importing = True
        self.import_progress_bar.visible = True
        self.import_progress_text.value = "Triaging photos…"
        self._safe_update()

        if self.session is None:
            batch_id = (self.batch_field.value or "").strip() or default_batch_id(self.ctx.config, self.ctx.crop)
            self.session = SortSession.create(self.ctx.db, self.ctx.config, self.ctx.crop, batch_id, folder)
            self.batch_field.value = batch_id

        def on_progress(i, total):
            self.import_progress_text.value = f"Processing photo {i}/{total}…"
            self.import_progress_bar.value = i / total if total else 0
            self._safe_update()

        try:
            summary = self.session.import_photos(
                Path(folder),
                allow_textured_bg=self.allow_textured_cb.value,
                one_seed=self.one_seed_cb.value,
                on_progress=on_progress,
            )
        except FileNotFoundError as exc:
            self.importing = False
            self.import_progress_bar.visible = False
            self.ctx.notify(str(exc), error=True)
            return

        self.importing = False
        self.import_progress_bar.visible = False
        self.import_progress_text.value = ""
        self._show_triage_summary(summary)
        self._rebuild()

    def _show_triage_summary(self, summary) -> None:
        rejected = self.session.rejected_photos() if self.session else []
        rows = [
            ft.Text(
                f"{summary.total} photos imported · {len(summary.usable)} usable · "
                f"{len(summary.textured_rejected)} rejected (textured background) · "
                f"{len(summary.piled_rejected)} rejected (piled/touching) · "
                f"{len(summary.no_seed_rejected)} rejected (no seed found)",
                size=12,
            )
        ]
        for r in rejected:
            if r["overridden"]:
                continue
            rows.append(
                ft.Row(
                    controls=[
                        ft.Text(f"{Path(r['source_image']).name} — {r['reason']}", size=11, color=theme.INK_FAINT, expand=True),
                        ft.TextButton("Keep anyway", on_click=lambda e, rid=r["id"]: self._override_rejected(rid)),
                    ]
                )
            )
        self.triage_summary_container.controls = rows

    def _override_rejected(self, rejected_id: int) -> None:
        if self.session is None:
            return
        match = next((r for r in self.session.rejected_photos() if r["id"] == rejected_id), None)
        if match is None:
            return
        self.ctx.page.run_thread(self._do_override, dict(match))

    def _do_override(self, row: dict) -> None:
        n = self.session.override_rejected(row)
        self.ctx.notify(f"Added {n} seed crop(s) from {Path(row['source_image']).name} to the queue.")
        self._rebuild()

    # ---- sort loop -----------------------------------------------------

    def _rebuild(self) -> None:
        if self.session is None:
            self.import_panel.visible = True
            self.sort_loop_panel.visible = False
            self.empty_state.visible = False
            self._safe_update()
            return

        self.import_panel.visible = True
        stats = self.session.stats()
        item = self.session.current_item()

        if item is None and stats["total"] == 0:
            self.sort_loop_panel.visible = False
            self.empty_state.visible = False
            self._safe_update()
            return

        if item is None:
            self.sort_loop_panel.visible = False
            self.empty_state.visible = True
            self._safe_update()
            return

        self.sort_loop_panel.visible = True
        self.empty_state.visible = False

        self.crop_image.src = item["crop_image_path"]
        self.source_label.value = f"from {item['source_image']}"
        label = item["suggested_label"]
        self.suggestion_text.value = f"Suggested: {theme.CLASS_LABELS.get(label, label)} — {item['suggested_reason']}"
        self.suggestion_text.color = theme.CLASS_COLORS.get(label, theme.INK)

        for cls, btn in self.class_buttons.items():
            is_suggested = cls == label
            btn.border = ft.Border.all(3, "#FFFFFF" if is_suggested else theme.CLASS_COLORS[cls])
            btn.opacity = 1.0 if is_suggested else 0.82

        self.progress_text.value = f"{stats['filed']} sorted · {stats['pending']} remaining · {stats['total']} total this batch"

        next_milestone = ((stats["filed"] // MILESTONE_STEP) + 1) * MILESTONE_STEP
        self.milestone_bar.value = (stats["filed"] % MILESTONE_STEP) / MILESTONE_STEP
        remaining_to_milestone = next_milestone - stats["filed"]
        self.milestone_text.value = f"{remaining_to_milestone} more → {next_milestone} seeds sorted"

        self.class_counts_container.controls = class_counts_row(stats["by_class"]).controls

        self._rebuild_filmstrip()
        self._safe_update()

    def _rebuild_filmstrip(self) -> None:
        if self.session is None:
            return
        items = self.session.review_filmstrip(limit=120)
        groups: dict[str, list] = {}
        for it in items:
            groups.setdefault(it["filed_label"], []).append(it)

        sections = []
        for label in theme.SORTABLE_CLASSES:
            group_items = groups.get(label, [])
            if not group_items:
                continue
            thumbs = [self._thumbnail(it) for it in group_items[:30]]
            sections.append(
                ft.Column(
                    spacing=6,
                    controls=[
                        ft.Text(f"{theme.CLASS_LABELS[label]} ({len(group_items)})", size=12, weight=ft.FontWeight.W_600, color=theme.CLASS_COLORS[label]),
                        ft.Row(wrap=True, spacing=6, controls=thumbs),
                    ],
                )
            )
        self.filmstrip_container.controls = sections

    def _thumbnail(self, item) -> ft.Control:
        return ft.Container(
            width=56,
            height=56,
            border_radius=6,
            on_click=lambda e, it=item: self._open_refile_dialog(it),
            content=ft.Image(src=item["crop_image_path"], fit=ft.BoxFit.COVER, border_radius=6, width=56, height=56),
            tooltip=item["source_image"],
        )

    def _open_refile_dialog(self, item) -> None:
        def make_handler(lb):
            def handler(e):
                self.ctx.page.pop_dialog()
                self._refile(item["id"], lb)

            return handler

        buttons = [
            ft.FilledButton(
                theme.CLASS_LABELS[lb],
                on_click=make_handler(lb),
                style=ft.ButtonStyle(bgcolor=theme.CLASS_COLORS[lb], color="#FFFFFF"),
            )
            for lb in theme.SORTABLE_CLASSES
        ]
        dialog = ft.AlertDialog(
            title=ft.Text("Re-file this seed"),
            content=ft.Column(tight=True, controls=[ft.Image(src=item["crop_image_path"], width=160, height=160, fit=ft.BoxFit.CONTAIN), ft.Row(wrap=True, spacing=8, controls=buttons)]),
        )
        self.ctx.page.show_dialog(dialog)

    def _refile(self, item_id: int, label: str) -> None:
        if self.session is None:
            return
        self.session.refile(item_id, label)
        self._rebuild()

    def _file(self, label: str) -> None:
        if self.session is None or self.importing:
            return
        self.session.file_current(label)
        self._rebuild()

    def _on_undo(self, e) -> None:
        if self.session is None:
            return
        undone = self.session.undo_last()
        if undone is None:
            self.ctx.notify("Nothing to undo.")
            return
        self._rebuild()

    def on_keyboard(self, e: ft.KeyboardEvent) -> None:
        if self.session is None or self.importing:
            return
        if e.key in theme.SORT_SHORTCUTS:
            self._file(theme.SORT_SHORTCUTS[e.key])
        elif e.key in ("U", "Backspace"):
            self.session.undo_last()
            self._rebuild()

    def _safe_update(self) -> None:
        try:
            self.root_column.update()
        except (AssertionError, RuntimeError):
            pass  # not yet mounted on the page

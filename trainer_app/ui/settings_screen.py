"""Settings — §3 "Shared chrome": where the raw-data root, model output,
and the pipeline scripts/python interpreter live."""

from __future__ import annotations

import flet as ft

from core import theme
from ui.components import card, section_title


class SettingsScreen:
    def __init__(self, ctx):
        self.ctx = ctx
        self.fields: dict[str, ft.TextField] = {}
        self.status_text = ft.Text("", size=12)

    def _field(self, key: str, label: str, hint: str) -> ft.TextField:
        tf = ft.TextField(label=label, value=getattr(self.ctx.config, key), hint_text=hint, dense=True)
        self.fields[key] = tf
        return tf

    def _pick_folder(self, key: str) -> None:
        async def handler(_: ft.Event) -> None:
            picker = ft.FilePicker()
            self.ctx.page.overlay.append(picker)
            self.ctx.page.update()
            path = await picker.get_directory_path(dialog_title=f"Choose {key}")
            self.ctx.page.overlay.remove(picker)
            if path:
                self.fields[key].value = path
                self.ctx.page.update()

        return handler

    def _save(self, e) -> None:
        cfg = self.ctx.config
        for key, tf in self.fields.items():
            setattr(cfg, key, tf.value)
        cfg.ensure_dirs()
        cfg.save()
        ok = cfg.is_pipeline_configured()
        self.status_text.value = (
            "Saved. Pipeline scripts found." if ok else "Saved — but prepare_dataset.py was not found at that pipeline location."
        )
        self.status_text.color = theme.CLASS_COLORS["GOOD"] if ok else theme.CLASS_COLORS["BROKEN"]
        self.ctx.page.update()

    def build(self) -> ft.Control:
        cfg = self.ctx.config

        def row_with_browse(key, label, hint):
            field = self._field(key, label, hint)
            return ft.Row(
                controls=[
                    ft.Container(content=field, expand=True),
                    ft.IconButton(icon=ft.Icons.FOLDER_OPEN_OUTLINED, on_click=self._pick_folder(key), tooltip="Browse"),
                ]
            )

        return ft.Column(
            spacing=20,
            scroll=ft.ScrollMode.AUTO,
            controls=[
                ft.Text("Settings", size=24, weight=ft.FontWeight.BOLD, color=theme.INK),
                card(
                    ft.Column(
                        spacing=14,
                        controls=[
                            section_title("Dataset locations"),
                            row_with_browse("raw_data_root", "Raw / sorted photos root", "raw/<crop>/<batch>/<LABEL>/*.jpg"),
                            row_with_browse("models_root", "Trained models output", ""),
                            row_with_browse("work_root", "Working/cache directory", "sort crop cache, run artifacts"),
                            row_with_browse("export_root", "Promote-to-App export output", ""),
                        ],
                    )
                ),
                card(
                    ft.Column(
                        spacing=14,
                        controls=[
                            section_title("Pipeline"),
                            row_with_browse("pipeline_dir", "ml/ pipeline scripts directory", "the ml/ folder (scripts, training, evaluation, preprocessing)"),
                            self._field("python_exe", "Python interpreter", "python executable with the ml/requirements.txt packages installed"),
                            ft.Text(
                                "Configured: prepare_dataset.py found at this location"
                                if cfg.is_pipeline_configured()
                                else "Not configured — prepare_dataset.py not found here yet",
                                size=12,
                                color=theme.CLASS_COLORS["GOOD"] if cfg.is_pipeline_configured() else theme.CLASS_COLORS["BROKEN"],
                            ),
                        ],
                    )
                ),
                ft.Row(
                    controls=[
                        ft.FilledButton("Save settings", on_click=self._save, style=ft.ButtonStyle(bgcolor=theme.ACCENT, color="#FFFFFF")),
                        self.status_text,
                    ]
                ),
            ],
        )

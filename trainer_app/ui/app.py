"""App shell: left navigation + a swappable content pane. One Flet Page,
no routes — simple enough for a 5-screen desktop tool and it keeps all
cross-screen state (the active sort session, the active training run) in
one place (AppContext) instead of re-fetching through a router.
"""

from __future__ import annotations

import flet as ft

from core import theme
from core.config import AppConfig
from data.db import Database


class AppContext:
    """Shared state + helpers every screen gets a reference to."""

    def __init__(self, page: ft.Page, config: AppConfig, db: Database):
        self.page = page
        self.config = config
        self.db = db
        self.crop = "barley"
        self.navigate: callable = lambda name: None  # set by AppShell
        self.refresh_home: callable = lambda: None

    def notify(self, text: str, error: bool = False) -> None:
        self.page.show_dialog(
            ft.SnackBar(
                content=ft.Text(text, color="#FFFFFF"),
                bgcolor=theme.CLASS_COLORS["BROKEN"] if error else theme.ACCENT,
            )
        )


NAV_ITEMS = [
    ("home", "Home", ft.Icons.HOME_OUTLINED),
    ("sort", "Sort", ft.Icons.GRID_VIEW_OUTLINED),
    ("train", "Train", ft.Icons.MODEL_TRAINING_OUTLINED),
    ("history", "History", ft.Icons.HISTORY_OUTLINED),
    ("settings", "Settings", ft.Icons.SETTINGS_OUTLINED),
]


class AppShell:
    def __init__(self, page: ft.Page, config: AppConfig, db: Database):
        self.page = page
        self.ctx = AppContext(page, config, db)
        self.ctx.navigate = self.navigate
        self._screens: dict[str, object] = {}
        self._current = "home"

        self.content_pane = ft.Container(expand=True, padding=28, bgcolor=theme.SURFACE)
        self.nav_buttons: dict[str, ft.Container] = {}

        nav_column = ft.Column(
            spacing=4,
            controls=[self._brand_header(), ft.Container(height=12), *self._build_nav_buttons()],
        )
        sidebar = ft.Container(
            width=208,
            bgcolor=theme.SURFACE_ALT,
            padding=ft.Padding(14, 20, 14, 20),
            content=nav_column,
        )

        self.root = ft.Row(
            expand=True,
            spacing=0,
            controls=[sidebar, ft.VerticalDivider(width=1, color=theme.SURFACE_ALT), self.content_pane],
        )

        page.on_keyboard_event = self._on_keyboard

    def _brand_header(self) -> ft.Control:
        return ft.Row(
            spacing=10,
            controls=[
                ft.Container(
                    width=30,
                    height=30,
                    border_radius=8,
                    bgcolor=theme.ACCENT,
                    content=ft.Icon(ft.Icons.GRASS_OUTLINED, color="#FFFFFF", size=18),
                    alignment=ft.Alignment.CENTER,
                ),
                ft.Column(
                    spacing=0,
                    controls=[
                        ft.Text("AgriSpectra", size=14, weight=ft.FontWeight.W_700, color=theme.INK),
                        ft.Text("Trainer", size=11, color=theme.INK_FAINT),
                    ],
                ),
            ],
        )

    def _build_nav_buttons(self) -> list[ft.Control]:
        buttons = []
        for key, label, icon in NAV_ITEMS:
            btn = ft.Container(
                padding=ft.Padding(12, 10, 12, 10),
                border_radius=8,
                on_click=lambda e, k=key: self.navigate(k),
                content=ft.Row(spacing=10, controls=[ft.Icon(icon, size=18, color=theme.INK), ft.Text(label, size=13, color=theme.INK)]),
            )
            self.nav_buttons[key] = btn
            buttons.append(btn)
        return buttons

    def _refresh_nav_highlight(self) -> None:
        for key, btn in self.nav_buttons.items():
            active = key == self._current
            btn.bgcolor = theme.ACCENT_MUTED if active else None
            row = btn.content
            icon_ctl, text_ctl = row.controls
            icon_ctl.color = theme.ACCENT if active else theme.INK
            text_ctl.color = theme.ACCENT if active else theme.INK
            text_ctl.weight = ft.FontWeight.W_700 if active else ft.FontWeight.W_400

    def _get_screen(self, name: str):
        if name not in self._screens:
            if name == "home":
                from ui.home import HomeScreen

                self._screens[name] = HomeScreen(self.ctx)
            elif name == "sort":
                from ui.sort_screen import SortScreen

                self._screens[name] = SortScreen(self.ctx)
            elif name == "train":
                from ui.train_screen import TrainScreen

                self._screens[name] = TrainScreen(self.ctx)
            elif name == "history":
                from ui.history_screen import HistoryScreen

                self._screens[name] = HistoryScreen(self.ctx)
            elif name == "settings":
                from ui.settings_screen import SettingsScreen

                self._screens[name] = SettingsScreen(self.ctx)
            else:
                raise ValueError(name)
        return self._screens[name]

    def navigate(self, name: str) -> None:
        self._current = name
        self._refresh_nav_highlight()
        screen = self._get_screen(name)
        self.content_pane.content = screen.build()
        self.page.update()
        on_show = getattr(screen, "on_show", None)
        if on_show:
            on_show()

    def _on_keyboard(self, e: ft.KeyboardEvent) -> None:
        sort_screen = self._screens.get("sort")
        if self._current == "sort" and sort_screen is not None:
            handler = getattr(sort_screen, "on_keyboard", None)
            if handler:
                handler(e)

    def mount(self) -> None:
        self.page.add(self.root)
        self.navigate("home")


def build_page(page: ft.Page, config: AppConfig, db: Database) -> AppShell:
    page.title = "AgriSpectra Trainer"
    page.bgcolor = theme.SURFACE
    page.fonts = {}
    # Every surface here is hard-coded light, so pin light mode -- following
    # a dark OS theme would give default-styled widgets light text on these
    # light surfaces. Brand colours are set explicitly rather than seeded:
    # a seed makes Material 3 derive a paler teal, which left outlined
    # buttons and checkbox labels too faint to notice.
    page.theme_mode = ft.ThemeMode.LIGHT
    page.theme = ft.Theme(
        font_family=theme.FONT_FAMILY,
        color_scheme=ft.ColorScheme(
            primary=theme.ACCENT,
            on_primary="#FFFFFF",
            on_surface=theme.INK,
            on_surface_variant=theme.INK_MUTED,
            outline=theme.ACCENT,
            surface=theme.SURFACE,
        ),
    )
    page.padding = 0
    page.window.width = 1180
    page.window.height = 820
    page.window.min_width = 900
    page.window.min_height = 640

    shell = AppShell(page, config, db)
    shell.mount()
    return shell

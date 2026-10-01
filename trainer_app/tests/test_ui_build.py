"""Control-tree construction tests for every screen.

These don't exercise the real Flutter client (no display is available in
CI), but they do build every screen's real Flet control tree against the
actual installed Flet API, which catches the overwhelming majority of
wiring mistakes (wrong constructor args, renamed enums, bad imports).
"""

from __future__ import annotations

from core import theme


class StubWindow:
    width = height = min_width = min_height = None


class StubPage:
    def __init__(self):
        self.controls = []
        self.overlay = []
        self.window = StubWindow()
        self.theme = None
        self.title = None
        self.bgcolor = None
        self.padding = None
        self.fonts = None
        self.on_keyboard_event = None
        self._dialogs = []

    def add(self, *controls):
        self.controls.extend(controls)

    def update(self, *controls):
        pass

    def show_dialog(self, dialog):
        self._dialogs.append(dialog)

    def pop_dialog(self):
        return self._dialogs.pop() if self._dialogs else None

    def run_thread(self, fn, *a, **k):
        fn(*a, **k)


def test_app_shell_builds_and_navigates_every_screen(config, db):
    from ui.app import AppShell

    page = StubPage()
    shell = AppShell(page, config, db)
    shell.mount()

    for name, _, _ in __import__("ui.app", fromlist=["NAV_ITEMS"]).NAV_ITEMS:
        shell.navigate(name)
        assert shell.content_pane.content is not None


def test_keyboard_routes_only_to_sort_screen(config, db):
    from ui.app import AppShell

    class FakeKey:
        key = "1"

    page = StubPage()
    shell = AppShell(page, config, db)
    shell.mount()

    shell.navigate("home")
    shell._on_keyboard(FakeKey())  # must not raise while not on sort

    shell.navigate("sort")
    shell._on_keyboard(FakeKey())  # no active session: swallowed, must not raise


def test_sort_screen_full_loop_via_ui(config, db, import_folder):
    from ui.sort_screen import SortScreen

    class Ctx:
        pass

    ctx = Ctx()
    ctx.config = config
    ctx.db = db
    ctx.crop = "barley"
    ctx.page = StubPage()
    ctx.navigate = lambda n: None
    ctx.notify = lambda *a, **k: None

    screen = SortScreen(ctx)
    screen.build()
    screen._do_import(str(import_folder))
    assert screen.session is not None
    assert screen.sort_loop_panel.visible is True

    stats_before = screen.session.stats()
    screen._file(screen.class_buttons and next(iter(theme.SORTABLE_CLASSES)))
    assert screen.session.stats()["filed"] == stats_before["filed"] + 1


def test_train_screen_preflight_disables_start_when_no_data(config, db):
    from ui.train_screen import TrainScreen

    class Ctx:
        pass

    ctx = Ctx()
    ctx.config = config
    ctx.db = db
    ctx.crop = "barley"
    ctx.page = StubPage()
    ctx.navigate = lambda n: None
    ctx.notify = lambda *a, **k: None

    screen = TrainScreen(ctx)
    screen.build()
    assert screen.start_button.disabled is True

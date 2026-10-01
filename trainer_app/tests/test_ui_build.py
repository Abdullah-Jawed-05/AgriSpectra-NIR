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


def test_sort_screen_phone_export_import_via_ui(config, db, tmp_path):
    import zipfile

    from ui.sort_screen import SortScreen

    zip_path = tmp_path / "export.zip"
    with zipfile.ZipFile(zip_path, "w") as zf:
        zf.writestr("barley/app_2026-10-02/GOOD/seed1.png", b"a")
        zf.writestr("barley/app_2026-10-02/DAMAGED/seed2.png", b"b")

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
    screen._do_import_phone_export(str(zip_path))

    assert "Imported 2 seed(s)" in screen.phone_import_text.value
    raw_root = __import__("pathlib").Path(config.raw_data_root)
    assert (raw_root / "barley" / "app_2026-10-02" / "GOOD" / "seed1.png").is_file()
    assert (raw_root / "barley" / "app_2026-10-02" / "DAMAGED" / "seed2.png").is_file()


def test_train_screen_promote_and_copy_to_app(config, db, tmp_path):
    import json
    from pathlib import Path

    import joblib
    import numpy as np
    from sklearn.ensemble import RandomForestClassifier

    from ui.train_screen import TrainScreen

    # A fake completed run — bypasses the slow real pipeline (covered by
    # test_pipeline_runner.py's slow test), since this test only exercises
    # Promote to App -> Copy to app.
    model_dir = tmp_path / "model"
    model_dir.mkdir()
    rng = np.random.default_rng(0)
    model = RandomForestClassifier(n_estimators=5, max_depth=3, random_state=0)
    model.fit(rng.normal(size=(30, 3)), rng.integers(0, 2, size=30))
    joblib.dump(model, model_dir / "model.joblib")
    (model_dir / "feature_columns.json").write_text(json.dumps(["f0", "f1", "f2"]))
    (model_dir / "label_classes.json").write_text(json.dumps(["GOOD", "DAMAGED"]))

    run_id = db.create_run(str(tmp_path / "work"))
    db.finish_run(run_id, model_dir=str(model_dir), macro_f1=0.5, balanced_accuracy=0.5)

    config.app_lib_ml_dir = str(tmp_path / "app_lib_ml")

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
    screen._do_promote(run_id)

    export_dir = Path(config.export_root) / f"trained_model_run_{run_id}"
    assert export_dir.is_dir()  # Promote to App actually ran

    screen._do_copy_to_app(export_dir)

    app_ml_dir = Path(config.app_lib_ml_dir)
    assert (app_ml_dir / "model_v1_generated.dart").is_file()
    assert (app_ml_dir / "agrispectra_model_v1_adapter.dart").is_file()
    copy_text = "".join(str(c.value) for c in screen.copy_status.controls if hasattr(c, "value"))
    assert "Copied to" in copy_text
    assert "useModelV1" in copy_text


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

"""Control-tree construction tests for every screen.

These don't exercise the real Flutter client (no display is available in
CI), but they do build every screen's real Flet control tree against the
actual installed Flet API, which catches the overwhelming majority of
wiring mistakes (wrong constructor args, renamed enums, bad imports).
"""

from __future__ import annotations

import flet as ft

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

    screen._do_copy_to_app(export_dir, run_id)

    app_ml_dir = Path(config.app_lib_ml_dir)
    assert (app_ml_dir / "model_v1_generated.dart").is_file()
    assert (app_ml_dir / "agrispectra_model_v1_adapter.dart").is_file()
    copy_text = "".join(str(c.value) for c in screen.copy_status.controls if hasattr(c, "value"))
    assert "Copied to" in copy_text
    assert "useModelV1" in copy_text


def test_train_screen_enable_model_v1_and_build_apk(config, db, tmp_path):
    from unittest.mock import patch

    from pipeline.runner import StageResult
    from promote.activate import ApkBuildResult
    from ui.train_screen import TrainScreen

    app_root = tmp_path / "app"
    app_ml_dir = app_root / "lib" / "ml"
    app_ml_dir.mkdir(parents=True)
    (app_ml_dir / "model_v1_predictor.dart").write_text("const bool useModelV1 = false;\n")
    (app_root / "pubspec.yaml").write_text("name: agrispectra\n")

    config.app_lib_ml_dir = str(app_ml_dir)
    config.flutter_exe = "flutter"

    run_id = db.create_run(str(tmp_path / "work"))
    db.finish_run(
        run_id,
        model_dir=str(tmp_path / "model"),
        macro_f1=0.8,
        balanced_accuracy=0.75,
        v0_baseline_json='{"macro_f1": 0.4, "scope_note": "V0 only predicts GOOD or DAMAGED."}',
    )

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

    def collect_text(control) -> str:
        parts = []
        value = getattr(control, "value", None)
        if value:
            parts.append(str(value))
        for child in getattr(control, "controls", None) or []:
            parts.append(collect_text(child))
        return " ".join(parts)

    screen._open_activate_confirm(run_id)
    assert len(ctx.page._dialogs) == 1
    dialog_text = collect_text(ctx.page._dialogs[0].content)
    assert "80.0%" in dialog_text  # the actual comparison numbers were shown, not just a generic prompt

    apk_path = app_root / "build" / "app" / "outputs" / "flutter-apk" / "app-release.apk"
    with (
        patch("ui.train_screen.build_apk", return_value=ApkBuildResult(True, apk_path, "BUILD SUCCESSFUL", 42.0)) as mock_build,
        patch("ui.train_screen.list_connected_devices", return_value=["Pixel 7 (mobile)"]),
    ):
        screen._do_enable_and_build(run_id)

    mock_build.assert_called_once()
    assert (app_ml_dir / "model_v1_predictor.dart").read_text().strip() == "const bool useModelV1 = true;"
    status_text = collect_text(screen.activate_status)
    assert "useModelV1 is now true" in status_text
    assert str(apk_path) in status_text
    assert "Pixel 7" in status_text

    with patch("ui.train_screen.install_apk", return_value=StageResult("install_apk", 0, "Installing...", 3.0)) as mock_install:
        screen._do_install(app_root)
    mock_install.assert_called_once()
    assert "Installed." in collect_text(screen.activate_status)


def test_train_screen_enable_model_v1_build_failure_is_reported(config, db, tmp_path):
    from unittest.mock import patch

    from promote.activate import ApkBuildResult
    from ui.train_screen import TrainScreen

    app_root = tmp_path / "app"
    app_ml_dir = app_root / "lib" / "ml"
    app_ml_dir.mkdir(parents=True)
    (app_ml_dir / "model_v1_predictor.dart").write_text("const bool useModelV1 = false;\n")
    (app_root / "pubspec.yaml").write_text("name: agrispectra\n")

    config.app_lib_ml_dir = str(app_ml_dir)
    config.flutter_exe = "flutter"

    run_id = db.create_run(str(tmp_path / "work"))
    db.finish_run(run_id, model_dir=str(tmp_path / "model"), macro_f1=0.5)

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

    with patch("ui.train_screen.build_apk", return_value=ApkBuildResult(False, None, "BUILD FAILED: gradle error", 5.0)):
        screen._do_enable_and_build(run_id)

    # useModelV1 still flips -- that part succeeded independently of the build.
    assert "true" in (app_ml_dir / "model_v1_predictor.dart").read_text()
    status_text = "".join(str(c.value) for c in screen.activate_status.controls if hasattr(c, "value"))
    assert "Build failed" in status_text
    assert "gradle error" in status_text


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


def test_sort_screen_presorted_plan_and_import(config, db, tmp_path):
    from pathlib import Path

    from sort.presorted_import import scan_presorted_folder
    from ui.sort_screen import SortScreen

    src = tmp_path / "Barley V4"
    for folder, n in {"Good": 3, "Impurity": 1}.items():
        (src / folder).mkdir(parents=True)
        for i in range(n):
            (src / folder / f"{i}.jpg").write_bytes(b"x")

    class Ctx:
        pass

    notes = []
    ctx = Ctx()
    ctx.config = config
    ctx.db = db
    ctx.crop = "barley"
    ctx.page = StubPage()
    ctx.navigate = lambda n: None
    ctx.notify = lambda msg, **k: notes.append(msg)

    screen = SortScreen(ctx)
    screen.build()
    screen.presorted_plan = scan_presorted_folder(src)
    screen.presorted_batch_field.value = "sorted_barley_v4"
    screen._show_presorted_plan(screen.presorted_plan)

    def text_of(c) -> str:
        parts = [str(getattr(c, "value", "") or "")]
        if isinstance(getattr(c, "content", None), str):
            parts.append(c.content)
        for child in getattr(c, "controls", None) or []:
            parts.append(text_of(child))
        return " ".join(parts)

    plan_text = text_of(screen.presorted_container)
    assert "Impurity" in plan_text and "Impurities" in plan_text  # the lenient rename is shown

    screen._do_import_presorted()

    batch = Path(config.raw_data_root) / "barley" / "sorted_barley_v4"
    assert len(list((batch / "GOOD").iterdir())) == 3
    assert len(list((batch / "IMPURITIES").iterdir())) == 1
    assert "Imported 4 photos" in text_of(screen.presorted_container)
    assert notes == []


def test_crop_switch_changes_every_screen_and_persists(config, db, tmp_path, monkeypatch):
    import json

    import core.paths as paths
    from ui.app import AppShell

    settings = tmp_path / "settings.json"
    monkeypatch.setattr(paths, "config_file", lambda: settings)  # never touch the real settings

    shell = AppShell(StubPage(), config, db)
    shell.mount()
    shell.navigate("sort")
    old_sort = shell._screens["sort"]

    shell.set_crop("wheat")

    assert shell.ctx.crop == "wheat"
    assert json.loads(settings.read_text())["crop"] == "wheat"
    assert shell._screens["sort"] is not old_sort  # rebuilt, not holding barley's session
    assert shell.crop_dropdown.value == "wheat"
    assert "wheat" in [o.key for o in shell.crop_dropdown.options]


def test_add_crop_dialog_switches_on_enter_and_rejects_blank(config, db, tmp_path, monkeypatch):
    import core.paths as paths
    from ui.app import AppShell

    monkeypatch.setattr(paths, "config_file", lambda: tmp_path / "settings.json")
    page = StubPage()
    shell = AppShell(page, config, db)
    shell.mount()

    shell._open_add_crop_dialog()
    dialog = page._dialogs[-1]
    field, error = dialog.content.controls[1], dialog.content.controls[2]

    field.value = "  !! "
    field.on_submit(None)
    assert page._dialogs == [dialog] and error.value  # stays open with a hint
    assert shell.ctx.crop == "barley"

    field.value = "Durum Wheat"
    field.on_submit(None)  # Enter in the field
    assert page._dialogs == []
    assert shell.ctx.crop == "durum_wheat"


def test_crop_switch_refused_mid_training(config, db, tmp_path, monkeypatch):
    import core.paths as paths
    from ui.app import AppShell

    monkeypatch.setattr(paths, "config_file", lambda: tmp_path / "settings.json")
    shell = AppShell(StubPage(), config, db)
    shell.mount()
    shell.navigate("train")
    shell._screens["train"].running = True
    notes = []
    shell.ctx.notify = lambda msg, **k: notes.append(msg)

    shell.set_crop("wheat")

    assert shell.ctx.crop == "barley"
    assert notes and "Finish" in notes[0]


def test_non_barley_run_cannot_be_promoted(config, db, tmp_path):
    from ui.train_screen import TrainScreen

    class Ctx:
        pass

    ctx = Ctx()
    ctx.config = config
    ctx.db = db
    ctx.crop = "wheat"
    ctx.page = StubPage()
    ctx.navigate = lambda n: None
    notes = []
    ctx.notify = lambda msg, **k: notes.append(msg)

    run_id = db.create_run(str(tmp_path / "w"), crop="wheat")
    db.finish_run(run_id, model_dir=str(tmp_path / "model"), macro_f1=0.5)

    screen = TrainScreen(ctx)
    screen.build()
    controls = screen._promote_controls(db.get_run(run_id), lambda e: None)
    assert not any(isinstance(c, ft.Row) for c in controls)  # no Promote button row
    assert "only supports Barley" in controls[0].value

    screen._do_promote(run_id)  # the handler itself refuses too
    assert notes and "Only Barley" in notes[0]

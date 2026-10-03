from __future__ import annotations

import sys
from unittest.mock import patch

from core.config import _discover_python_exe


def test_discover_python_exe_uses_sys_executable_when_not_frozen():
    with patch.object(sys, "frozen", False, create=True):
        assert _discover_python_exe() == sys.executable


def test_discover_python_exe_searches_path_when_frozen():
    """Regression: a packaged build's sys.executable is this app's own
    exe, not a general-purpose interpreter -- using it as python_exe
    would make every Train Mode subprocess call fail silently against
    the wrong binary."""
    with patch.object(sys, "frozen", True, create=True), patch("shutil.which") as which:
        which.side_effect = lambda name: "/usr/bin/python" if name == "python" else None
        assert _discover_python_exe() == "/usr/bin/python"
        which.assert_any_call("python")


def test_load_repairs_paths_left_by_a_deleted_build(tmp_path, monkeypatch):
    """Regression: a real settings.json pointed pipeline_dir and python_exe
    into a temp build folder that had since been deleted (python_exe was that
    build's own exe), so Train and Promote could only fail."""
    import json

    import core.paths as paths
    from core.config import AppConfig

    gone = tmp_path / "trainer_build" / "windows"
    settings = tmp_path / "settings.json"
    settings.write_text(json.dumps({
        "raw_data_root": str(tmp_path / "raw"),
        "pipeline_dir": str(gone / "ml"),
        "python_exe": str(gone / "AgriSpectra Trainer.exe"),
    }))
    monkeypatch.setattr(paths, "config_file", lambda: settings)

    cfg = AppConfig.load()

    assert cfg.is_pipeline_configured()
    assert cfg.python_exe == sys.executable
    assert cfg.raw_data_root == str(tmp_path / "raw")  # user's own choices are kept
    assert "trainer_build" in settings.read_text()  # repaired in memory, file not rewritten


def test_repair_keeps_working_paths(config):
    before = (config.pipeline_dir, config.python_exe)
    config.repair_stale_tool_paths()
    assert (config.pipeline_dir, config.python_exe) == before


def test_packaged_build_never_uses_its_own_exe_as_python(tmp_path):
    from core.config import _is_usable_python

    own_exe = tmp_path / "AgriSpectra Trainer.exe"
    own_exe.write_bytes(b"")
    with patch.object(sys, "frozen", True, create=True), patch.object(sys, "executable", str(own_exe)):
        assert not _is_usable_python(str(own_exe))
    assert not _is_usable_python(str(tmp_path / "missing.exe"))
    assert not _is_usable_python("")


def test_discover_python_exe_empty_when_frozen_and_nothing_found():
    with patch.object(sys, "frozen", True, create=True), patch("shutil.which", return_value=None):
        assert _discover_python_exe() == ""

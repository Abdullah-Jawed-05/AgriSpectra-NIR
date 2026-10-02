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


def test_discover_python_exe_empty_when_frozen_and_nothing_found():
    with patch.object(sys, "frozen", True, create=True), patch("shutil.which", return_value=None):
        assert _discover_python_exe() == ""

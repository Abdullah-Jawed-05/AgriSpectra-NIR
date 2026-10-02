"""Enable Model V1 & rebuild APK — §4.4. Mechanizes the two mechanical
steps left after Promote to App / Copy to app: flipping `useModelV1` and
running `flutter build apk`. The decision itself — whether V1 actually
deserves to replace V0 — stays with whoever clicks the button in the UI,
which the train_screen.py caller shows the V0-vs-V1 comparison for before
offering this action. This module does the mechanics only; it never
decides, and it never runs on its own after a promote or a copy.
"""

from __future__ import annotations

import re
import time
from dataclasses import dataclass
from pathlib import Path
from typing import Optional

from pipeline.runner import OnLine, StageResult, run_subprocess

_ENABLED_LINE = "const bool useModelV1 = true;"
_DISABLED_LINE = "const bool useModelV1 = false;"
_PREDICTOR_FILENAME = "model_v1_predictor.dart"


class PredictorFileError(RuntimeError):
    """model_v1_predictor.dart is missing, or doesn't contain the exact
    `useModelV1` line this module knows how to flip — e.g. it was
    hand-edited since. Never guess at a different line to replace; fail
    clearly instead (§6: don't silently do the wrong thing to a file a
    human maintains by hand)."""


def _predictor_path(app_lib_ml_dir: Path) -> Path:
    return app_lib_ml_dir / _PREDICTOR_FILENAME


def is_model_v1_enabled(app_lib_ml_dir: Path) -> bool:
    path = _predictor_path(app_lib_ml_dir)
    if not path.is_file():
        raise PredictorFileError(f"{path} not found — is app_lib_ml_dir set correctly in Settings?")
    text = path.read_text()
    if _ENABLED_LINE in text:
        return True
    if _DISABLED_LINE in text:
        return False
    raise PredictorFileError(
        f"{path} doesn't contain the expected `useModelV1` line — it may have been hand-edited. "
        "Not flipping it automatically; check it manually."
    )


def enable_model_v1(app_lib_ml_dir: Path) -> None:
    """Flips `useModelV1` to `true` in model_v1_predictor.dart. Idempotent
    (a no-op if already enabled). Raises PredictorFileError rather than
    touching the file if the expected line isn't found exactly as
    written — see its docstring."""
    path = _predictor_path(app_lib_ml_dir)
    if not path.is_file():
        raise PredictorFileError(f"{path} not found — is app_lib_ml_dir set correctly in Settings?")
    text = path.read_text()
    if _ENABLED_LINE in text:
        return
    if _DISABLED_LINE not in text:
        raise PredictorFileError(
            f"{path} doesn't contain the expected `useModelV1` line — it may have been hand-edited. "
            "Not flipping it automatically; check it manually."
        )
    path.write_text(text.replace(_DISABLED_LINE, _ENABLED_LINE, 1))


@dataclass
class ApkBuildResult:
    success: bool
    apk_path: Optional[Path]
    log: str
    duration_s: float


def build_apk(flutter_exe: str, app_root: Path, on_line: Optional[OnLine] = None) -> ApkBuildResult:
    """Runs `flutter build apk` (release, the default build type) from
    `app_root` via the same subprocess-streaming helper the four training
    stages use. `flutter build apk`'s output path is fixed by Flutter's
    own convention, not something this app controls."""
    start = time.monotonic()
    try:
        result: StageResult = run_subprocess(
            [flutter_exe, "build", "apk"],
            app_root,
            "build_apk",
            on_line,
        )
    except FileNotFoundError as exc:
        return ApkBuildResult(
            success=False,
            apk_path=None,
            log=f"Could not run {flutter_exe!r}: {exc}. Check Settings -> Flutter SDK.",
            duration_s=time.monotonic() - start,
        )

    apk_path = app_root / "build" / "app" / "outputs" / "flutter-apk" / "app-release.apk"
    success = result.returncode == 0 and apk_path.is_file()
    return ApkBuildResult(success=success, apk_path=apk_path if success else None, log=result.log, duration_s=result.duration_s)


_DEVICE_LINE_RE = re.compile(r"^(?P<name>.+?)\s+•\s+(?P<id>\S+)\s+•", re.MULTILINE)


def list_connected_devices(flutter_exe: str) -> list[str]:
    """Best-effort list of connected device names via `flutter devices`,
    for the optional "install to device" follow-up — never required,
    never assumed to find anything."""
    try:
        result = run_subprocess([flutter_exe, "devices"], None, "list_devices", None)
    except FileNotFoundError:
        return []
    if result.returncode != 0:
        return []
    return [m.group("name").strip() for m in _DEVICE_LINE_RE.finditer(result.log)]


def install_apk(flutter_exe: str, app_root: Path, on_line: Optional[OnLine] = None) -> StageResult:
    """Runs `flutter install` from `app_root`, pushing the just-built APK
    to whatever device `flutter` picks (its own default when exactly one
    is connected; errors clearly otherwise — never guessed at here)."""
    return run_subprocess([flutter_exe, "install"], app_root, "install_apk", on_line)

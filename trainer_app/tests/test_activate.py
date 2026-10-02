from __future__ import annotations

from pathlib import Path
from unittest.mock import patch

import pytest

from pipeline.runner import StageResult
from promote.activate import (
    ApkBuildResult,
    PredictorFileError,
    build_apk,
    enable_model_v1,
    install_apk,
    is_model_v1_enabled,
    list_connected_devices,
)

PREDICTOR_TEMPLATE = """import 'x.dart';

const bool useModelV1 = {value};

QualityPrediction? tryModelV1(SeedFeatures features) {{
  if (!useModelV1 || !modelV1Available) return null;
}}
"""


@pytest.fixture
def app_lib_ml_dir(tmp_path: Path) -> Path:
    d = tmp_path / "app_lib_ml"
    d.mkdir()
    (d / "model_v1_predictor.dart").write_text(PREDICTOR_TEMPLATE.format(value="false"))
    return d


def test_enable_model_v1_flips_the_flag(app_lib_ml_dir: Path):
    assert is_model_v1_enabled(app_lib_ml_dir) is False
    enable_model_v1(app_lib_ml_dir)
    assert is_model_v1_enabled(app_lib_ml_dir) is True
    text = (app_lib_ml_dir / "model_v1_predictor.dart").read_text()
    assert "useModelV1 = true" in text
    # Nothing else in the file was touched.
    assert "QualityPrediction? tryModelV1" in text


def test_enable_model_v1_is_idempotent(app_lib_ml_dir: Path):
    enable_model_v1(app_lib_ml_dir)
    enable_model_v1(app_lib_ml_dir)  # must not raise or double-replace
    text = (app_lib_ml_dir / "model_v1_predictor.dart").read_text()
    assert text.count("useModelV1 = true") == 1


def test_enable_model_v1_missing_file_raises(tmp_path: Path):
    with pytest.raises(PredictorFileError):
        enable_model_v1(tmp_path / "does_not_exist")


def test_enable_model_v1_refuses_to_guess_at_a_hand_edited_file(app_lib_ml_dir: Path):
    (app_lib_ml_dir / "model_v1_predictor.dart").write_text("// someone rewrote this file entirely\n")
    with pytest.raises(PredictorFileError):
        enable_model_v1(app_lib_ml_dir)


def test_build_apk_reports_file_not_found_clearly(tmp_path: Path):
    result = build_apk("C:/nonexistent/flutter.exe", tmp_path)
    assert result.success is False
    assert result.apk_path is None
    assert "flutter.exe" in result.log


def test_build_apk_success_finds_the_fixed_output_path(tmp_path: Path):
    apk_path = tmp_path / "build" / "app" / "outputs" / "flutter-apk" / "app-release.apk"
    apk_path.parent.mkdir(parents=True)
    apk_path.write_bytes(b"fake apk")

    with patch("promote.activate.run_subprocess", return_value=StageResult("build_apk", 0, "BUILD SUCCESSFUL", 12.3)):
        result: ApkBuildResult = build_apk("flutter", tmp_path)

    assert result.success is True
    assert result.apk_path == apk_path
    assert result.duration_s == 12.3


def test_build_apk_nonzero_exit_is_a_failure_even_if_a_stale_apk_exists(tmp_path: Path):
    apk_path = tmp_path / "build" / "app" / "outputs" / "flutter-apk" / "app-release.apk"
    apk_path.parent.mkdir(parents=True)
    apk_path.write_bytes(b"stale apk from a previous build")

    with patch("promote.activate.run_subprocess", return_value=StageResult("build_apk", 1, "BUILD FAILED", 2.0)):
        result = build_apk("flutter", tmp_path)

    assert result.success is False
    assert result.apk_path is None  # never point at a stale artifact as if it were fresh


def test_list_connected_devices_parses_flutter_devices_output():
    sample = (
        "Found 2 connected devices:\n"
        "Pixel 7 (mobile)       • 1A2B3C4D5E • android-arm64  • Android 14 (API 34)\n"
        "Windows (desktop)      • windows    • windows-x64    • Microsoft Windows\n"
    )
    with patch("promote.activate.run_subprocess", return_value=StageResult("list_devices", 0, sample, 1.0)):
        devices = list_connected_devices("flutter")
    assert devices == ["Pixel 7 (mobile)", "Windows (desktop)"]


def test_list_connected_devices_empty_when_flutter_not_found():
    with patch("promote.activate.run_subprocess", side_effect=FileNotFoundError()):
        assert list_connected_devices("flutter") == []


def test_install_apk_delegates_to_flutter_install(tmp_path: Path):
    with patch("promote.activate.run_subprocess", return_value=StageResult("install_apk", 0, "Installing...", 5.0)) as mock_run:
        result = install_apk("flutter", tmp_path)
    mock_run.assert_called_once_with(["flutter", "install"], tmp_path, "install_apk", None)
    assert result.returncode == 0

from __future__ import annotations

import json

import joblib
import numpy as np
import pytest
from sklearn.ensemble import RandomForestClassifier
from sklearn.preprocessing import LabelEncoder

import sys

from conftest import REPO_ML_DIR
from promote.export import PromoteFailed, copy_promoted_to, promote_model

sys.path.insert(0, str(REPO_ML_DIR / "export"))
from dart_fallback_codegen import export_forest_to_dart  # noqa: E402


@pytest.fixture
def trained_model_dir(tmp_path):
    rng = np.random.default_rng(0)
    x = rng.normal(size=(120, 5))
    y = rng.integers(0, 3, size=120)
    encoder = LabelEncoder().fit(["GOOD", "DAMAGED", "BROKEN"])

    model = RandomForestClassifier(n_estimators=10, max_depth=4, random_state=0)
    model.fit(x, y)

    model_dir = tmp_path / "model"
    model_dir.mkdir()
    joblib.dump(model, model_dir / "model.joblib")
    (model_dir / "feature_columns.json").write_text(json.dumps([f"f{i}" for i in range(5)]))
    (model_dir / "label_classes.json").write_text(json.dumps(list(encoder.classes_)))

    return model_dir, model, x


def test_promote_model_m2cgen_path(tmp_path, config, trained_model_dir):
    model_dir, _model, _x = trained_model_dir
    export_root = tmp_path / "export"
    result = promote_model(config, model_dir, export_root, run_id="r1", version_label="t1")

    assert result.method == "m2cgen"
    assert result.generated_dart_path.is_file()
    assert result.adapter_dart_path.is_file()
    assert "List<double> score(List<double> input)" in result.generated_dart_path.read_text()
    adapter_text = result.adapter_dart_path.read_text()
    assert "modelV1FeatureOrder" in adapter_text
    assert "const bool modelV1Available = true;" in adapter_text
    assert "f0" in adapter_text
    assert "GOOD" in adapter_text

    feature_cols = json.loads((result.export_dir / "feature_columns.json").read_text())
    assert feature_cols == result.feature_columns

    # Dart requires UTF-8 source; Windows' default encoding wrote the header's
    # em dash as byte 0x97, which Dart flags as an invalid UTF-8 sequence.
    for path in (result.generated_dart_path, result.adapter_dart_path):
        path.read_bytes().decode("utf-8")  # raises if not valid UTF-8


def test_copy_promoted_to_copies_both_dart_files(tmp_path, config, trained_model_dir):
    model_dir, _model, _x = trained_model_dir
    export_root = tmp_path / "export"
    result = promote_model(config, model_dir, export_root, run_id="r1", version_label="t1")

    destination = tmp_path / "app_lib_ml"
    copied = copy_promoted_to(result.export_dir, destination)

    names = {p.name for p in copied}
    assert names == {"model_v1_generated.dart", "agrispectra_model_v1_adapter.dart"}
    for p in copied:
        assert p.is_file()
        assert p.read_text() == (result.export_dir / p.name).read_text()


def test_fallback_codegen_matches_sklearn_predict(trained_model_dir):
    model_dir, model, x = trained_model_dir
    dart = export_forest_to_dart(model)
    assert "List<double> score(List<double> input)" in dart

    label_classes = json.loads((model_dir / "label_classes.json").read_text())
    n_classes = len(label_classes)

    def tree_leaf_proportions(tree, row):
        node = 0
        while tree.children_left[node] != -1:
            node = tree.children_left[node] if row[tree.feature[node]] <= tree.threshold[node] else tree.children_right[node]
        counts = tree.value[node][0]
        return counts / counts.sum()

    # Mirrors RandomForestClassifier.predict: average each tree's leaf
    # class-proportions (soft voting), then argmax — NOT a majority vote
    # of each tree's own hard per-tree prediction.
    mismatches = 0
    for row in x[:40]:
        scores = np.zeros(n_classes)
        for est in model.estimators_:
            scores += tree_leaf_proportions(est.tree_, row)
        fallback_pred = int(np.argmax(scores))
        sklearn_pred = int(model.predict(row.reshape(1, -1))[0])
        mismatches += fallback_pred != sklearn_pred

    assert mismatches == 0


def test_promote_runs_in_the_configured_python_not_in_process(tmp_path, config, trained_model_dir):
    """Regression: the packaged Trainer has no scikit-learn, so unpickling
    model.joblib in-process failed ("No module named 'sklearn'"). Promote
    must go through config.python_exe; a bad interpreter must fail cleanly."""
    model_dir, _model, _x = trained_model_dir
    config.python_exe = str(tmp_path / "no_such_python.exe")
    with pytest.raises(PromoteFailed):
        promote_model(config, model_dir, tmp_path / "export", run_id="r1")


def test_promote_surfaces_script_errors(tmp_path, config):
    empty_model_dir = tmp_path / "model"
    empty_model_dir.mkdir()
    with pytest.raises(PromoteFailed) as exc:
        promote_model(config, empty_model_dir, tmp_path / "export", run_id="r1")
    assert "model.joblib" in str(exc.value)

from __future__ import annotations

import json

import joblib
import numpy as np
import pytest
from sklearn.ensemble import RandomForestClassifier
from sklearn.preprocessing import LabelEncoder

from promote.export import promote_model
from promote.fallback_codegen import export_forest_to_dart


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


def test_promote_model_m2cgen_path(tmp_path, trained_model_dir):
    model_dir, _model, _x = trained_model_dir
    export_root = tmp_path / "export"
    result = promote_model(model_dir, export_root, run_id="r1", version_label="t1")

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

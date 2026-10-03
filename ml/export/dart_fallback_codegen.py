"""Fallback Dart codegen for when m2cgen can't export a model — §4.5.

Hand-generates one nested if/else Dart function per tree directly from
scikit-learn's own tree introspection (`estimator.tree_`), each returning
its leaf's class-proportion vector, then sums them across trees —
matching `RandomForestClassifier.predict`'s own rule exactly: it averages
each tree's `predict_proba` (soft voting) and argmaxes the result, NOT a
majority vote of each tree's own hard per-tree prediction (summing
instead of averaging gives the same argmax and avoids a division in
Dart). Produces a `score(List<double> input) -> List<double>` function
with the same shape m2cgen's exporters use (one weight per class, argmax
= predicted class), so `promote/export.py`'s adapter needs no changes
depending on which path generated the file.

This is the *preferred* path for scikit-learn forests, not just a fallback:
m2cgen emits a whole forest as one giant function, and Flutter's AOT
compiler (`flutter build apk`) ran out of memory on that for a 300-tree
model. One small function per tree compiles fine. m2cgen remains the path
for model types this can't handle (e.g. LightGBM).
"""

from __future__ import annotations


def _tree_to_dart(tree, node: int, n_classes: int, indent: str) -> str:
    left = tree.children_left[node]
    right = tree.children_right[node]
    if left == -1 and right == -1:
        # A leaf's *class-proportion* vector, not a hard one-hot argmax:
        # RandomForestClassifier.predict averages each tree's predict_proba
        # (leaf class proportions) and argmaxes the sum — "soft" voting,
        # not a majority vote of each tree's own hard prediction. Emitting
        # a one-hot vector here would silently diverge from the real
        # model's predictions whenever a tree's leaf is impure.
        counts = tree.value[node][0]
        total = float(counts.sum()) or 1.0
        vec = ", ".join(repr(float(c) / total) for c in counts)
        return f"{indent}return const [{vec}];\n"  # const: no allocation per call

    # Plain Python int/float first: under NumPy 2, repr() of a NumPy scalar
    # is "np.float64(0.4)", which would be emitted into the Dart verbatim.
    feature = int(tree.feature[node])
    threshold = float(tree.threshold[node])
    out = f"{indent}if (input[{feature}] <= {threshold!r}) {{\n"
    out += _tree_to_dart(tree, left, n_classes, indent + "  ")
    out += f"{indent}}} else {{\n"
    out += _tree_to_dart(tree, right, n_classes, indent + "  ")
    out += f"{indent}}}\n"
    return out


def export_forest_to_dart(model, function_name: str = "score") -> str:
    if not hasattr(model, "estimators_") or not hasattr(model, "n_classes_"):
        raise ValueError(
            f"Fallback codegen only supports a scikit-learn forest (estimators_ of "
            f"DecisionTreeClassifier); got {type(model).__name__}. m2cgen's own exporter "
            "failed for this model type and there's no further fallback for it."
        )

    n_classes = int(model.n_classes_)
    n_trees = len(model.estimators_)

    parts: list[str] = []
    for i, estimator in enumerate(model.estimators_):
        tree = estimator.tree_
        body = _tree_to_dart(tree, 0, n_classes, "  ")
        parts.append(f"List<double> _tree{i}(List<double> input) {{\n{body}}}\n")

    # Each tree runs once per prediction and adds its leaf vector. Keeping
    # every tree in its own small function (rather than one giant function,
    # as m2cgen emits) is what lets Flutter's AOT compiler handle large
    # forests: it optimizes per function, and a single 60k-line function
    # ran it out of memory on a 300-tree model.
    tree_list = ", ".join(f"_tree{i}" for i in range(n_trees))
    main = (
        f"const List<List<double> Function(List<double>)> _trees = [{tree_list}];\n\n"
        f"List<double> {function_name}(List<double> input) {{\n"
        f"  final votes = List<double>.filled({n_classes}, 0.0);\n"
        f"  for (final tree in _trees) {{\n"
        f"    final leaf = tree(input);\n"
        f"    for (var c = 0; c < {n_classes}; c++) {{\n"
        f"      votes[c] += leaf[c];\n"
        f"    }}\n"
        f"  }}\n"
        f"  return votes;\n"
        f"}}\n"
    )
    return "\n".join(parts) + "\n" + main

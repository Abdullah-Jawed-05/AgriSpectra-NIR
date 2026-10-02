"""Locates and loads the real ml/ pipeline — the "wrap, don't reimplement"
seam from docs/TRAINER_APP_BUILD_PROMPT.md §5/§6.

Two integration paths, both calling the unmodified ml/ code:

- `import_preprocessing()` — a direct Python import of
  `preprocessing.segmentation` / `preprocessing.features`, used read-only
  by Sort Mode for live, interactive per-seed segmentation (§5: "a second,
  independent integration path is fine... read-only, feature-extraction
  only, never training").
- `stage_command()` (pipeline/runner.py) — builds the exact subprocess
  argv for each of the four training stages, which always run as
  unmodified scripts, never imported.
"""

from __future__ import annotations

import sys
import types
from pathlib import Path

from core.config import AppConfig


def _ensure_on_path(pipeline_dir: Path) -> None:
    p = str(pipeline_dir)
    if p not in sys.path:
        sys.path.insert(0, p)


def import_preprocessing(config: AppConfig) -> types.SimpleNamespace:
    """Imports the real segmentation/feature-extraction code from ml/.

    Raises FileNotFoundError with a clear message if ml/ isn't where
    config.pipeline_dir says — callers (importer.py) turn that into a
    Settings-screen-pointing error in the UI rather than a crash.
    """
    if not config.is_pipeline_configured():
        raise FileNotFoundError(
            f"Pipeline scripts not found under {config.pipeline_dir!r}. "
            "Set the correct path in Settings -> Pipeline location."
        )
    _ensure_on_path(Path(config.pipeline_dir))
    from preprocessing import features, segmentation  # noqa: PLC0415

    return types.SimpleNamespace(
        segment=segmentation.segment,
        assess_background_texture=segmentation.assess_background_texture,
        pick_primary_seed=segmentation.pick_primary_seed,
        extract_all=features.extract_all,
    )


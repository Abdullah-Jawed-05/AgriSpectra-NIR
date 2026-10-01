# AgriSpectra Trainer

An offline, gamified seed-labelling + model-training desktop app. It's a
companion to the AgriSpectra phone app (`../app/`): sort raw seed photos
into quality classes, then run the real training pipeline (`../ml/`) —
Prepare → Split → Train → Evaluate — entirely on your own machine, no
cloud, no AI assistant required at runtime.

Full product spec: [`../docs/TRAINER_APP_BUILD_PROMPT.md`](../docs/TRAINER_APP_BUILD_PROMPT.md).

This app **wraps** `../ml/` — it never reimplements segmentation, feature
extraction, or training. Sort Mode imports the real
`preprocessing.segmentation` / `preprocessing.features` modules directly
(read-only, for live per-seed previews); Train Mode runs the real
`prepare_dataset.py` / `split_dataset.py` / `train_baseline.py` /
`evaluate_model.py` scripts as unmodified subprocesses.

## Running it from source

```bash
cd trainer_app
python -m venv .venv
source .venv/bin/activate   # .venv\Scripts\activate on Windows
pip install -r requirements.txt
python main.py
```

On first launch it creates `Documents/AgriSpectra Trainer/` (raw photos,
models, working cache, promote-to-app exports) and auto-detects the
`ml/` pipeline scripts as a sibling directory. If that auto-detection is
wrong (e.g. you moved the scripts, or you're running a packaged build),
fix the paths in **Settings**.

## Running the tests

```bash
cd trainer_app
pip install -r requirements.txt pytest
python -m pytest            # fast tests only take a few seconds
python -m pytest -m slow    # includes a real prepare→split→train→evaluate run
```

`tests/test_ui_build.py` builds every screen's real Flet control tree
against the actual installed Flet API (no display needed) — it's not a
substitute for clicking through the app, but it catches the large
majority of UI wiring mistakes. `tests/test_pipeline_runner.py` and
`tests/test_promote_export.py` exercise the real `ml/` scripts and a real
trained model end to end.

## Packaging a standalone Windows .exe

```bash
cd trainer_app
pip install -r requirements.txt

# Vendor the exact ml/ scripts this build was tested against, so the
# packaged app is fully self-contained (per docs/TRAINER_APP_BUILD_PROMPT.md §5):
cp -r ../ml .

flet build windows
```

The output lands in `build/windows/` — a single folder you can zip and
hand to the project owner. No Python install, no `pip install`, no
terminal required on their end. `flet build` bundles Python + every
dependency in `requirements.txt`.

If `flet build windows` isn't available in your Flet version, fall back
to PyInstaller:

```bash
pip install pyinstaller
pyinstaller --name "AgriSpectra Trainer" --windowed --icon assets/icon.png \
    --add-data "ml;ml" --add-data "assets;assets" main.py
```

## Project layout

```
trainer_app/
  main.py                  entry point (ft.run)
  core/                     settings (config.py), brand palette (theme.py), app-data paths
  data/db.py                SQLite: sort-session queue/undo, training-run history (app state only —
                             never the dataset itself, see §5 of the build prompt)
  sort/                     Sort Mode: import/triage (importer.py), session state machine
                             (session.py), the Model V0 pre-suggestion rule (suggest.py)
  pipeline/                 Train Mode: pre-flight scan (preflight.py), subprocess orchestration
                             of the real ml/ scripts (runner.py), the ml/ import seam (scripts.py)
  promote/                  "Promote to App": m2cgen Dart export + adapter (export.py), the
                             scikit-learn tree-introspection fallback codegen (fallback_codegen.py)
  ui/                       Flet screens: app.py (shell/nav), home.py, sort_screen.py,
                             train_screen.py, history_screen.py, settings_screen.py, components.py
  tests/                    pytest — fast by default, `-m slow` for the real pipeline run
  assets/                   window icon + its generator
```

## Design notes / non-negotiables

See `docs/TRAINER_APP_BUILD_PROMPT.md` §6 for the full list. The two
most load-bearing ones, reflected throughout this code:

- **Never lose sorted data.** Every filed seed is copied to
  `raw/<crop>/<batch_id>/<LABEL>/` immediately (`sort/session.py:file_current`)
  — the filesystem is the durable truth, the SQLite queue is only
  bookkeeping that can be rebuilt by re-importing.
- **Never claim a metric that isn't leakage-safe.** The results dashboard
  and History both show `split_summary.json`'s `test_leakage_safe` flag
  prominently (`ui/components.py:leakage_badge`) rather than a clean-
  looking number with the caveat buried.

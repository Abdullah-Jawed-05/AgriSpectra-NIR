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

Train Mode's pre-flight lists every batch folder of the current crop with a
checkbox. Only ticked batches are trained on (passed to `prepare_dataset.py`
as `--batch`). Unticked batches are remembered per crop in settings, and
each run records the batches it used, shown in Results and History.
Unticking never moves or deletes any photos.

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

**Use PyInstaller, not `flet build windows`.** `flet build` was tried
first and does not work for this app: it compiles every bundled `.py`
file (including a vendored copy of `ml/`) to `.pyc`, which breaks Train
Mode's file-discovery and its subprocess calls into those scripts: it has
no standalone `python.exe` inside the package at all, so even with that
fixed, nothing could spawn `prepare_dataset.py` etc.; and its bundler
drops `opencv-python`'s required `config.py`, breaking Sort Mode too
(`ImportError: OpenCV loader: missing configuration file`). PyInstaller's
own community hooks (`pyinstaller-hooks-contrib`, a PyInstaller
dependency) handle `cv2`/`sklearn` correctly, and it preserves normal,
uncompiled `.py` files for anything added via `--add-data`.

**This build deliberately requires Python already installed** on the
machine that runs it (the project owner's own machine qualifies) — Train
Mode subprocesses into it to run the real, unmodified `ml/` scripts, per
the "wrap, don't reimplement" rule in
`docs/TRAINER_APP_BUILD_PROMPT.md` §5/§6. A fully self-contained build
would additionally need to bundle a second, portable Python specifically
for that subprocess target; deliberately not done here, to keep the
build simpler and more reliable.

```bash
cd trainer_app
pip install -r requirements.txt
pip install pyinstaller

# 1. A multi-resolution .ico (Windows needs one; assets/icon.png alone
#    isn't accepted by --icon). Regenerate whenever icon.png changes:
python -c "from PIL import Image; Image.open('assets/icon.png').save('assets/icon.ico', sizes=[(16,16),(32,32),(48,48),(64,64),(128,128),(256,256)])"

# 2. Flet's desktop view is a separate, generic, version-pinned native
#    binary (not something PyInstaller builds) that flet_desktop normally
#    downloads to ~/.flet/client/ on first run. Bundle it instead, so the
#    packaged app needs no internet on first launch. MUST match the exact
#    flet/flet-desktop version pinned in requirements.txt -- re-download
#    after any version bump, or the client silently won't match:
curl -L -o flet-windows.zip "https://github.com/flet-dev/flet/releases/download/v1.0.3/flet-windows.zip"

# 3. Build. --onedir (the default, no --onefile): PyInstaller's
#    self-extracting --onefile mode re-extracts on every launch, same
#    startup cost flet build's bundler had.
pyinstaller main.py --name "AgriSpectra Trainer" --windowed \
    --icon assets/icon.ico \
    --add-data "assets;assets" \
    --add-data "flet-windows.zip;flet_desktop/app" \
    --collect-all flet --collect-all flet_desktop \
    --noconfirm

# 4. Ship the pipeline scripts next to the exe, where auto-detection looks
#    for them. Only git-tracked files -- a working ml/ can hold gigabytes
#    of local datasets that must not be copied. Run from the repo root:
git ls-files ml | while read f; do mkdir -p "trainer_app/dist/AgriSpectra Trainer/$(dirname "$f")" && cp "$f" "trainer_app/dist/AgriSpectra Trainer/$f"; done
```

The output lands in `dist/AgriSpectra Trainer/` — zip that whole folder
(not just the `.exe`; it needs `_internal/` and `ml/` alongside it) to
hand off. On first launch it finds the bundled `ml/` and the `python` on
PATH by itself. That Python must have `ml/requirements.txt` installed
(scikit-learn, pandas, …) — check **Settings → Python interpreter** if
Train reports a missing module. A saved path that stops existing (a
deleted build folder, a moved checkout) is re-detected on the next launch
rather than left broken; a path that still works is never overridden.

Launch-test it before shipping — actually open it and click into Sort
Mode, not just confirm the process doesn't immediately exit; both earlier
packaging bugs looked fine at a glance (process stayed alive) and only
surfaced once a screen that imports `cv2` was opened.

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
                             scikit-learn tree-introspection fallback codegen (fallback_codegen.py),
                             and "Enable Model V1 & rebuild APK" (activate.py) — flips the
                             useModelV1 flag + runs flutter build apk, never on its own
  ui/                       Flet screens: app.py (shell/nav), home.py, sort_screen.py,
                             train_screen.py, history_screen.py, settings_screen.py, components.py
  tests/                    pytest — fast by default, `-m slow` for the real pipeline run
  assets/                   window icon + its generator
```

## From a trained model to a new APK

Train a run → **Promote to App** → **Copy to app** (writes the two
generated Dart files into Settings' `app/lib/ml/` directory) → **Enable
Model V1 & rebuild APK**, which shows the V1-vs-V0 comparison for that
run, and on confirmation flips `useModelV1` to `true` in
`app/lib/ml/model_v1_predictor.dart` and runs `flutter build apk` (needs
Settings' Flutter SDK executable set). It then offers to `flutter
install` to a connected device if one's found. Nothing in this chain
runs on its own after a promote or a copy — each step is its own button,
and the comparison is shown before the one step that actually changes
what the app predicts.

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

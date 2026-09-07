# AgriSpectra — Project Handoff

*Feed this whole file to Claude to resume work on the project. It is the
running state of everything done so far, why, and what's left. Last
updated: 2026-09-08.*

---

## 1. What this is

**AgriSpectra** — a software-first, sensor-agnostic **seed-quality
screening** platform. V1 is a phone app (camera + macro lens + classical
computer vision + a classical ML model). Every screen, data model and
service is written against a `SpectralDevice` interface so a physical NIR
spectroscope can be added over BLE later without touching the vision
pipeline, DB schema or UI.

Built by **Abdullah Jawed** from his own **"Master Build Prompt"** — an 80-section
spec. Code comments cite it as `§NN` (key ones: §15 class list, §43 model
roadmap V0–V6, §66 scientific-claims discipline, §67 hackathon
MUST/SHOULD/FUTURE, §71 fusion, §8/§10 capture guidance).

### Where everything lives

| | |
|---|---|
| **Project home** | `E:\AgriSpectra AI-NIR\` (Windows) |
| **Git repo** | `E:\AgriSpectra AI-NIR\AgriSpectra\` → [github.com/Abdullah-Jawed-05/AgriSpectra-NIR](https://github.com/Abdullah-Jawed-05/AgriSpectra-NIR), branch `main` = source of truth |
| **Datasets** (not in git) | `Datasets/` — `Barley Dataset` (158, lot1, white paper), `Barley Dataset V2` / `V2.2` (blue mat, textured), `Barley Dataset v3` (`Front Split` 10 + `Batch` 16, white paper), `Wheat Scan` (109, unlabelled, mixed bg) |
| **Prebuilt APKs** | `Prebuilt APK/` |
| **Submission docs** | `Submission/` — Project Overview / Demo Script / Project Summary `.docx` |
| **Master Build Prompt** | `Master Build Prompt/` (`.docx`, §15 updated to barley taxonomy) |
| **Memory (2 copies, keep synced)** | `C:\Users\abdul\Downloads\Claude Work\.claude\projects\C--Users-abdul-Downloads\memory\` and `E:\AgriSpectra AI-NIR\memory\` |

### Stack

Flutter 3.47 / Dart 3.13 (`app/`), Riverpod (DI), `sqflite` raw SQL
(`app/lib/database/`), pure-Dart classical CV (`app/lib/ml/`), `pdf` +
`printing`, `share_plus`, `camera`, `flutter_blue_plus` (future NIR).
Python 3.11+ training pipeline (`ml/` — scikit-learn, LightGBM, OpenCV,
pandas). Android toolchain: AGP 9.1 / Gradle 9.3 / Kotlin 2.4.

---

## 2. Current state (2026-09-08)

**The app is complete, builds, and has been tested on a real Android
device — capture, quality gate, segmentation, per-seed + batch scoring,
explanations, history, PDF export, and the in-app data-collection flow all
work offline. 64 tests pass, `flutter analyze` clean.**

### What's real vs. rule-engine vs. simulated

- **Real & working:** the whole app pipeline and UI.
- **Model V0 (ships):** a hand-tuned **rule engine**, not trained. It emits
  only `good` / `damaged` (on `darkRegionRatio > 0.22` — dark/discoloured
  regions) plus batch-relative `impurities` (foreign matter). It does
  **not** detect cracks, shrivel or breakage. All other rules were
  removed as miscalibrated for barley (see changelog).
- **Model V1 (built, NOT wired in):** does not generalise across
  collection sessions (macro-F1 ~0.1, ROC-AUC ~0.5). Would be worse than
  V0. Full analysis in `docs/VALIDATION.md`.
- **NIR:** no hardware exists. `SimulatedNIRDevice` produces
  clearly-labelled synthetic spectra. `BluetoothNIRDevice` is wired but
  untested (no firmware).

### Taxonomy (barley only, §15)

`QualityClass = { good, damaged, broken, shriveled, impurities, unknown }`.
`impurities` = foreign matter — excluded from batch quality stats, reported
as `impurityCount` / `purityRatio` instead. `Crop = { barley }` (one-item
selector kept as the seam for future crops). Storage keys are uppercase
(`GOOD`, `DAMAGED`, …).

### The #1 blocker: data

Everything ML hinges on **one clean multi-session barley dataset**: plain
white **matte paper**, **10–50 seeds spread in a single layer (not
touching)** per frame, sorted into `good / damaged / broken / shriveled /
impurities` folders. Then: `prepare_dataset.py` → `split_dataset.py` →
`train_baseline.py` → `evaluate_model.py`, and re-run the cross-session
test in `docs/VALIDATION.md` before V1 is allowed into the app.

Every existing barley set fails one of: textured background (V2/V2.2 blue
mat), single-seed macro shots (all), or unlabelled (wheat). v3 `Front
Split` is the right style but only 10 grains and one class.

---

## 3. Complete changelog

Commits are on `main`. Read newest-first for "what's the latest thinking".

### Session 2026-09-08 — vision quality overhaul (from `Barley Dataset v3`)

Abdullah's feedback after device testing: app works, but vision results
wrong — natural furrow called "damage", impurities shown as a seed corner,
shadows flagged, piled batches misclassified. All fixed (commits
`00c7c8c` → `109aa1a`):

- **Dropped the `crackLikeEdgeRatio` rule.** It fired on barley's natural
  ventral furrow / husk venation — healthy ventral-side grains score
  ~0.47 edge density, *higher* than damaged (~0.20). Edge density tracks
  which face is up, not damage. V0 is now `darkRegionRatio > 0.22` alone.
- **Segmentation now thresholds on CIE-Lab chroma, not luminance.**
  `seed_finder.dart::find` / `segmentation.py::segment`. A light-tan grain
  on white paper is barely darker than the paper (luminance fg fraction
  ~0.78 — useless) but is clearly more *coloured*; a cast shadow is the
  paper's colour just darker, so it falls below the chroma threshold.
  Luminance (`lum_dark`) is a fallback for near-greyscale frames (peak
  chroma < 3) / very dark seeds. Hand-rolled 3×3 morph open+close.
  Parity verified on a real grain (area 4809 vs 4817, all features ~2%).
- **Shadow + fragment rejection** (chroma channel only): drop a blob whose
  mean chroma < 4 (shadow), or whose area < 0.4× the batch median (furrow
  line / speck).
- **Pile detection.** A big seed-coloured blob rejected as oversize
  (> 5% of frame) ⇒ `SegmentationResult.piled` / `lastLayoutPiled`. The
  app **stops the scan** with "spread the seeds into a single layer, then
  rescan"; `prepare_dataset.py` skips the image.
- **`ImpurityDetector` needs a colour signal.** Foreign matter = size/shape
  outlier **AND** colour outlier (Lab a*/b* distance from batch median),
  or a strong colour outlier alone. A big/bent *barley* grain isn't
  flagged; nor is a segmentation fragment.
- **Result screen shows classes vividly.** Colour-coded count chips under
  the score, seed grid split into a labelled section per class, class-
  colour bar on each `SeedCard`. `impurities` → "Non-seed" in the result
  view. Shared `qualityClassColor` / `qualityClassResultLabel` in
  `badges.dart`.
- Capture-guide text now says "spread in a single layer, plain paper".
- `docs/HACKATHON_DEMO.md` de-staled (was "web-only, no Android SDK").
- `analyze_capture_set.py` reports `piled` / `channel`.
- Test fixtures switched to single-offset-per-pixel jitter (grey stays
  grey so the chroma channel defers to luminance).

### Session 2026-09-07 — app hardening + two device bugs (`938e69c` → `e212b8b`)

- **APK builds again.** `flutter build apk` failed at
  `:share_plus:compileDebugKotlin` — pub cache on `C:`, project on `E:`,
  Kotlin's incremental compiler can't relativize across drives. Fix:
  `kotlin.incremental=false` in `app/android/gradle.properties`.
- **Background-texture gate.** `image_quality_gate.dart::_tileTextureStats`
  + `segmentation.py::assess_background_texture`. 48px-tile Laplacian pass;
  hard-reject when median tile std-dev > 3.2 or busy-tile ratio > 0.80.
  0 false-reject on 158 clean, ~97% of 270 textured caught. `textureScore`
  added to `ImageQualityReport`.
- **V0 first re-tune** (later superseded on 09-08): removed the shape rule
  (barley is elongated → everything → `shriveled`), the inverted
  discoloration rule, the no-signal hole rule.
- **Touching-seed splitter** (`seed_splitter.dart` / `seed_splitter.py`,
  §11). Marker Voronoi partition (chamfer distance transform → relative
  regional maxima, 16px min separation → multi-source BFS) — NOT
  `cv2.watershed` (chosen for cross-language determinism). Parity enforced
  by `seed_splitter_parity_test.dart` + `gen_splitter_parity_fixture.py`.
- **Tests 24 → 58**: `rule_classifier_test`, `image_quality_gate_test`,
  `seed_splitter_test` (+ parity), `nir/fusion_engine_test`,
  `nir/nir_quality_test`, `application/scan_orchestrator_test` (Scan
  round-trip through in-memory DB), `database/migration_test`,
  `test/support/fixtures.dart`.
- **Two device bugs fixed** (`3be8c4b`, `e212b8b`):
  1. *Results never generated / History showed "appDatabaseProvider must
     be overridden in main()".* `main.dart` nested a root `ProviderScope`
     inside the override scope → `scanRepositoryProvider` (no
     `dependencies`) was hosted in the root and read the throwing default
     `appDatabaseProvider`. Now `_Bootstrap` builds the *only* scope, keyed
     per state.
  2. *"Preparing results…" hung forever.* `scan_flow_screen` passed an
     `async` closure to `Result.when`'s `ok:` — the save Future was never
     awaited or caught. Save is now awaited outside `when()` with its own
     catch → real "analysis failed" panel.
  Plus a scrollable `ErrorState` widget for async error branches.
  `test/core/providers_test.dart` + `AppDatabase.forTesting` cover the DB
  provider path (had zero coverage — nobody had run the app end-to-end).
- **Web smoke-test inconclusive** — `flutter build web` compiles, but the
  in-app browser pane won't render + `sqflite_common_ffi_web` worker
  fails. Not Android-relevant. `app/tool/serve_web_build.py` added.

### Session 2026-09-05/06 — earlier work

- **Barley-only taxonomy refactor** across all layers + Master Build
  Prompt `.docx` §15.
- **Python↔Dart feature parity** — was badly broken (different
  perimeter/ellipse/edge/hole algorithms; a real production bug where
  `img.grayscale()` mutated its argument in place, silently desaturating
  every colour feature since the MVP). Fixed; `docs/ML_PIPELINE.md` §3.
- **`_normaliseLighting`** (gray-world WB + exposure pull), Dart + Python.
- **Model V1 first trained** — then the cross-session test showed it
  doesn't generalise (see `docs/VALIDATION.md`).
- **Data augmentation** (`ml/scripts/augment_dataset.py`) — didn't help on
  the tiny single-session set; kept as correct infra.
- **"Make Our App Better"** (home screen, §44): every scan's seeds save
  `verified_label = NULL`; the screen lets anyone confirm/correct the
  model's guess later; **Export** zips verified seeds into
  `<crop>/app_YYYY-MM-DD/<LABEL>/*.png` (= `prepare_dataset.py` layout)
  and hands it to the OS share sheet. DB schema v1→v2.
- **PDF report export** (`scan_report_pdf.dart`) — "Save Report" button,
  on demand only, via `Printing.sharePdf`.
- **Evidence-factor persistence** bug fixed (the "why this score" card was
  empty when reopening a scan from History).
- **Brand** — a seed-silhouette + scan-band mark, drawn by hand 3× in a
  Flutter `CustomPainter` (`agrispectra_mark.dart`), `PdfGraphics`, and
  PIL (`assets/icon/generate_icon.py` → `flutter_launcher_icons`).

### In progress / parallel

- **NIR fusion calibration-weighting fix** — a side session committed
  `16f4616` ("Gate NIR confidence on calibration validity
  multiplicatively") on a **branch, not merged to `main`**. An expired
  NIR calibration with a clean signal still drags a confident visual
  score ~30 pts because `calibrationValidity` is only 0.4 of the NIR
  confidence weight (§71 says it should gate it). Cosmetic; merge later.

---

## 4. Key files

### App (`app/lib/`)

| File | What |
|---|---|
| `main.dart` | Bootstrap — `_Bootstrap` builds the only `ProviderScope`, keyed per state. Do not nest scopes. |
| `core/providers.dart` | `appDatabaseProvider` (throws until overridden), `scanRepositoryProvider`, `unverifiedSeedCountProvider` |
| `ml/vision_pipeline.dart` | `runVisionPipeline` — the CPU pipeline, runs via `compute()` on an isolate. Early-returns on: unusable quality, no seeds, **piled**. |
| `ml/image_quality_gate.dart` | blur / exposure / glare / background / **texture** / resolution. `_tileTextureStats`. |
| `ml/seed_finder.dart` | `ClassicalCVSeedFinder` — chroma-based segmentation, `_chromaField`, `_thresholdAbove`, `_morphClean`, `_labelBinary`, shadow/fragment/pile logic, `lastChannel` / `lastLayoutPiled`. |
| `ml/seed_splitter.dart` | `SeedSplitter` — marker Voronoi split of touching-seed blobs. |
| `ml/feature_extractor.dart` | per-seed features; `_rgbToLab` / `_rgbToHsv` (float precision, parity source of truth). |
| `ml/rule_classifier.dart` | Model V0 — `darkRegionRatio > 0.22` → damaged, else good. Nothing else. |
| `ml/impurity_detector.dart` | batch-relative size/shape **+ colour** outlier → `impurities`. |
| `ml/batch_engine.dart` | aggregates per-seed → `BatchStatistics` (excludes impurities from quality; `purityRatio` / `impurityCount`). |
| `nir/` | `SpectralDevice` interface, `NoNIRDevice`, `SimulatedNIRDevice`, `BluetoothNIRDevice`, `FusionEngine`, `NirQualityScorer` |
| `application/scan_orchestrator.dart` | wires the pipeline + NIR + fusion + Scan assembly. NIR failure mid-scan must not abort (§36/§58). |
| `presentation/screens/` | `home`, `crop_selection`, `scan_flow`, `result`, `seed_detail`, `history`, `improve_app` ("Make Our App Better"), `nir_device`, `settings` |
| `database/app_database.dart` | schema v2, `_migrations` (additive only), `createSchemaForTesting`, `forTesting`, `migrationsForTesting` |

### ML (`ml/`)

| File | What |
|---|---|
| `preprocessing/segmentation.py` | `segment()` (returns `SegmentationResult`), `find_seeds()` (back-compat), `assess_background_texture()`, `_normalise_lighting()`, `pick_primary_seed()`, `geometry_from_mask()` — **must stay parity-identical to `seed_finder.dart`** |
| `preprocessing/features.py` | `extract_all()`, `_rgb_to_lab` / `_rgb_to_hsv` (numpy ports of the Dart formulas) |
| `preprocessing/seed_splitter.py` | mirror of `seed_splitter.dart` |
| `scripts/prepare_dataset.py` | `raw/<crop>/[<batch>/]<label>/*.jpg` → `features.csv` + crops. Skips textured + piled. `--one-seed`, `--allow-textured-bg` |
| `scripts/split_dataset.py` | group-aware split, `--test-batch <id>`, reports `test_leakage_safe` / `val_leakage_safe` |
| `scripts/train_baseline.py` / `evaluate_model.py` | LightGBM; `NON_FEATURE_COLUMNS` drops absolute-pixel geometry |
| `scripts/augment_dataset.py` | run after split on `train.csv` only |
| `scripts/analyze_capture_set.py` | **triage a raw capture folder** — texture / piled / no-seed / feature ranges. Run this on any new dataset first. |
| `scripts/gen_splitter_parity_fixture.py` | regenerate `app/test/ml/fixtures/seed_splitter_parity.json` when either splitter changes |
| `scripts/parity_check.py` + `app/test/tool/parity_check_dev.dart` | run both pipelines on one image, diff features by hand |

### Docs (`docs/`)

`ARCHITECTURE.md` (system map), `VALIDATION.md` (**the honest-status doc —
read this**), `ML_PIPELINE.md` (parity + what each stage does),
`ROADMAP.md`, `DATASET_GUIDE.md`, `HACKATHON_DEMO.md`.

---

## 5. How to resume

```bash
cd "E:/AgriSpectra AI-NIR/AgriSpectra"
git pull

# App
cd app
flutter pub get
flutter test                 # expect all green
flutter analyze              # expect clean
flutter build apk --release --split-per-abi

# ML (only if working on training)
cd ../ml
python -m pip install -r requirements.txt   # or: opencv-python numpy pandas scikit-learn lightgbm
python scripts/analyze_capture_set.py --dir "<new dataset>" --out out/triage
```

Python interpreter that has the ML deps in this environment:
`/c/Users/abdul/AppData/Local/Python/bin/python` (3.14). `node` / `pandoc`
/ LibreOffice are **not** installed. `python-docx` was pip-installed.

### Standing instructions from Abdullah

- **Prioritise quality/correctness over speed or token cost** — "don't
  cheap out on resources". If the better fix is more work, do it.
- **Push to `main` after each finished step** — don't ask each time.
- **Whatever works better wins**, even if it's more work.
- End git commit messages with:
  `Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>`
- End PR descriptions with:
  `🤖 Generated with [Claude Code](https://claude.com/claude-code)`
- Keep the **two memory copies** in sync.
- §66 discipline: the app reports "visual quality characteristics that may
  correlate with quality", never "detects X". Keep UI copy, report text
  and docs honest — `docs/VALIDATION.md` is the source of truth for what's
  been checked.

---

## 6. Open items / next steps (priority order)

1. **Collect a clean multi-session barley dataset** (see §2 blocker) →
   `prepare_dataset.py` → `split_dataset.py --test-batch` → `train_baseline`
   → re-run the cross-session test in `docs/VALIDATION.md`. Only wire V1
   into the app (`vision_pipeline.dart`) if it beats V0 on held-out data.
2. **Merge the NIR calibration-weighting fix** (`16f4616`) after reviewing
   it; update the two bound assertions in `nir/fusion_engine_test.dart`
   that currently pin the old behaviour.
3. **A learned detector (YOLO / similar)** for dense piles — classical CV
   can't segment ~40 overlapping grains. `SeedFinder` is an interface;
   swap `ClassicalCVSeedFinder` without touching anything downstream of
   `SegmentedSeed` (§11).
4. **Widget render tests** for `result` / `seed_detail` / `improve_app`
   screens (only a theme smoke test today) + one true capture→result
   end-to-end.
5. **Second crop** — only post-barley-V1. Candidate data:
   [Roboflow "seed"](https://universe.roboflow.com/projects-vclkw/seed-qysqx)
   (CC BY 4.0, ~7.7k imgs, bbox, Good/Bad × 4 non-barley crops — needs
   real adaptation, not a drop-in). Noted in `docs/ROADMAP.md`.
6. **Physical NIR prototype** (ESP32 + AS7265x) against
   `nir_protocol/protocol.md` → `BluetoothNIRDevice`.

## 7. Do NOT redo

- Don't re-derive the Python↔Dart parity fixes — they're done and tested.
- Don't reintroduce the crack/shape/discoloration/hole rules to V0 — each
  was checked against real barley and removed for cause.
- Don't segment on luminance — chroma is deliberate.
- Don't nest `ProviderScope`s in `main.dart`.
- Don't wire Model V1 into the app until the cross-session test passes.
- Don't claim the classifier is trained, or that NIR is real.

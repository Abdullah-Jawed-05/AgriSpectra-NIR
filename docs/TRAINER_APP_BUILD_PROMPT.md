# Build prompt: "AgriSpectra Trainer" — offline, gamified seed-labelling + model-training desktop app

*Copy everything below this line into another LLM (e.g. in a fresh chat or
an agentic coding tool) to have it build the app. It is self-contained —
the builder does not need access to the AgriSpectra repo, though having
it helps. Written 2026-10-02.*

---

## 0. Who you are building this for, and why

You are building a **companion desktop tool** for a mobile app called
**AgriSpectra** — a Flutter app that screens barley seeds for visible
quality from a phone photo. AgriSpectra's on-device classifier is
currently a hand-tuned rule engine (not learned). Upgrading it to a
trained model requires a labelled dataset, and **labelling and running
the training pipeline today means asking an AI coding assistant to do it
by hand, every single time** — slow, not repeatable without that
assistant, and not something the project owner can do on his own
schedule.

**Your job**: build a **standalone, offline, Windows desktop GUI
application** that lets the project owner (a non-ML-engineer who knows
the problem domain, not the codebase) (1) sort raw seed photos into
quality classes quickly and enjoyably, and (2) run the existing training
pipeline on that sorted data, entirely on his own machine, with no cloud
dependency and no AI assistant required at runtime. The existing Python
training pipeline (described in full below) is **correct and already
proven** — your app **wraps and orchestrates it**; it does not reimplement
seed detection, feature extraction, or model training from scratch.

Treat this as a real product brief, not a toy. Build it completely:
error handling, a settings screen, sensible empty states, and the ability
to recover from a crash mid-run. The user will run this unattended for
long stretches (sorting hundreds of photos, training runs that take
minutes), so it must never lose work.

---

## 1. Context: what AgriSpectra is

AgriSpectra is a phone-camera app that screens a batch of barley seeds
(10–50 at a time, spread on plain paper) for visible quality in a few
seconds, fully offline. The user photographs the seeds; the app segments
each one, scores it, and rolls the batch into a summary (average score,
uniformity, anomaly count, batch purity, confidence).

**Taxonomy** (barley only, for now — this is a closed, fixed list, do not
invent new classes):

| Class | Storage key | Meaning |
|---|---|---|
| Good | `GOOD` | Healthy, undamaged grain |
| Damaged | `DAMAGED` | Dark/discoloured regions, mould, rot |
| Broken | `BROKEN` | Physically fragmented |
| Shriveled | `SHRIVELED` | Shrunken, underdeveloped |
| Impurities | `IMPURITIES` | Foreign matter — not a seed at all (stones, chaff, stems, other-crop seeds) |
| Unknown | `UNKNOWN` | Fallback only — never a deliberate label a human assigns |

The on-device classifier today (Model V0) is a rule engine that only
distinguishes `GOOD` vs `DAMAGED` on one signal (dark/discoloured surface
area). It was deliberately stripped down after testing showed every other
heuristic (shape, discoloration, edge density) was unreliable or actively
wrong for barley. A **trained model (Model V1)** exists in prototype but
isn't shipped yet because it doesn't generalise across photo sessions —
more, better-labelled data is the fix, which is the entire reason this
tool needs to exist.

**Brand / visual identity** (reuse this — the tool should feel like a
sibling of the phone app, not a bolted-on alien tool):

- Primary accent (teal): `#0E6E5D`, muted accent: `#DCEEE9`
- Ink/text: `#171E1B`, faint/secondary text: `#8B968F`
- Surface: off-white `#FFFFFF` / `#EFF2F0`
- Class colours (use these exact hues for the exact same classes,
  everywhere in your app — the phone app uses this mapping and it should
  match): Good = `#1B7A4C` (green), Damaged/Shriveled = `#B07A12`
  (amber), Broken = `#B0401E` (red-orange), Impurities/Unknown = `#8B968F`
  (neutral grey)
- The app's mark is a simple seed silhouette with a horizontal "scan
  band" cut across it — a tall, slightly-elongated rounded teardrop /
  grain shape in teal, with a lighter horizontal stripe. Recreate a
  simplified version of this as your app's icon/wordmark; don't invent an
  unrelated logo.
- Typography: clean geometric/humanist sans (Calibri or a similar
  freely-licensed equivalent — Inter, Source Sans, or system default are
  all fine), no decorative fonts.
- Tone: calm, precise, a little scientific — not cartoonish. "Gamified"
  here means *satisfying and fast*, not childish. Think the feel of
  Duolingo's streaks/progress or a well-made onboarding flow, applied to
  a serious agri-tech tool — not confetti and cartoon mascots.

---

## 2. The existing Python ML pipeline you are wrapping

This pipeline already exists, is tested, and is **the source of truth**.
Do not rewrite the computer-vision or training logic — call these scripts
(or their functions) as-is. If the builder doesn't have the actual repo,
reimplement each script's *documented behaviour* faithfully from the spec
below, but structure your app so swapping in the real scripts later is a
one-line change (one `subprocess` call target per stage, or one import
per stage — see §7).

### Stage 1 — `prepare_dataset.py`: raw photos → a feature table

```
python prepare_dataset.py --raw-dir <folder> --out <folder> [--one-seed] [--allow-textured-bg]
```

- **Input layout** (`--raw-dir`), two accepted forms, auto-detected:
  - 3-level (preferred): `raw/<crop>/<batch_id>/<LABEL>/*.jpg` — a
    "batch" is one real-world collection session (one day, one lighting
    setup). This matters a lot: the training/validation/test split is
    done *by batch*, not randomly, so near-duplicate seeds from one photo
    session never leak across the split.
  - 2-level (fallback): `raw/<crop>/<LABEL>/*.jpg` — everything is
    treated as one implicit batch.
  - `<crop>` today is always `barley`.
  - `<LABEL>` must be one of `GOOD, DAMAGED, BROKEN, SHRIVELED,
    IMPURITIES, UNKNOWN` (case-insensitive, spaces/hyphens normalised to
    underscores — "Shell Free" → "SHELL_FREE" would be rejected; only the
    six above are valid). Unrecognised label folders are skipped with a
    warning, not an error.
- **For each image**, the script:
  1. Runs a **background-texture check** (`assess_background_texture`) —
     rejects (skips, with a printed warning) any photo shot on a woven
     mat, fabric, wood grain, or otherwise textured surface, unless
     `--allow-textured-bg` is passed. This matters enormously — an
     earlier real dataset got ruined this way (see §10).
  2. Runs seed **segmentation** (`segment()`): finds every seed-like blob
     in the photo using colour-based thresholding (not brightness —
     deliberately, see §10), splits touching seeds apart, and rejects the
     photo outright if the seeds are piled up / touching in a way that
     can't be reliably separated (`result.piled`), again unless the
     caller opts out.
  3. Extracts a fixed feature vector **per detected seed** (see exact
     column list below).
  4. Writes one row per seed to `features.csv`, plus the seed's cropped
     image and its binary mask to `crops/` and `masks/`.
- **`--one-seed`**: for a photo known to contain exactly one seed (a
  macro shot), keep only the one blob that looks like the actual subject
  and discard the rest (background noise). Your Sort Mode (§5) will
  usually *not* need this flag, because it already shows the user one
  seed crop at a time after segmentation — but support it for bulk
  command-line use.
- **Output**: `features.csv` with these exact columns (do not rename or
  reorder — anything downstream, including the eventual mobile app,
  depends on exact column names):

  ```
  crop, batch_id, source_image, seed_id, crop_image_file, mask_file, label,
  area_px, perimeter_px, width_px, length_px, aspect_ratio, circularity,
  eccentricity, convexity,
  mean_r, mean_g, mean_b, mean_hue, mean_saturation, mean_value,
  mean_lab_l, mean_lab_a, mean_lab_b, color_variance_rgb, discoloration_ratio,
  edge_density, entropy, surface_irregularity, local_contrast,
  dark_region_ratio, crack_like_edge_ratio, hole_ratio, abnormal_pigmentation_score
  ```

  (`crop, batch_id, source_image, seed_id, crop_image_file, mask_file,
  label` are identifiers/metadata, not model features; `area_px,
  perimeter_px, width_px, length_px` are excluded from training too —
  they're absolute-pixel measurements that encode camera framing, not
  seed shape. The scale-invariant ones — `aspect_ratio, circularity,
  eccentricity, convexity` — are kept. The remaining ~20 columns are the
  real feature set a model trains on.)

### Stage 2 — `split_dataset.py`: feature table → train/val/test

```
python split_dataset.py --features features.csv --out <folder> [--test-fraction 0.2] [--val-fraction 0.15] [--seed 42] [--test-batch <batch_id>]
```

- Splits **by `batch_id`** whenever ≥2 batches exist (so test data is a
  genuinely held-out photo session, never near-duplicate seeds from the
  same shoot as training data). Falls back to a stratified *row* split
  only when there's just one batch, and flags that fallback as
  leakage-unsafe in its output summary.
- `--test-batch <id>`: force a specific batch to be the test set (useful
  for "always test on the most recent session").
- Output: `train.csv`, `val.csv`, `test.csv`, and a `split_summary.json`
  reporting `test_leakage_safe` / `val_leakage_safe` booleans — **surface
  these booleans prominently in your UI**; this is exactly the kind of
  thing that silently invalidates a training run.

### Stage 3 — `train_baseline.py`: train the model

```
python train_baseline.py --train train.csv --val val.csv --out <folder> [--model lightgbm|random_forest]
```

- Trains either a LightGBM `LGBMClassifier` or a scikit-learn
  `RandomForestClassifier` on the feature columns (excluding the
  metadata/non-feature columns listed above), encoding `label` with a
  `LabelEncoder`. `--model` chooses which; without it, the script
  defaults to `lightgbm` when the package is installed and falls back to
  `random_forest` otherwise — so the artifact's actual type depends on
  the training environment, not just the code. Don't assume one or the
  other; read `model.joblib`'s type (or `training_metadata.json`) before
  writing any code that only handles one.
- Writes to `--out`: `model.joblib` (the trained model), `label_classes.json`
  (the label encoder's class order), `feature_columns.json` (the exact
  ordered feature-column list the model expects), `training_metadata.json`
  (accuracy metrics, training timestamp, row counts).

### Stage 4 — `evaluate_model.py`: score it on held-out data

```
python evaluate_model.py --model <folder from stage 3> --test test.csv --out <folder>
```

- Loads the model, runs it on `test.csv`, writes a confusion matrix and
  per-class precision/recall/F1 plus macro-F1 and balanced accuracy.

### Also available (call these too, where it makes sense)

- `analyze_capture_set.py --dir <folder> --out <folder> [--save-crops]` —
  triage a raw folder of photos *before* committing to labelling it:
  reports how many are texture-rejected, piled, unsegmentable, and the
  feature-value ranges on the ones that are usable. **Run this
  automatically** whenever the user imports a new batch of raw photos, and
  show the result before they start sorting — don't make them label 200
  photos only to discover half were unusable.
- `augment_dataset.py` — light augmentation (rotation/flip/brightness) on
  `train.csv` only, run after the split, never before (to avoid leaking
  augmented near-duplicates into val/test).
- `generate_confusion_matrix.py` — a plotting helper for stage 4's output.

---

## 3. The actual product: two modes, one app

Build this as two clear modes plus a results/history view, not one
undifferentiated screen:

### Mode A — **Sort** (the part that should feel like a game)

This is the actual bottleneck this whole tool exists to solve, and it's
where the "almost like a game" feel matters most. The project owner has
raw photos (could be single-seed macro shots or multi-seed batch
photos — handle both). Sort Mode:

1. **Import**: drag-and-drop a folder of photos (or individual files) in.
   Immediately run `analyze_capture_set.py`-equivalent triage in the
   background and show a quick summary *before* sorting begins: "214
   photos imported · 198 usable · 12 rejected (textured background) · 4
   rejected (seeds piled up)". Rejected photos get a clear reason and are
   set aside, not silently dropped — let the user see them and decide
   (re-shoot, or override and keep anyway).
2. **Segment**: for each usable photo, run the real segmentation and
   produce one or more seed crops (exactly what `prepare_dataset.py`
   would produce). Build a queue of **individual seed crops** to label,
   not whole photos — a 30-seed batch photo becomes 30 small sorting
   decisions, each fast.
3. **Sort loop** (the core interaction): show one seed crop at a time,
   large, centered, with the six class buttons (or keyboard shortcuts —
   this matters a lot for speed: 1–6 or similar) laid out clearly,
   colour-coded per §1's palette. The user picks a class with a single
   click or keypress; the crop is instantly filed and the next one
   appears — no modal, no confirmation dialog, no page reload. Support
   an "undo last" (single keystroke) for mis-clicks.
4. **Smart pre-suggestion**: run the *existing* V0 rule (dark-region-ratio
   → damaged, else good — a single, simple threshold check already
   defined in the pipeline) against each crop's extracted features and
   **pre-highlight** the suggested button. The user then just confirms
   (one tap/keystroke) or overrides. This alone should roughly double
   sorting speed on the common case. Never auto-file without the human's
   explicit action — a suggestion is not a label.
5. **Momentum, not gimmicks**: a running session counter, a small
   progress bar toward the next natural milestone (e.g. "40 more seeds →
   enough for a training run"), a lightweight streak indicator for
   consecutive sorting sessions, and a lightweight, tasteful transition
   /micro-animation on each sort (e.g. the crop flies into a coloured
   bin, or a soft colour-flash) — fast, satisfying, never blocking input.
   No points/leaderboards/sound effects unless they're easy to mute; this
   is a tool the user may run for 30+ minutes at a stretch, so avoid
   anything that gets annoying on repetition.
6. **Batch awareness**: every Sort session is one `batch_id` (default:
   today's date + an auto-incrementing suffix if more than one session
   happens in a day, editable by the user). This is what makes the
   eventual train/test split leakage-safe — don't let the user skip or
   hide this concept, but don't make them think about it either; just
   handle it correctly by default and show it quietly in a corner.
7. **Output**: writes directly to the `raw/<crop>/<batch_id>/<LABEL>/`
   folder structure Stage 1 expects. The user can close the app mid-sort
   and resume later without losing anything — persist state (what's been
   sorted, what's left in the queue) continuously, not just on exit.
8. A **review/fix-up list** per session: a filmstrip of everything sorted
   this session, grouped by class, so the user can scan for an obvious
   mis-click before moving on (click to re-file). This is the same idea
   as the phone app's own "Make Our App Better" review screen — this
   desktop tool is effectively a faster, offline, power-user version of
   that screen, and should feel familiar if someone has used both.

### Mode B — **Train**

Takes however much labelled data exists (across all sessions/batches in
the configured raw-data root — not just today's) and runs it through
Stages 1–4 of the real pipeline, with a visible pipeline view:

1. **Pre-flight**: before running anything, show a summary of what's
   about to be trained on — total labelled seeds per class (flag badly
   imbalanced classes, e.g. 400 Good vs 8 Broken, with a plain-language
   note, not just a number), number of distinct batches (flag if there's
   only 1 — the split will not be leakage-safe and the resulting metrics
   will be overly optimistic; say so plainly, the way this project's own
   validation docs do), and an estimated run time.
2. **Run**, with each of the four stages shown as a step in a visible
   pipeline (think a clean progress-stepper UI, not a spinning wheel):
   Prepare → Split → Train → Evaluate. Each step shows live log output
   from the underlying script in a collapsible panel (don't just show a
   generic "working…" — real users of this tool will want to see "412/600
   images processed, 14 skipped: textured background" scroll past) and a
   determinate progress bar where the underlying script supports it.
3. **Results dashboard** at the end: overall accuracy/macro-F1/balanced
   accuracy, a confusion matrix (rendered as an actual heatmap grid, not
   a wall of numbers), per-class precision/recall, and — critically —
   whether this run's test set was leakage-safe (`split_summary.json`).
   Compare this run's headline metric against the *previous best run* and
   show the delta clearly (up/down, with colour) — this comparison is the
   single most motivating thing in the whole app; make it prominent.
4. **History**: every run is saved (its metrics, its model artifact, the
   dataset snapshot it trained on) and browsable later, so the user can
   see progress over weeks, not just the latest run.
5. A clearly-separated, **not automatic**, "Promote this model" action
   (see §4) — never silently overwrite what the phone app uses.

### Shared chrome

- A persistent small status strip: total labelled seeds in the library,
  per class, with the class colours from §1. This is the "home base" view
  and should also be the app's landing screen.
- Settings: where the raw-data root lives on disk, where trained-model
  output goes, path to the Python interpreter / pipeline scripts if not
  bundled (see §7).

---

## 4. The "Promote to App" step — read this carefully, it's the trickiest part

The trained model from Stage 3 (`model.joblib`, either a LightGBM
`LGBMClassifier` or a scikit-learn `RandomForestClassifier` — see §2's
note on `train_baseline.py --model`) **cannot be loaded directly by the
Flutter app** — Flutter/Dart has no Python runtime and no joblib/pickle
reader. There is currently **no deployment path from a trained model to
the phone app at all**; building one is implicitly part of this tool's
job, because "the model learns from it" has to eventually mean the phone
app gets smarter, not just that a file sits on a laptop.

**Recommended approach**: use **model-to-code generation**, specifically
the `m2cgen` Python library (`pip install m2cgen`), which converts a
trained model directly into standalone source code in a target language
with **zero runtime dependencies** — it supports both LightGBM and
scikit-learn models, and Dart as an output language, so the same export
call works regardless of which model type Stage 3 produced. Concretely,
your "Promote to App" action should:

1. Run `m2cgen.export_to_dart(model)` (or equivalent) on the trained
   model — whichever type it is — to produce a `.dart` file containing
   the decision logic as plain functions/arrays — no ML library needed at
   runtime in the app. Only fall back to hand-written tree introspection
   (e.g. for a scikit-learn forest via `estimator.tree_`) if `m2cgen`
   itself fails for a given model type.
2. Wrap that generated file with a small, clearly-marked adapter that:
   - Takes the app's existing per-seed feature object (the Dart app
     already computes every one of the feature-column names from §2,
     Stage 1, via its own `FeatureExtractor` — the ordering and naming
     must match `feature_columns.json` from the trained model **exactly**,
     field-for-field) and builds the numeric feature vector in that exact
     order.
   - Calls the generated prediction function.
   - Maps the numeric class index back to a label using
     `label_classes.json`'s exact ordering.
3. Write the generated file + adapter to a clearly-named output folder
   (e.g. `export/trained_model_v1/`) — **do not** try to auto-detect or
   auto-modify a Flutter project's source tree. Copying the file into the
   app, and wiring it into the app's prediction pipeline, is a deliberate
   decision the project owner (or his AI assistant) makes separately,
   with the cross-session validation test in mind — never do this
   automatically as part of training.
4. Show the exact feature-column order and label order on screen when you
   do this, in copyable form — this is the one place a silent mismatch
   would cause the phone app to misclassify everything without any error,
   so make it impossible to miss.
5. If `m2cgen` doesn't support a feature this model ends up needing, the
   fallback is: dump the model with scikit-learn's own tree introspection
   (`model.estimators_[i].tree_`) and hand-generate equivalent nested
   `if/else` Dart yourself, one tree per estimator, majority-voted — this
   is more code but has the same zero-dependency property. Do not
   introduce a TFLite or ONNX runtime dependency for this model type —
   those export paths exist in this project already but are reserved for
   a *future* CNN-based model (Model V2), a different, much later phase;
   using them for a Random Forest is the wrong tool and will cost more
   time than it saves.

---

## 5. Technical architecture

- **Language/stack**: Python, since the entire pipeline you're wrapping
  is Python and the owner's machine already has the right Python
  environment and packages (opencv-python, numpy, pandas, scikit-learn,
  joblib) installed and working. Don't introduce a second language
  runtime (e.g. a JS/Electron frontend talking to a Python backend) —
  it roughly doubles packaging complexity for no real benefit here.
- **GUI framework** — recommended: **Flet** (`pip install flet`), a
  Python framework built on Flutter. This is a deliberate choice beyond
  "it's Python": it renders with the same engine as the phone app, so
  recreating AgriSpectra's visual language (the exact colours in §1,
  smooth transitions, a consistent "feel") is natural rather than fought
  against, and it packages to a single Windows executable
  (`flet pack` / `flet build windows`) that runs with no visible console,
  no separate install step, no "install Python first" friction for the
  end user. If Flet proves limiting for a specific interaction (e.g. very
  custom drag-and-drop), **PySide6** (Qt for Python) is the fallback —
  more mature, more verbose, also packages to a standalone `.exe`
  (PyInstaller).
- **Calling the pipeline — integration method**: wrap each of the four
  pipeline stages as a **subprocess call** to the real scripts
  (`subprocess.Popen` with `stdout=PIPE`, read line-by-line as it runs,
  parse the existing print statements each script already emits for
  progress/warnings) rather than trying to import and refactor them.
  This is deliberate: it guarantees **zero behavioural drift** from the
  exact, already-correct pipeline — you are never at risk of silently
  changing what "prepare" or "train" actually does while adapting it for
  GUI use. If real-time per-image progress (vs. per-stage) turns out to
  matter a lot for the Sort-mode feel, a *second*, independent
  integration path is fine: directly `import` and call
  `preprocessing.segmentation.segment()` for the live, interactive
  segmentation shown while sorting (read-only, feature-extraction only,
  never training) — but Stages 1–4 of actual *training* should stay
  subprocess calls to the unmodified scripts.
- **Data on disk**: don't invent a new database. The raw sorted photos,
  `features.csv`, split files, and trained-model folders are just files
  in a directory tree the user points the app at (defaulting to something
  sensible like `Documents/AgriSpectra Trainer/`). A small local SQLite
  file (via Python's built-in `sqlite3`) is fine for *app-only* state —
  sort-session history, run history, undo stack — but never as the
  source of truth for the actual dataset; that stays as plain files so it
  stays inspectable, portable, and compatible with the existing scripts
  being run by hand if ever needed.
- **Packaging**: ship as a single Windows `.exe` (via `flet build windows`
  or PyInstaller) that bundles Python + all dependencies, so the end user
  never runs `pip install` or opens a terminal. Bundle the pipeline
  scripts alongside it (or vendor the specific versions you tested
  against) so the tool is fully self-contained and versioned together.

---

## 6. Non-negotiables / do-not-do

- **Do not reimplement seed segmentation or feature extraction.** The
  exact numeric definitions in `ml/preprocessing/segmentation.py` and
  `ml/preprocessing/features.py` (colour-space math, edge thresholds,
  etc.) are deliberately kept bit-for-bit identical to a parallel Dart
  implementation in the phone app, verified by hand over many iterations.
  Any drift here — even a seemingly-equivalent rewrite — breaks that
  parity invisibly and makes a trained model behave differently on-device
  than during training. Call the existing code; don't rewrite it "more
  cleanly."
- **Do not silently relabel or auto-correct a human's sort decision.**
  Pre-suggestions are fine (§3); overwriting a confirmed label based on a
  model's own opinion is not.
- **Do not skip the texture/pile rejection, and do not hide it.** These
  checks exist because of a real, painful incident (an entire collection
  session had to be thrown out because it was shot on a textured mat that
  fragmented into dozens of false "seeds" — see §10). Surface rejections,
  don't suppress them, and let the user override deliberately rather than
  the tool guessing.
- **Do not claim a metric you haven't actually computed on a leakage-safe
  split.** If the split summary says `test_leakage_safe: false`, the
  results screen must say so plainly, not just show a clean-looking
  number. This project is deliberately strict about not overstating what
  a model can do — match that discipline.
- **Fully offline.** No network calls, no telemetry, no cloud sync. This
  runs on one person's laptop, on his own schedule, specifically *because*
  he can't always have an AI assistant available.
- **Never lose sorted data.** Write to disk incrementally (per sorted
  seed, not per session), and make the file layout itself the durable
  state — if the app crashes mid-sort, relaunching should resume exactly
  where it left off by reading what's already on disk.

---

## 7. Why this tool is needed right now (background, for your own judgement calls)

Two real collection sessions of barley photos exist. Training on one and
testing on the other — the only real test of whether a model generalises
— currently scores barely above random chance. The root cause, found by
inspecting the actual photos rather than only the metrics: one session
was shot on a textured surface that fragmented into dozens of
false "seeds" per photo, and both sessions were single-seed macro shots
rather than the realistic multi-seed batch photos the phone app actually
captures. The fixes for *that* are already in the pipeline you're
wrapping (lighting normalisation, colour-based segmentation, the
texture/pile rejection). What's left, and what this tool exists to make
sustainable, is simply **collecting and correctly labelling a proper
dataset** — plain background, seeds spread out, many sessions, many
photos — without that effort being bottlenecked on access to an AI coding
assistant for every round.

---

## 8. Definition of done

Build until all of the following are true:

1. A user can drop in a folder of raw barley photos and, within the app,
   sort every detected seed into one of the six classes using only mouse
   clicks or keyboard, with pre-suggestions, undo, and a visible running
   tally — no file-system or terminal interaction required.
2. Sorted data lands on disk in exactly the `raw/<crop>/<batch_id>/
   <LABEL>/*.jpg` layout `prepare_dataset.py` expects, with zero manual
   fixup needed.
3. A user can trigger a full Prepare → Split → Train → Evaluate run from
   the GUI, watch its progress, and see a results dashboard including a
   confusion matrix and a clear leakage-safety indicator, without ever
   opening a terminal.
4. Closing the app mid-sort or mid-run and reopening it does not lose
   data or leave the dataset in a broken state.
5. A trained model can be exported via "Promote to App" into a
   dependency-free Dart file plus the exact feature/label ordering
   needed to wire it up, with that ordering shown clearly on screen.
6. The whole thing runs with no network access and no terminal, start to
   finish, as a packaged Windows application.

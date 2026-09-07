# AgriSpectra — Executive Architecture

Status: living document. Version 0.1.0 — 2026-08-28.

## 1. What this is

AgriSpectra is a software-first, sensor-agnostic seed-quality screening platform.
V1 ships as a phone app: camera + macro lens + computer vision + a classical ML
model. Nothing about the app assumes that's all it will ever be — every screen,
data model, and service is written against a `SpectralDevice` interface so that
a physical NIR spectroscope can be plugged in later (BLE) without touching the
vision pipeline, the database schema, or the UI shell.

This document is the map. It intentionally does not contain code. Code lives
under `app/`, `ml/`, `nir_protocol/`, `simulator/`, and is explained in the
per-module docs listed in §9.

## 2. MVP definition (hackathon)

```
OPEN APP → SELECT CROP → CAPTURE SEED IMAGE → IMAGE QUALITY CHECK →
DETECT SEEDS → SEGMENT INDIVIDUAL SEEDS → ANALYZE EACH SEED →
CLASSIFY VISIBLE QUALITY → CALCULATE BATCH STATISTICS →
DISPLAY RESULT → SAVE SCAN
```

A batch is 10–50 seeds. Output: per-seed quality score + visual condition
label, batch average, uniformity %, anomaly count, confidence, and an
explanation ("why this score"). All of this must work with **zero network
connectivity** and **zero physical NIR hardware** — NIR is represented by a
simulator that is unmistakably labeled as simulated.

MVP is explicitly *not*: a laboratory germination predictor, a cloud service,
a multi-tenant SaaS, or a calibrated spectrometer. Those are later phases
(§8).

## 3. Technology stack

| Layer | Choice | Why |
|---|---|---|
| App framework | **Flutter 3.47 / Dart 3.13** | Cross-platform, already installed locally, camera+BLE plugin ecosystem is mature, one codebase for the eventual Android/iOS release. |
| State management / DI | **Riverpod** | Compile-safe DI is what makes `SpectralDevice` swappable (`NoNIRDevice` → `SimulatedNIRDevice` → `BluetoothNIRDevice`) without rewiring the app; testable without a widget tree. |
| Local database | **sqflite** (raw SQL, hand-written data sources) | Matches the schema in §7 directly; `drift`'s codegen isn't worth the build-time cost for a schema this size right now. Revisit if the schema grows past ~10 tables. |
| Camera | **camera** plugin | Cross-platform (Android/iOS/Web) live preview + capture; web support lets us verify UI in this dev environment where there is no Android SDK yet (see §10 risk). |
| Classical image processing | **image** (pure Dart) | No native OpenCV binding is set up in this environment; `image` is sufficient for thresholding, connected-component blob detection, and color/texture feature extraction at V0/V1 fidelity. Revisit → native OpenCV or a Rust/FFI binding if V2 needs more. |
| On-device ML inference | **tflite_flutter** (wired, unused until a trained model exists) | Standard mobile TFLite runtime; V0/V1 don't need it (rule-based / classical-features + a model trained in `ml/` and exported later). |
| BLE (future NIR) | **flutter_blue_plus** | Actively maintained, supports the GATT patterns needed for `BluetoothNIRDevice` (§7 of build prompt / `nir_protocol/`). |
| Charts | **fl_chart** | Batch histograms, quality distribution, spectral graph with zoom/point-inspection. |
| PDF report | **pdf** + **printing** | Shareable scan report export. |
| ML training | **Python 3.11+, scikit-learn, LightGBM, OpenCV, pandas** | Classical baseline (Model V1) per §14 of the build prompt; deliberately not a "huge neural network" for a dataset this small. |

## 4. Repository layout

```
AgriSpectra/
├── app/                        Flutter application
│   ├── lib/
│   │   ├── core/                theming, constants, DI setup, result types
│   │   ├── domain/               entities: Seed, Scan, Batch, Prediction, SpectralData, Device
│   │   ├── data/                 sqlite, ml inference, camera, ble — implementations
│   │   ├── application/          scan orchestration, analysis controller, device manager
│   │   ├── presentation/         screens, widgets, charts, theme
│   │   ├── ml/                   classical CV feature extraction + V0 rule engine (Dart)
│   │   ├── camera/                capture screen + quality gate
│   │   ├── nir/                   SpectralDevice abstraction + simulator + BLE device
│   │   └── database/               schema + migrations
│   ├── assets/
│   ├── test/
│   └── pubspec.yaml
├── ml/                          Python training repository (§17 below)
├── nir_protocol/                 BLE GATT protocol spec + example payloads
├── simulator/simulated_nir/       standalone Dart/Python reference of the simulator's data model
├── docs/                         this file + one doc per subsystem
└── README.md
```

## 5. Application architecture (camera-only path)

```
Camera
  ↓
Image Quality Gate      (blur / exposure / glare / background / resolution)
  ↓
Seed Detector            (classical CV: threshold → connected components)
  ↓
Segmentation              (per-seed crop, mask, contour, orientation)
  ↓
Feature Extraction         (geometry, color in RGB/HSV/LAB, texture, damage heuristics)
  ↓
Visual Classifier (V0)      (rule engine over darkening + edge density → good / damaged + score)
  ↓
Impurity Screen (V0)        (batch-relative size/shape outlier → IMPURITIES)
  ↓
Batch Engine                (aggregate seeds → quality stats; impurities → purity metric)
  ↓
Result
```

Barley quality classes: `good`, `damaged` (hull compromised; also where the
few hull-missing seeds go), `broken`, `shriveled`. `impurities` is a fifth
class the classifier can emit but it means "not a seed" — the batch engine
keeps it out of the quality figures and reports it as batch purity instead.

Model V0 is a **rule engine**, not a trained model, and it only emits
`good` or `damaged` — surface darkening and crack-like edge density,
thresholds checked against the barley reference set (see
docs/VALIDATION.md; the original shape/colour rules were miscalibrated for
elongated barley and were removed). `broken`, `shriveled` and `impurities`
need the trained V1; `impurities` additionally has a batch-relative
outlier rule (`impurity_detector.dart`). V0 exists so the full pipeline is
provably correct end-to-end before any ML training — per §43 of the build
prompt, proving the pipeline is the goal of V0, not accuracy.

## 6. Future multimodal architecture

```
Camera ──→ Vision Model ──┐
                           ├→ Late-Fusion Model → Result
NIR ─────→ Spectral Model ┘
```

`SpectralDevice` is the seam: `connect()`, `disconnect()`, `getStatus()`,
`startScan()`, `stopScan()`, `getCalibration()`, `getMeasurement()`,
`subscribeToMeasurements()`. Implementations, in delivery order:

1. `NoNIRDevice` — always present, camera-only mode. Ships in MVP.
2. `SimulatedNIRDevice` — generates labeled-synthetic spectral data (wavelength/
   intensity/noise/dark/white-reference) so the fusion UI and fusion model can
   be built and demoed before hardware exists. Ships in MVP. Never presented
   to the user as real.
3. `BluetoothNIRDevice` — real ESP32 + AS7265x hardware over BLE GATT
   (`nir_protocol/protocol.md`). Post-hackathon.

Fusion strategy: **late fusion** (`P_visual`, `P_nir`, per-sensor confidences,
crop/temperature/humidity → small fusion model), chosen over early fusion
because it's independently debuggable and degrades gracefully — a broken or
absent NIR reading doesn't take down the visual result (§36, §71 of the build
prompt).

## 7. Data model (SQLite)

```
Scan
 ├─ scan_id, timestamp, crop, cultivar?, location?, camera_metadata
 ├─ image_quality, number_of_seeds, batch_score, confidence
 └─ model_version, analysis_version, nir_available, nir_device_id

SeedResult
 ├─ seed_id, scan_id, image_path, segmentation
 ├─ visual_features, prediction, confidence, anomalies
 └─ verified_label?, verified_at?  (human ground truth, §44 — see below)

SpectralMeasurement          (future, table exists from day one)
 ├─ scan_id, device_id, timestamp
 ├─ wavelengths[], raw_values[], dark_reference[], white_reference[]
 └─ corrected_values[], integration_time, temperature, humidity, calibration_status
```

Raw measurements are never discarded (§33). Every prediction row records
`model_version` — predictions are never silently overwritten when a model
changes (§26).

`verified_label`/`verified_at` are set by the "Make Our App Better" review
flow (`app/lib/presentation/screens/improve_app_screen.dart`), never by
the vision pipeline — they're the app's own dataset-collection mode (§44),
turning every scan into potential training data without asking anything
of the user at capture time. See `docs/DATASET_GUIDE.md`'s "In-app
collection" section.

## 8. Roadmap

| Horizon | Scope |
|---|---|
| **Hackathon** (now) | Everything in §11 MUST-HAVE below. |
| **+12 weeks** | Grow the barley dataset past its current one-session state (multiple batches, ≥2 lighting setups, ≥2 phones); Model V1 (classical ML on extracted features) replaces the V0 rule engine + impurity heuristic for barley; dataset collection mode (§44 of build prompt) shipped to field-test users; validation framework (§47) run across lighting/phone/lens combinations. A second crop comes after barley V1 is validated, not before. |
| **+6 months** | Model V2 (lightweight CNN / transfer learning) if the classical baseline plateaus; first physical NIR prototype (ESP32 + AS7265x) wired to `BluetoothNIRDevice`; paired image+NIR+germination data collection begins (Model V4/V5 groundwork). |
| **Production** | Fusion model trained on real paired data; cloud sync as an opt-in, not a requirement; two-tier (camera-free vs. camera+NIR) packaging becomes a real business decision, not just an architectural placeholder. |

## 9. Companion documents

- [`README.md`](../README.md) — install & run instructions
- [`ML_PIPELINE.md`](ML_PIPELINE.md) — Python training repo
- [`NIR_PROTOCOL.md`](NIR_PROTOCOL.md) — BLE GATT spec
- [`DATASET_GUIDE.md`](DATASET_GUIDE.md) — labeling, splitting, versioning
- [`VALIDATION.md`](VALIDATION.md) — known limitations, what's been tested
- [`ROADMAP.md`](ROADMAP.md) — the table in §8, expanded

## 10. Risks and current environment constraints

- **No Android SDK / no Visual Studio C++ workload installed in this dev
  environment.** The app is built to target Android/iOS, but locally it can
  only be run/verified via `flutter run -d web-server` (web target). This is
  sufficient to verify UI, navigation, the CV pipeline (pure Dart, runs
  identically on web), and the simulated-NIR flow, but **not** camera-plugin
  behavior on a real device, BLE (not available on web), or a release APK.
  Installing Android Studio + SDK is needed before real-device testing —
  flagging this rather than silently skipping verification. Verified so
  far via the web target: navigation across Home → Crop Selection →
  Capture, theming (light/dark), and graceful camera-permission-denied
  error handling (expected in a browser sandbox with no camera device).
- **`sqflite_common_ffi_web` requires COOP/COEP response headers.** Without
  `Cross-Origin-Opener-Policy: same-origin` and
  `Cross-Origin-Embedder-Policy: require-corp`, `AppDatabase.open()` hangs
  indefinitely on web (its async OPFS worker needs `crossOriginIsolated`).
  `flutter run -d web-server` needs `--web-header=...` flags for both (see
  `README.md`); `flutter run -d chrome` sets them automatically. `main.dart`
  also no longer blocks `runApp()` on database open, specifically so a slow
  or failed open shows a visible loading/error state instead of a blank
  page — see `_Bootstrap` in `app/lib/main.dart`.
- **First load in `web-server`/DDC debug mode is slow** (multiple minutes
  observed in this sandboxed environment, likely CPU-constrained) — the
  dev bundle pulls in ~1500 JS modules including `flutter_test`/
  `leak_tracker` transitively. This is a debug-mode-only characteristic;
  `flutter run -d chrome` (real Chrome, incremental) or a release web build
  are the faster loops for actual development.
- **The only labelled dataset is one barley collection** (~158 images, five
  label folders, single session) — enough for a first Model V1 sanity pass,
  not enough for an accuracy claim. V0 stays a rule engine (plus a
  batch-relative size/shape outlier rule for impurities) so the pipeline is
  demonstrated honestly rather than pretending a validated model exists. The
  app is scoped to one crop (barley) to match.
- **AS7265x is a discrete-channel sensor**, not a continuous spectrometer.
  The data model stores `wavelengths[]`/`values[]` arrays, not a continuous
  curve, and nothing in this codebase should be extended to fabricate
  sub-nanometer resolution or a reconstructed 400–2500nm curve.

## 11. Hackathon prioritization

**MUST HAVE:** camera capture, seed detection, segmentation, visual
classification (V0 rule engine), batch scoring, polished UI, local inference,
scan history, NIR device screen, NIR simulator, multimodal architecture
(wired even if `NoNIRDevice` is the default), documentation.

**SHOULD HAVE:** dataset collection mode, PDF report generation,
explainability ("why this score"), advanced charts.

**FUTURE (explicitly out of scope now):** real NIR hardware, large dataset,
laboratory validation, germination prediction, cloud platform, commercial
certification, cultivar fingerprinting.

## 12. Scientific / claims discipline

This system reports **visual quality screening** and **screening confidence**,
never germination, viability, or embryo condition, unless a specific claim has
been validated against laboratory ground truth (§16 of the build prompt) —
which does not exist yet. UI copy, report text, and code comments should all
reflect this; see `docs/VALIDATION.md` for the running list of what is and
isn't validated.

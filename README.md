# AgriSpectra

AI-first mobile seed-quality diagnostics — camera + computer vision today,
architected for an optional NIR spectroscope tomorrow. Start with
[`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) for the full picture; this
file is install/run instructions.

## What's here

```
app/              Flutter application (Android/iOS/Web)
ml/               Python training pipeline (Model V1+)
nir_protocol/     BLE GATT protocol spec for the future NIR device
simulator/        Reference notes for the simulated NIR data model
docs/             Architecture, roadmap, dataset guide, validation status
```

## Prerequisites

- Flutter 3.47+ / Dart 3.13+
- For Android builds: Android Studio + SDK (not required for web)
- For iOS builds: Xcode (macOS only)
- Python 3.11+ (only needed for `ml/`)

## Run the app

```bash
cd app
flutter pub get
flutter run                 # picks a connected device
flutter run -d chrome       # web, for quick UI iteration
```

### Web-specific setup

The app uses `sqflite_common_ffi_web` for local storage on web, which
needs two things `flutter create` doesn't set up by itself:

```bash
cd app
dart run sqflite_common_ffi_web:setup   # copies sqlite3.wasm + sqflite_sw.js into web/
```

And the dev/prod server must send COOP/COEP headers — sqlite3.wasm's async
storage worker needs `crossOriginIsolated` to be `true`, or
`AppDatabase.open()` hangs indefinitely and nothing past the loading
screen ever renders:

```bash
flutter run -d web-server \
  --web-header=Cross-Origin-Opener-Policy=same-origin \
  --web-header=Cross-Origin-Embedder-Policy=require-corp
```

(`flutter run -d chrome` sets these automatically for its own debug
session; only the plain `web-server` target needs the flags above. A
production web host needs to send the same two headers.)

## Run tests

```bash
cd app
flutter test
```

## ML pipeline

See [`ml/README.md`](ml/README.md). Not required to run the app — Model V0
ships as a rule engine in Dart (`app/lib/ml/rule_classifier.dart`); `ml/`
is where Model V1+ gets trained once real data exists.

## Where to go next

- [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) — system design, roadmap, tech choices
- [`docs/DATASET_GUIDE.md`](docs/DATASET_GUIDE.md) — how to collect and structure training data
- [`docs/VALIDATION.md`](docs/VALIDATION.md) — what has and hasn't been validated
- [`docs/HACKATHON_DEMO.md`](docs/HACKATHON_DEMO.md) — demo script
- [`nir_protocol/protocol.md`](nir_protocol/protocol.md) — BLE protocol for the future NIR device

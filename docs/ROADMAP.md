# Roadmap

Detail behind the summary table in [`ARCHITECTURE.md`](ARCHITECTURE.md) §8.

## Hackathon (now)

Ship everything in the MUST HAVE list (build spec §67): camera capture,
seed detection/segmentation, Model V0 visual classification, batch
scoring, local persistence + history, the NIR abstraction wired to
`NoNIRDevice`/`SimulatedNIRDevice`, and the documentation set this file is
part of. See git history / the app's screens for current status —
this roadmap doesn't restate a checklist that the code already shows.

## +12 weeks

- Collect a real labeled dataset per [`DATASET_GUIDE.md`](DATASET_GUIDE.md)
  — target: multiple batches (not just multiple images) per crop, across
  at least 2 crops, ideally 2+ lighting setups and 2+ phones.
- Train Model V1 (`ml/training/train_baseline.py`) and replace
  `RuleBasedClassifier` as the app's default classifier, keeping the rule
  engine available as a fallback if the trained model is missing/corrupt
  (§58 error handling).
- Ship the dataset-collection mode (§44 of the build spec) so future data
  collection doesn't depend on manually organizing folders.
- Run the validation sweep in [`VALIDATION.md`](VALIDATION.md) and publish
  real numbers there instead of "pre-validation."

## +6 months

- Model V2 (CNN transfer learning, `ml/training/train_cnn.py`) if V1's
  accuracy/dataset-size tradeoff plateaus — not before, per §14 of the
  build spec.
- First physical NIR prototype (ESP32 + AS7265x, `docs/ARCHITECTURE.md`
  hardware section) wired to `BluetoothNIRDevice`
  (`app/lib/nir/ble_nir_device.dart`), integration-tested against
  `nir_protocol/protocol.md` for the first time.
- Begin paired image + NIR + germination data collection (the protocol in
  `DATASET_GUIDE.md`'s Germination dataset section) — this is the
  long-lead item for Model V4/V5, so it should start well before it's
  needed.

## Production

- Model V5 (multimodal RGB + NIR fusion) trained on real paired data,
  replacing `FusionEngine`'s confidence-weighted linear combination.
- Cloud sync as an explicit opt-in (§59/§60 of the build spec) — never a
  requirement for the app to function.
- The free/premium (camera-only vs. camera+NIR) packaging in §61 of the
  build spec becomes an actual business decision once there's a real
  device to sell, not before.

## Explicitly not scheduled

Laboratory-certified validation, commercial regulatory certification, and
large-scale cultivar fingerprinting are FUTURE-tier (§67) — no target
timeframe until the production-phase items above are real.

# Roadmap

Detail behind the summary table in [`ARCHITECTURE.md`](ARCHITECTURE.md) §8.

## Hackathon (now)

Ship everything in the MUST HAVE list (build spec §67): camera capture,
seed detection/segmentation, Model V0 visual classification, batch
scoring, local persistence + history, the NIR abstraction wired to
`NoNIRDevice`/`SimulatedNIRDevice`, and the documentation set this file is
part of. See git history / the app's screens for current status —
this roadmap doesn't restate a checklist that the code already shows.

## Now / next

- A first labelled **barley** dataset exists (~158 images, five folders:
  GOOD / DAMAGED / BROKEN / SHRIVELED / IMPURITIES; one collection session).
  App + pipeline are scoped to barley to match — see
  [`DATASET_GUIDE.md`](DATASET_GUIDE.md).
- Train Model V1 for barley (`ml/training/train_baseline.py`) and replace
  `RuleBasedClassifier` + `ImpurityDetector` as the app's default
  classifier, keeping both available as a fallback if the trained model is
  missing/corrupt (§58 error handling).

## +12 weeks

- Grow the barley dataset past one session: multiple real collection
  batches, ideally 2+ lighting setups and 2+ phones, so the train/test
  split can actually separate them.
- Add a second crop only once barley V1 is validated.
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

## Version log

`AppVersions` (`app/lib/core/constants/app_constants.dart`) — bump reasons
recorded here per that file's comment.

- **analysis_version 0.1.0 → 0.2.0** — quality taxonomy scoped to barley
  (`good / damaged / broken / shriveled / impurities`; removed
  `discolored / shell_free / mold_suspect / insect_damaged`). `Crop`
  narrowed to `barley`. `BatchStatistics` / the `batch_statistics` JSON
  gained `impurity_count` and `purity_ratio`; scans written before 0.2.0
  read those back as `0` / `1.0`. No database schema change
  (`database_schema_version` stays `1` — the affected column is JSON).

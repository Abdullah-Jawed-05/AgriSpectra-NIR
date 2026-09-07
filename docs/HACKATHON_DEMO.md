# Hackathon Demo Script

90-second flow (§50 of the original build spec), plus the fallback plan if
live capture is unreliable on the day.

## Flow

**0–15s — the problem.** Farmers and seed dealers currently have no fast,
inexpensive way to screen seed quality before purchase; lab testing is
slow and inaccessible at point-of-sale.

**15–30s — the hardware.** Show the phone and the clip-on macro lens.
Emphasize: this is the whole hardware budget for V1.

**30–50s — capture.** Open AgriSpectra, pick a crop, capture a batch of
seeds (10–50) **spread in a single layer, not touching**, on a plain sheet
of paper inside the framing guide. (The pipeline rejects piled/touching
seeds and textured backgrounds up front — worth showing that guard once.)

**50–65s — detection and scoring.** The app detects and segments
individual seeds, scores each one, and shows why (evidence factors, not a
bare number).

**65–75s — batch result.** Show the batch result screen: score
distribution, uniformity, anomaly count, confidence.

**75–90s — the NIR pathway.** Open NIR Device, connect the simulator
(clearly labeled as simulated on screen), rescan, and show the combined
result screen updating with a spectral graph and a higher-confidence
combined score. Say, close to verbatim from §50: *"The phone gives farmers
an accessible first layer. When the AgriSpectra spectroscope is connected,
the same application adds spectral information that cannot be obtained
from the camera alone."*

## Fallback plan if live capture is flaky

Per §49 of the build spec: real camera → real detection → real model →
real result is the target, but if lighting/venue conditions make live
capture unreliable, fall back to a **pre-captured** batch photo (still run
through the live pipeline, not a canned result) rather than skipping the
segment. Never substitute a fabricated result for a real pipeline run —
the demo should show what the software does, not a mockup of it.

## What to say about the NIR segment, precisely

Say the spectral reading is simulated, out loud, when demoing it — the UI
already labels it, but the verbal framing should match: "this is a
software simulation of what the sensor will report once the physical
device exists" is accurate; "the NIR sensor detected moisture stress" is
not, because there is no physical sensor yet.

## Known rough edges to preempt in Q&A

- **No real training dataset yet** → the visual classifier is Model V0, a
  hand-tuned rule engine, not a trained model. It screens **dark /
  discoloured damage** and batch purity; it does *not* detect cracks,
  shrivel or breakage (those need the trained V1). Framed as
  "screening that may correlate with quality", never "detects X" — see
  `docs/VALIDATION.md` and §66 of the build spec.
- **Classical segmentation has limits** → it handles seeds spread in a
  single layer well; a dense pile of ~40 touching grains can't be
  separated per-seed by classical CV, so the app detects that and asks for
  a better layout rather than returning a wrong count. A learned detector
  (YOLO) is the post-V1 fix.
- **No physical NIR hardware yet** → everything NIR is simulated (labelled
  on screen) or an unverified BLE client waiting for real firmware.
- Built and installed as a release APK on Android; the camera / scan /
  history / report / dataset-collection flows have been run on a real
  device. BLE against real NIR firmware is untested (no firmware exists).

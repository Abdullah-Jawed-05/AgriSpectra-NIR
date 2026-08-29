# Simulated NIR — reference notes

The actual, functional simulator is `app/lib/nir/simulated_nir_device.dart`
— a `SpectralDevice` implementation used directly by the app (see
`docs/NIR_INTEGRATION.md`). This directory is not a second implementation;
it's where the simulator's data-shape decisions are written down for
anyone building a non-Dart tool (a Python analysis notebook, a firmware
test harness) that needs to produce or consume the same shape of data.

## Channel layout

18 discrete channels at fixed wavelengths (nm), matching the real AS7265x
Triad sensor and `nir_protocol/protocol.md`:

```
410, 435, 460, 485, 510, 535,   # AS72651
560, 585, 610, 645, 680, 705,   # AS72652
730, 760, 810, 860, 900, 940    # AS72653
```

## What the simulator generates per reading

- `dark_reference[18]`, `white_reference[18]` — synthetic calibration
  constants, generated once per `runCalibration()` call and reused until
  recalibrated.
- `raw_values[18]` — `dark + reflectance * (white - dark)`, plus Gaussian
  noise.
- `reflectance[18]` — `(raw - dark) / (white - dark)`, clamped to `[0, 1]`.
- `temperature_c`, `humidity_percent` — small random values in a plausible
  ambient range, not derived from anything physical.

## Profiles

`SimulatedSeedProfile`: `goodSeed`, `agedSeed`, `moistureStressed`,
`damagedSeed`, `unknown`. Each maps to a hand-authored reflectance curve
shape in `SimulatedNIRDevice._profileReflectanceAt` — see that method's
doc comment for what each shape represents and why it's labeled
illustrative rather than measured.

## The one rule that matters

Nothing produced here may be presented to a user as a real measurement.
`SpectralMeasurement.isSimulated` is `true` for every reading this device
produces, and every screen that displays a spectral reading must check it
(see `ResultScreen`'s "SIMULATED" badge and `NirDeviceScreen`'s device
status card for the current examples).

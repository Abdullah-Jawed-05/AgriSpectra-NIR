# AgriSpectra NIR BLE Protocol — v1

Status: **provisional design**, unvalidated against real hardware (no
physical AgriSpectra NIR device exists yet — see
`docs/ARCHITECTURE.md` §10). This document is what `BluetoothNIRDevice`
(`app/lib/nir/ble_nir_device.dart`) implements today, and what a future
ESP32 firmware should implement to be compatible with it.

`protocol_version: 1`. The app rejects any device advertising a
`protocol_version` it doesn't recognize (`UnsupportedProtocolVersionException`
in `app/lib/nir/spectral_device.dart`) rather than guessing at
compatibility.

## Transport

BLE GATT. Central = phone (AgriSpectra app). Peripheral = ESP32 running the
AgriSpectra NIR firmware.

## Service

```
AgriSpectra Sensor Service
UUID: 6e400001-b5a3-f393-e0a9-e50e24dcca9e   (custom, Nordic UART-style base)
```

## Characteristics

| Name | UUID (suffix) | Properties | Payload |
|---|---|---|---|
| Device Information | `...ca9e` → `6e400010-...` | Read | see §Device Info |
| Calibration Control | `6e400011-...` | Write, Notify | see §Calibration |
| Scan Control | `6e400012-...` | Write | see §Scan Control |
| Spectral Data | `6e400013-...` | Notify | see §Spectral Data |
| Environmental Data | `6e400014-...` | Notify | see §Environmental |
| Battery Status | `6e400015-...` | Read, Notify | 1 byte, 0-100 |
| Device Status | `6e400016-...` | Read, Notify | 1 byte, enum below |

All multi-byte integers/floats are **little-endian**.

## Device Status enum

```
0 = idle
1 = scanning
2 = calibrating
3 = error
```

## Device Information (read)

```
offset 0, 1 byte   : protocol_version   (must be 1)
offset 1, 16 bytes : device_id          (UTF-8, null-padded)
offset 17, 8 bytes : firmware_version   (UTF-8, null-padded, e.g. "0.1.0")
offset 25, 8 bytes : hardware_revision  (UTF-8, null-padded)
```

## Calibration Control

Write `0x01` to start a dark-reference capture, `0x02` to start a
white-reference capture (§74 physical steps: place reference target, close
chamber, run dark, run white). The characteristic notifies back a single
status byte (`0 = in_progress`, `1 = complete`, `2 = failed`) followed
later by a full `CalibrationState` delivered over **Spectral Data** with a
reserved `measurement_type = 0xFF` (calibration reference, not a sample).

## Scan Control

Write `0x01` to start a sample scan, `0x00` to stop/cancel.

## Spectral Data (notify)

One notification per completed scan. The AS7265x provides 18 discrete
channels (§31/§32 of the build spec — not a continuous spectrum, and this
payload must never be reinterpreted as one):

```
offset 0,  1 byte   : measurement_type   (0x01 = sample, 0xFF = calibration reference)
offset 1,  4 bytes  : integration_time_ms (float32)
offset 5,  18*4 = 72 bytes : raw_values[18] (float32 each, channel order below)
```

Channel order (matches `SimulatedNIRDevice.wavelengthsNm` in
`app/lib/nir/simulated_nir_device.dart` exactly, so simulated and real
readings are interchangeable downstream):

```
410, 435, 460, 485, 510, 535,   # AS72651
560, 585, 610, 645, 680, 705,   # AS72652
730, 760, 810, 860, 900, 940    # AS72653  (nm)
```

Dark/white reference captures use the same 72-byte channel layout with
`measurement_type = 0xFF`; the app matches them to the most recent
calibration request.

## Environmental Data (notify)

```
offset 0, 4 bytes : temperature_c (float32)
offset 4, 4 bytes : humidity_percent (float32)
```

## Versioning

Any breaking change to a payload layout bumps `protocol_version`. Additive
changes (new optional characteristic) do not require a bump, but firmware
should still update `hardware_revision` for traceability (§75).

## What is confirmed vs. provisional

- **Confirmed:** AS7265x provides 18 discrete channels at the wavelengths
  listed above (from the SparkFun Triad Spectroscopy Sensor datasheet).
- **Provisional:** the exact GATT UUIDs, byte offsets, and status-byte
  values above — these are this project's own design, not an existing
  standard, and will change once real firmware is built and the two sides
  are integration-tested against each other.

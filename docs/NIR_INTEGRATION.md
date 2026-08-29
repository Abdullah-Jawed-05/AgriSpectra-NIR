# NIR Integration

How the NIR side of the app fits together — the abstraction, the two
implementations that ship today, and what changes (and doesn't) when real
hardware arrives. For the wire protocol itself, see
[`../nir_protocol/protocol.md`](../nir_protocol/protocol.md).

## The interface everything depends on

`app/lib/nir/spectral_device.dart` — `SpectralDevice`. Screens
(`NirDeviceScreen`), the orchestrator (`ScanOrchestrator`), and the fusion
engine (`FusionEngine`) all depend on this interface, never on a concrete
device class. `DeviceManager`
(`app/lib/application/device_manager.dart`) owns the single active
instance app-wide.

## Implementations

| Class | File | Status |
|---|---|---|
| `NoNIRDevice` | `nir/no_nir_device.dart` | Ships. Default. Camera-only mode. |
| `SimulatedNIRDevice` | `nir/simulated_nir_device.dart` | Ships. Synthetic, clearly labeled, never presented as real (§30). |
| `BluetoothNIRDevice` | `nir/ble_nir_device.dart` | Written against `nir_protocol/protocol.md`, **never tested against real hardware** — no physical device exists yet. Not wired into `DeviceManager`'s default options. |

## What "adding real hardware" actually involves

Because everything above depends on the interface, bringing up real
hardware is additive, not a rewrite:

1. Build the ESP32 firmware implementing `nir_protocol/protocol.md`'s GATT
   service. Integration-test it against `BluetoothNIRDevice` for the first
   time — expect the byte-level details in the protocol doc to need
   correction once a real peripheral exists (the doc says this explicitly).
2. Wire `BluetoothNIRDevice` into `NirDeviceScreen`'s "Search for real
   device" tile (currently `enabled: false` with an explanatory subtitle —
   see `app/lib/presentation/screens/nir_device_screen.dart`), using
   `BluetoothNIRDevice.discover()`.
3. Nothing in `ScanOrchestrator`, `FusionEngine`, the database schema, or
   any result screen needs to change — they already only see
   `SpectralDevice`.

## Fusion

`app/lib/nir/fusion_engine.dart` implements confidence-weighted late
fusion (Model V0 of fusion — see the class doc comment for why late fusion
and why confidence-weighted, both traceable to specific build-spec
sections). `app/lib/nir/nir_quality.dart` scores how much to trust a given
NIR reading independent of what the vision pipeline found. Neither module
cares whether the reading came from the simulator or real hardware — the
`SpectralMeasurement.isSimulated` flag exists for UI labeling, not for
different fusion behavior.

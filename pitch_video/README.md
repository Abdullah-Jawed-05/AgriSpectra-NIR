# AgriSpectra pitch video

Seven cue-based clips that play behind the speaker, one per block of the stage
script (see [`CUES.md`](CUES.md)). Each scene is an HTML page whose
`render(t)` is a pure function of time, rendered frame by frame in headless
Chromium and encoded with ffmpeg.

```bash
npm install && npm run setup
node render.mjs 06_device --fps 60          # -> out/06_device.mp4
./sheet.sh 06_device 2,9,16,27              # contact sheet of stills for checking
```

Set `CHROME_PATH` if Chromium isn't at the default path. Open
`scenes/<name>.html?play` through any static server to preview a scene live.

For the show, put the rendered MP4s in the same folder as `player.html` and open
it in Chrome: → / Space / clicker advances a cue, each clip holds on its last
frame, and the HUD keys are listed on the start screen.

| Scene | Content |
|---|---|
| `01_problem` | Seed bag → failed field → Punjab per-acre wheat input cost (Rs 87,187) |
| `02_scale` | Pakistan dot map, 1 in 3 workers in agriculture, 392 banned seed companies |
| `03_app` | App capture → detection → score 87 → expected germination 68% → PDF report |
| `04_race` | Lab spectroscopy (days, Rs 10,000+) vs AgriSpectra (seconds, Rs 0) |
| `05_inside` | Seed cutaway, outside perfect / inside degraded → device reveal |
| `06_device` | Exploded view, light path, 18-channel spectrum, reference comparison, BLE to phone |
| `07_close` | Closing line, phone + NIR converge, end card "Know what you sow." |

The 3D device lives in `lib/device.js`, modelled after the product renders
(110 × 80 × 75 mm, top button + status LED, light-sealed drawer, ESP32 PCB,
18650 cell, white LED + AS7265x optical chamber).

## Voice-over cut

`voiceover.py` narrates the clips with [Kokoro](https://github.com/thewh1teagle/kokoro-onnx)
(open-weights neural TTS, runs offline) and writes one continuous MP4 with
audio. Each line is placed at its visual beat; a clip whose narration runs
long holds its last frame. Cue 7 is re-rendered with a time-warp so the
close lands on the voice:

```bash
pip install kokoro-onnx soundfile
# model files from github.com/thewh1teagle/kokoro-onnx/releases (model-files-v1.0),
# paths via KOKORO_MODEL / KOKORO_VOICES
node render.mjs 07_close --fps 60 --out 07_close_vo \
  --warp "0:0,5:5,8:6.3,10.4:7.2,12.9:8.75,13.5:9.6,14.9:10.6,20.3:16"
python3 voiceover.py am_michael out/AgriSpectra_voiceover_male.mp4   # or af_heart
```

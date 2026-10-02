"""Narrate the seven cue clips with Kokoro TTS and mux a voiced full cut.

Each line is placed at the clip time where its visual beat lands. If a line
would overlap the previous one it is pushed later, and a clip whose narration
outlasts it gets its last frame held (tpad) so nothing is cut off.

Usage: python3 voiceover.py <voice> <out.mp4>

Cue 7 is re-rendered first with:
  node render.mjs 07_close --fps 60 --out 07_close_vo \\
    --warp "0:0,5:5,8:6.3,10.4:7.2,12.9:8.75,13.5:9.6,14.9:10.6,20.3:16"
"""
import json
import os
import subprocess
import sys
from pathlib import Path

import numpy as np
import soundfile as sf
from kokoro_onnx import Kokoro

VOICE = sys.argv[1] if len(sys.argv) > 1 else "am_michael"
OUT = Path(sys.argv[2] if len(sys.argv) > 2 else "deliver/AgriSpectra_voiceover.mp4")
ROOT = Path(__file__).parent
SR = 24000
GAP = 0.2  # minimum silence between lines
SPEED = 1.12
TAIL = 1.2  # hold after the last line of a cue

# (clip time in seconds, line). Brand spelled so the TTS says it as two words.
CUES = {
    "01_problem": [
        (0.5, "Every season, millions of farmers make a bet they can't check."),
        (5.6, "They buy seed at the counter on trust, with no quick, affordable way to test it."),
        (10.6, "When that seed is bad, they don't find out at the shop. They find out weeks later, in an empty field."),
        (17.2, "By then, the money, the land, and the season, are gone."),
    ],
    "02_scale": [
        (1.8, "In Pakistan, agriculture employs one in three workers."),
        (6.2, "Fake and substandard seed is so common, that authorities have banned three hundred and ninety-two companies for selling it."),
        (11.6, "At that scale, one bad bag becomes a national loss."),
    ],
    "03_app": [
        (0.4, "Agri Spectra solves this."),
        (2.0, "The Agri Spectra A.I. provides preliminary, non-destructive seed quality screening, from a smartphone camera."),
        (8.4, "It finds every seed, scores each one, and gives you a full batch report, based on growth-tested models."),
    ],
    "04_race": [
        (0.3, "Compare that to a lab."),
        (1.7, "A spectroscopy test takes three to four days, and costs up to five figures."),
        (6.7, "Agri Spectra gives you an answer at the counter, before you pay."),
        (10.5, "And scanning with your phone costs nothing."),
    ],
    "05_inside": [
        (0.4, "But a camera can only see so far."),
        (2.5, "A seed can look perfect on the outside,"),
        (5.9, "and be dead on the inside."),
        (10.2, "That's where Agri Spectra N.I.R. comes in."),
    ],
    "06_device": [
        (2.0, "Eighteen channels of near-infrared spectroscopy look inside the seed,"),
        (7.6, "reading moisture content, pigment difference, lipid and protein variation, and signs of degradation."),
        (12.9, "It compares that fingerprint against growth-tested reference samples, to estimate germination viability,"),
        (18.4, "then sends the result straight to your phone."),
        (22.3, "One button."),
        (23.8, "No screen."),
        (25.2, "Fits in your hand."),
    ],
    # narrated cue 7 uses a retimed render (out/07_close_vo.mp4), see WARP_07
    "07_close": [
        (0.3, "A farmer shouldn't have to gamble a whole season on a bag of seed."),
        (4.9, "With Agri Spectra, the phone sees the outside."),
        (8.1, "The N.I.R. sees the inside."),
        (10.5, "And the farmer knows, before they plant."),
        (13.6, "Agri Spectra."),
        (15.0, "Know what you sow."),
    ],
}


def duration(path):
    out = subprocess.check_output(["ffprobe", "-v", "error", "-show_entries", "format=duration", "-of", "json", str(path)])
    return float(json.loads(out)["format"]["duration"])


def main():
    tts = Kokoro(os.environ.get("KOKORO_MODEL", "/tmp/tts/kokoro-v1.0.onnx"), os.environ.get("KOKORO_VOICES", "/tmp/tts/voices-v1.0.bin"))
    work = ROOT / "frames" / f"vo_{VOICE}"
    work.mkdir(parents=True, exist_ok=True)
    parts = []
    report = []
    for cue, lines in CUES.items():
        clip = ROOT / "out" / f"{cue}_vo.mp4"
        if not clip.exists():
            clip = ROOT / "out" / f"{cue}.mp4"
        vdur = duration(clip)
        placed, cursor = [], 0.0
        for t, text in lines:
            audio, sr = tts.create(text, voice=VOICE, speed=SPEED, lang="en-us")
            assert sr == SR
            start = max(t, cursor + GAP)
            if start > t + 0.05:
                report.append(f"{cue}: '{text[:40]}…' pushed {start - t:.1f}s")
            placed.append((start, audio))
            cursor = start + len(audio) / SR
        total = max(vdur, cursor + TAIL)
        track = np.zeros(int(total * SR) + 1, dtype=np.float32)
        for start, audio in placed:
            i = int(start * SR)
            track[i:i + len(audio)] += audio
        peak = np.abs(track).max() or 1.0
        track = track / peak * 0.89
        wav = work / f"{cue}.wav"
        sf.write(wav, track, SR)
        seg = work / f"{cue}.mp4"
        pad = max(0.0, total - vdur)
        subprocess.check_call([
            "ffmpeg", "-v", "error", "-y", "-i", str(clip), "-i", str(wav),
            "-filter_complex", f"[0:v]tpad=stop_mode=clone:stop_duration={pad + 0.6:.3f}[v];[1:a]apad=pad_dur=0.6,aresample=48000[a]",
            "-map", "[v]", "-map", "[a]", "-t", f"{total + 0.6:.3f}",
            "-c:v", "libx264", "-crf", "16", "-preset", "medium", "-pix_fmt", "yuv420p",
            "-c:a", "aac", "-b:a", "192k", str(seg)])
        parts.append(seg)
        report.append(f"{cue}: video {vdur:.1f}s, narrated cue {total + 0.6:.1f}s (held {pad + 0.6:.1f}s)")
    lst = work / "list.txt"
    lst.write_text("".join(f"file '{p}'\n" for p in parts))
    OUT.parent.mkdir(parents=True, exist_ok=True)
    subprocess.check_call(["ffmpeg", "-v", "error", "-y", "-f", "concat", "-safe", "0", "-i", str(lst), "-c", "copy", "-movflags", "+faststart", str(OUT)])
    print("\n".join(report))
    print(f"wrote {OUT} ({duration(OUT):.1f}s)")


if __name__ == "__main__":
    main()

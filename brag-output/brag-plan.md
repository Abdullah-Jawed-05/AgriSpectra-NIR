# Brag Plan: AgriSpectra

## What is this app?
AgriSpectra screens seed quality from a phone camera photo — segmenting, classifying, and scoring individual seeds in a batch offline — and gets sharper when an optional NIR spectroscope is connected for a second, spectral opinion the camera alone can't give.

## The angle
No lab-coat theatrics, no "streamline your workflow" — this is an instrument demo. The premise: the entire V1 hardware budget is a phone and a clip-on macro lens, and the software still produces a real, explained, per-seed quality score. Then the one twist: the same app has a slot waiting for real spectral hardware, and when you plug it in (today: simulated, honestly labeled), the score gets sharper, not replaced. The film plays it straight, like a product reel for a diagnostic instrument, because the honesty *is* the impressive part.

## Hook (first 2-3 seconds)
Full-bleed on the near-white instrument panel: the AgriSpectra seed-mark icon, then the line **"Seed quality. From a phone."** snaps in — deep teal on off-white, no fanfare.

## Key moments (the middle)
- A spread batch of seeds on a plain sheet gets scanned; the frame guide locks on, then seeds segment one by one with a thin teal outline per seed.
- The Batch Result screen arrives: the big score, the confidence chip, then the class-count chips landing one by one — good (teal), damaged, shriveled, broken, impurities — each in its real status color.
- The score-distribution histogram draws in, bar by bar.
- Cut to NIR Device: connect the "AgriSpectra-NIR (Simulated)" entry — clearly tagged SIMULATED — and the result screen updates with the purple spectral graph and the batch score ticking up as NIR enhancement joins visual score.

## Outro / punchline
Hold on the wordmark and the line: **"The phone gives you a first layer. NIR adds what the camera can't see."** — then, smaller, the honest footnote the app itself carries: "Preliminary screening. Not a replacement for certified lab testing." Logo mark settles. Silence under the last beat.

## User flow worth showing
1. **Entry:** pick crop (Barley), open the capture guide, frame a single-layer spread of seeds on a plain sheet.
2. **Key action:** scan → per-seed segmentation and classification → batch score computed.
3. **Result:** Batch Result screen (score, confidence, class chips, histogram) → connect simulated NIR → combined result updates with spectral graph and a higher-confidence fused score.

## Tone
- Preset: polished
- Creative direction: quiet diagnostic-instrument film — restrained, scientific, confident without hype.
- Interpretation: 3-4 scenes, longer holds (4-6s each), slow crossfades, mixed-case type at light-to-medium weight, generous letter-spacing. No bullet-point energy, no chaotic cuts — confidence comes from what's being shown, not how fast it's cut.

## Format: landscape — 1920x1080
## Duration: 22s (revised from 20s — see Storyboard note)

## Visual identity (from the project)
- Background: `#F7F8F7` (light) — near-white instrument panel, not pure white
- Accent: `#0E6E5D` (deep teal) — primary brand/status-good color
- Secondary accent: `#5B3FA0` (NIR purple), used only for the spectral/NIR beat
- Text: `#171E1B` (ink, near-black green)
- Muted text: `#54615B`
- Status colors: good `#1B7A4C`, moderate `#B07A12`, low/danger `#B0401E`
- Display/body font: Roboto (app-wide `fontFamily: 'Roboto'`)
- Strongest visual element: the AgriSpectra mark (a stylized seed silhouette crossed by a lighter horizontal band — reads as both a spectral scan pass and a seed's crease) plus the color-coded class-count chips on the result screen

## Share copy (draft)
AgriSpectra screens seed quality from a phone camera — and gets sharper with an optional NIR spectroscope. No lab required.

## Audio direction
- Role: sparse professional accents — a low, restrained bed under confident, unhurried visuals
- Music: `happy-beats-business-moves-vol-9-by-ende-dot-app.mp3` (114.84 BPM) — mixed well below its native energy; used for a steady, unobtrusive pulse rather than its default upbeat feel
- Music treatment: starts low under the hook, stays low and steady through the scan/result scenes, a very slight lift (not a swell) under the NIR beat, fades out under the outro's silence
- Music cue guidance: preset exists at `assets/music/cues/happy-beats-business-moves-vol-9-by-ende-dot-app.music-cues.json`. Target strong cues near 4.23s (hook settle), 10.54s (batch result arrival), and 12.65s (histogram draw) — within the plan's 20s window. Treat the bundled grid as rhythm guidance only; the restrained posture takes priority over hitting every beat.
- Audio-reactive treatment: none — this tone wants stillness, not a glow that breathes with the track
- SFX posture: sparse; one soft per-seed tick as segmentation outlines land, one clean confirm tone as the batch score resolves, one subtle distinct tone (slightly different timbre) on NIR connect — no SFX during the outro
- Audio-coupled moments: per-seed segmentation ticks (fast, quiet, several in a row), one clear tone on batch score reveal, one distinct tone on NIR "connected" state
- Restraint rule: audio must never spike, never add a laugh-track-style stinger, and must get out of the way completely for the final silent hold on the wordmark

## Storyboard

**Revision note:** the original 4-scene/20s cut combined the NIR beat and the outro punchline into one 4s scene. At the reading-time floor (~0.3s/word), the outro line alone ("The phone gives you a first layer. NIR adds what the camera can't see.", 14 words) needs ~4.2s settled — it cannot share a 4s scene with the NIR-connect beat without being pulled off before it's readable. Split into 5 scenes and extended to 22s total (still inside the 15-25s window) so the outro gets its own hold.

### Scene 1 — Hook — 4s
Full-bleed instrument-panel background (`#F7F8F7`). AgriSpectra mark fades/scales in at center-top, small. Line settles below it: "Seed quality. From a phone." in ink `#171E1B`, Roboto, medium weight, generous letter-spacing. Hold the full line fully readable for ~2s minimum before any exit.
Sequential/interaction: none
Audio intent: calm confidence, not excitement — the bed enters quietly under the mark's fade-in
Audio-coupled idea: none
Music: low bed enters, steady
Transition mood: soft crossfade → Scene 2

### Scene 2 — Capture & scan — 4.5s
Recreate the capture guide: a framing rectangle over a plain sheet with a spread batch of seed shapes (simple, true-to-UI silhouette seeds, not photoreal). The frame guide locks (border shifts from muted to teal `#0E6E5D`). Seeds then get thin teal outlines one by one — a quick per-seed segmentation pass, 8-10 seeds, each outline landing in quick succession.
Sequential/interaction: yes — seed outlines appear one by one across the batch, left to right, fast (~0.15-0.2s apart, since these are small accent marks, not text)
Audio intent: precise, mechanical confidence — each segmentation tick reads as the instrument doing real work
Audio-coupled idea: a soft, quiet tick per seed outline landing
Music: low bed continues, steady
Transition mood: soft crossfade → Scene 3

### Scene 3 — Batch Result — 5.5s
Recreate the Batch Result screen using real layout and copy: large batch score top-left, confidence chip beside it, "N seeds analyzed · Multimodal assessment" line beneath. Class-count chips arrive one by one in their real colors — Good (teal), Damaged, Shriveled, Broken, Impurities — each a confident settle, not a bounce. Then the score-distribution histogram draws in bar by bar beneath.
Sequential/interaction: yes — class chips arrive one by one (hold each ~0.8s before the next starts, per the reading-time floor for short labels); histogram bars draw in left to right after chips settle
Audio intent: the "proof" moment — unhurried, matter-of-fact certainty
Audio-coupled idea: one clear, clean confirm tone exactly as the batch score number settles; chips land silently or with the faintest click, subordinate to the main tone
Music: low bed, slight presence (no swell)
Transition mood: slow crossfade (0.6-0.8s) → Scene 4

### Scene 4 — NIR fusion — 3s
Cut to the NIR Device screen: the "AgriSpectra-NIR (Simulated)" row with its SIMULATED tag, in NIR purple `#5B3FA0`. Connects (badge flips to CONNECTED); crossfades into the combined result — spectral graph (purple) appears beside the score, which ticks up slightly as NIR enhancement joins visual score. Short beat, no long sentence here — labels only ("NIR enhancement", "Combined score").
Sequential/interaction: none beyond the one connect/crossfade beat
Audio intent: a small lift in attention — not a swell, just a distinct marker that something new joined
Audio-coupled idea: one distinct, quiet tone on NIR "connected" state (different timbre from Scene 3's confirm tone)
Music: low bed continues, slight presence
Transition mood: slow crossfade → Scene 5

### Scene 5 — Outro — 5s
Wordmark (mark + "AgriSpectra") settles center, then the punchline line beneath: "The phone gives you a first layer. NIR adds what the camera can't see." — holds fully readable (14 words needs ~4.2s settled; this scene exists to give it that room). The smaller italic footnote line about preliminary screening/lab-testing, exactly as the app states it, appears just beneath and holds alongside it. Music fades fully across this scene; last ~1s is silent under the still wordmark.
Sequential/interaction: none — everything arrives once and holds, no sequencing needed
Audio intent: let go — the bed fades out and gets out of the way for the silent final hold
Audio-coupled idea: none
Music: fades out across this scene, silent for the last ~1s
Transition mood: hold to end (no exit transition — the video ends on this still frame)

**Music mood for this video:** restrained, low-key pulse under a confident, unhurried visual — never upbeat-sounding despite the track's native energy
**Audio summary:** A quiet, steady bed enters with the hook, stays low and matter-of-fact through the scan and result scenes (one tick-per-seed moment, one clean confirm tone on the score), gets a single distinct tone on the NIR connect beat, then fades completely to silence under the final wordmark hold.

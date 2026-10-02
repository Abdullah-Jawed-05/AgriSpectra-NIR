# Hyperframes Composition Brief: AgriSpectra

## Objective
Create a short, restrained launch-style brag video for AgriSpectra, a phone-camera seed-quality screening app with an optional simulated NIR spectroscope fusion pathway.

## Output
- Composition directory: `composition/`
- Rendered video: `brag.mp4`
- Format: landscape — 1920x1080
- Duration: 22 seconds (revised up from 20s — see `brag-plan.md` storyboard revision note: the outro punchline needs its own scene to stay readable)

## Source Material
- Project root: `/home/user/AgriSpectra-NIR`
- Primary files read: `README.md`, `docs/HACKATHON_DEMO.md`, `app/lib/core/theme/app_theme.dart`, `app/lib/presentation/screens/home_screen.dart`, `app/lib/presentation/screens/result_screen.dart`, `app/lib/presentation/screens/nir_device_screen.dart`, `app/lib/presentation/screens/crop_selection_screen.dart`, `app/lib/presentation/widgets/agrispectra_mark.dart`
- Product name: AgriSpectra
- Tagline / strongest claim: "The phone gives farmers an accessible first layer. When the AgriSpectra spectroscope is connected, the same application adds spectral information that cannot be obtained from the camera alone." (docs/HACKATHON_DEMO.md)
- Key UI or visual moment to recreate: the Batch Result screen (score, confidence chip, color-coded class-count chips, score-distribution histogram) and the NIR Device screen's "AgriSpectra-NIR (Simulated)" entry → combined result with the purple spectral graph
- Copy that must appear verbatim (re-cased/trimmed is fine, invented is not):
  - "Seed quality screening" (home screen subtitle)
  - "NEW SCAN" (primary action button)
  - Class labels: Good, Damaged, Shriveled, Broken, Impurities (quality classes, §15)
  - "AgriSpectra-NIR (Simulated)" / "SIMULATED" badge text (nir_device_screen.dart, result_screen.dart)
  - "AgriSpectra provides preliminary, non-destructive visual seed-quality screening... it does not... predict germination, and it is not a replacement for certified laboratory testing." (home_screen.dart methodology sheet / result_screen.dart footnote — may be trimmed, not altered in meaning)

## Creative Direction
- Tone preset: polished
- Creative direction: quiet diagnostic-instrument film — serious, restrained, confident without hype
- Interpretation: 4 scenes, 4-6s holds, slow crossfades (0.6-0.8s), mixed-case type at light-to-medium weight with generous letter-spacing. No bullet energy, no hard cuts, no chaotic staggering — confidence comes from what is shown, not how fast it is cut.
- Angle: the entire V1 hardware budget is a phone and a clip-on macro lens, and the software still produces a real, explained, per-seed quality score; the one twist is that the same app has a slot waiting for real spectral hardware, and plugging it in (today: honestly labeled as simulated) sharpens the score rather than replacing the camera's read.
- Hook: AgriSpectra mark settles, then "Seed quality. From a phone." on the near-white instrument panel.
- Outro / punchline: "The phone gives you a first layer. NIR adds what the camera can't see." followed by the smaller, italic lab-testing footnote the app itself carries.
- Avoid:
  - Generic SaaS language
  - Abstract filler visuals
  - Unrelated visual redesign (do not invent a new palette or UI — recreate the app's real theme)
  - Overstating the NIR capability as real hardware (it is explicitly simulated and must read that way on screen)

## Visual Identity
- Background: `#F7F8F7` (light instrument-panel background)
- Surface: `#FFFFFF`, Surface-alt: `#EFF2F0`
- Text (ink): `#171E1B`; muted text: `#54615B`; divider: `#DDE3DF`
- Accent (primary/teal): `#0E6E5D`; accent-muted: `#DCEEE9`
- Status colors: good `#1B7A4C`, moderate `#B07A12`, low/danger `#B0401E`
- NIR accent (purple): `#5B3FA0`; NIR-muted: `#EAE4F6`
- Display/body font: project uses `Roboto` app-wide; in the composition use the equivalent system sans-serif stack (`system-ui, -apple-system, "Segoe UI", Arial, sans-serif`) rather than naming a custom webfont, to match weight/spacing without requiring a bundled `@font-face` file
- Visual references from the project: the AgriSpectra mark (a stylized seed silhouette crossed by a lighter horizontal band — reads as both a spectral scan pass and a seed's crease — recreate as inline SVG/CSS, not a bitmap); the rounded-card, zero-elevation, bordered-divider look (`AppRadius.lg` = 14px, 1px dividers); color-coded status pills/chips exactly as in `result_screen.dart`

## Storyboard
Use the storyboard in `../brag-plan.md` as the creative contract.

Scene summary:
1. Hook — 4s — mark settles, "Seed quality. From a phone." fully readable
2. Capture & scan — 4.5s — framing guide locks teal, seed outlines segment one by one
3. Batch Result — 5.5s — score + confidence chip + class chips arrive one by one in real status colors + histogram draws in
4. NIR fusion — 3s — simulated NIR connect → combined result with purple spectral graph, score ticks up
5. Outro — 5s — wordmark + punchline + footnote, all hold together; music fades to silence under the final still frame

## Audio
- Audio role: sparse professional accents over a low, restrained bed
- Audio arc: bed enters quietly under the hook, stays low and steady through capture/result, one distinct tone on NIR connect, fades fully to silence under the final wordmark hold
- Music: `happy-beats-business-moves-vol-9-by-ende-dot-app.mp3` (copied to `composition/assets/music/`) — mixed well below its native energy (target gain roughly 0.18-0.22) so its native "happy beats" character reads as a steady unobtrusive pulse, not upbeat
- Music treatment: fade in over ~0.6s at t=0; hold low through t≈16s; fade out over the last ~3s of the video so the final ~1s is silent
- Music cue guidance: preset at `<skill-dir>/assets/music/cues/happy-beats-business-moves-vol-9-by-ende-dot-app.music-cues.json` (114.84 BPM). Candidate strong cues inside the 0-20s window: 4.23s, 6.34s, 10.54s, 12.65s. Treat as optional — the restrained tone should win over hitting every cue; align at most 1-2 major reveals (batch-score settle, NIR connect) near a nearby strong cue within ~0.15s if it doesn't fight the reading-time floor.
- Audio-reactive treatment: **none, by design** — the brag-plan's restraint rule for the `polished` tone explicitly rules out audio-reactive glow/presence ("this tone wants stillness"). This intentionally overrides the generic audio-reactive checklist item; documented here rather than wired in.
- Audio-coupled moments:
  - Scene 2 (capture & scan) — a soft, quiet tick per seed outline landing (8-10 ticks, fast succession)
  - Scene 3 (batch result) — one clear, clean confirm tone exactly as the batch score number settles
  - Scene 4 (NIR fusion) — one distinct tone (different timbre from Scene 3's confirm) on the NIR "connected" state; no sound under the final outro hold
- SFX selection guidance: choose quiet, low-high-frequency-risk sounds for the repeated per-seed ticks (Scene 2) since they repeat 8-10x; the two "payoff" tones (batch score, NIR connect) may sit a little more present since each only fires once
- SFX analysis guidance: use `sfx-analysis.md` from this skill's assets if present when selecting exact files
- Exact SFX choice: Hyperframes should choose exact filenames/timestamps/density/volume once the animation implementation exists
- Audio files: music is already copied to `composition/assets/music/`; copy any selected SFX into `composition/assets/sfx/`

## Hyperframes Instructions
Build `composition/index.html` as a monolithic single-file composition (4 scenes, 20s total — small enough that sub-compositions are not needed) using native Hyperframes conventions: one root `data-composition-id`, one paused GSAP timeline registered on `window.__timelines`, each scene a `<section class="clip">` with its own `data-start`/`data-duration`. Follow `hyperframes-core` (data-attributes, determinism, media rules), `hyperframes-animation` (motion), `hyperframes-creative` (restraint/typography), `hyperframes-keyframes` (if any punch-in/reframe is used), and `hyperframes-cli` (lint/check/render). This is `/brag`'s own workflow — do not enter the generic `hyperframes` intent interview or its promo/launch-video template.

Requirements:
- Show at least one real UI/copy element from the source project (batch result screen layout + copy, NIR simulated badge) — satisfied by Scenes 2-4.
- Keep all text readable: short labels ≥0.8s settled, the hook sentence ≥1.2s settled per the reading-time floor.
- Total duration stays 15-25s (target 22s; scenes sum to 4+4.5+5.5+3+5=22).
- Include the planned music layer (not disabled); audio-reactive is intentionally skipped per the plan's restraint rule (see above), not because extraction failed.
- Treat `/brag`'s audio notes (ticks, confirm tone, NIR tone) as guidance; choose exact SFX files/timestamps after the visual animation exists.
- Lock at most 1-2 major reveals near a strong cue (±0.15s); do not force every tween onto the beat grid — readability and the polished tone's restraint come first.
- Run `npx hyperframes check` before render — it is the single gate.
- Keep creation and rendering local; no cloud/publish workflow requested.

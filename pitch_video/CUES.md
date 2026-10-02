# AgriSpectra: stage script and video cues

Put `player.html` and the seven MP4 files together in one folder, open `player.html` in Chrome on the presentation laptop, and press **F** for fullscreen.
Each click (→, Space, Page Down, or a presenter clicker) starts the next clip. A clip plays
its animation and then **holds on its last frame** until you click again, so
you set the pace and never have to chase the video.

Click **on the first word** of each block below. The animation is timed to a calm
~140 words/min read. If you run long, the clip just waits on its final frame.

| Key | Action |
|---|---|
| → / Space / Page Down / click | next cue |
| ← / Page Up | previous cue |
| R | replay current cue |
| 1–7 | jump to cue |
| B | black screen (toggle) |
| H | show cue number (bottom-left) |

---

### CUE 1: The problem (27 s)
> "Every season, millions of farmers make a bet they can't check. They buy seed at the counter on trust, with no quick, affordable way to test it. When that seed is bad, they don't find out at the shop. They find out weeks later, in an empty field. By then the money, the land and the season are gone."

Seed bag → magnifier "?" → timeline (shop → week 3) with a field where most rows fail →
per-acre loss bar builds to **Rs 87,187** → "A 5-acre farmer: Rs 4.36 lakh gone in one season."
*(Punjab Agriculture Dept, wheat cost of production 2023–24, pre-harvest costs.)*

### CUE 2: The scale (16 s)
> "In Pakistan, agriculture employs one in three workers. Fake and substandard seed is so common that authorities have banned 392 companies for selling it. At that scale, one bad bag becomes a national loss."

Pakistan dot map → 1 in 3 dots go green, counter to **25.5 million** → **392** slams in → red spreads across the map.

### CUE 3: AgriSpectra AI (19 s)
> "AgriSpectra solves this. The AgriSpectra AI provides preliminary, non-destructive seed quality screening from a smartphone camera. It finds every seed, scores each one, and gives you a full batch report based on growth-tested models."

Phone: capture → rings snap on 42 objects → score **87** → class chips → histogram →
**Expected germination 68%** (34 good, 4 damaged, 2 shriveled, using the 75/45/0/0% growth-test rates) → PDF report slides out.

### CUE 4: Lab vs AgriSpectra (15 s)
> "Compare that to a lab. A spectroscopy test takes 3–4 days and costs up to five figures. AgriSpectra gives you an answer at the counter, before you pay, and scanning with your phone costs nothing."

Split screen: lab calendar flips Day 1 → Day 4, courier van, Rs 10,000+ ·
AgriSpectra stopwatch finishes in 10 s while the lab is still on Day 1 → "Answer at the counter. Before you pay." → **Rs 0**.

### CUE 5: The turn (14 s)
> "But a camera can only see so far. A seed can look perfect on the outside and be dead on the inside. That's where AgriSpectra NIR comes in."

Macro barley seed in a camera frame ("surface only") → "Perfect on the outside." → a scan slice cuts it open,
embryo darkens and moisture spots spread → "Dead on the inside." → **hard cut to black** → the device rises
out of the dark, status LED pulses → "Introducing AgriSpectra NIR".
*Tip: land "That's where…" on the black beat (~8.5 s).*

### CUE 6: The device (28 s)
> "Eighteen channels of near-infrared spectroscopy look inside the seed, reading moisture content, pigment difference, lipid and protein variation, and signs of degradation. It compares that fingerprint against growth-tested reference samples to estimate germination viability, then sends the result straight to your phone. One button. No screen. Fits in your hand."

Exploded view with labels (top cover, ESP32, TP4056 + LDO, 18650, white LED, AS7265x, sample tray, drawer) →
"Light in. Fingerprint out.": LED → seed → sensor light path, 18-band spectrum, the four property chips →
"Does it grow?": sample vs Good 75% / Damaged 45% / Broken 0% references → **72% estimated viability** →
Bluetooth pulse to the phone (score 91) → **One button. No screen. Fits in your hand.** + specs line.
*Tip: say "One button" as the button press animates (~22.4 s).*

### CUE 7: The close (16 s)
> "A farmer shouldn't have to gamble a whole season on a bag of seed. With AgriSpectra, the phone sees the outside. The NIR sees the inside. And the farmer knows before they plant.
> **AgriSpectra. Know what you sow.**"

Line on black → phone · seed (half outside / half inside) · device → they converge → white flash →
green end card: logo, **AgriSpectra**, **Know what you sow.**, *Seeds Today, Bigger Tomorrows*, Better Seeds · Stronger Communities · A Greener Planet.
*Tip: pause after "before they plant", then click and say the last line over the logo.*

---

**Punchline:** "Know what you sow." It echoes "you reap what you sow", fits the brand's
seed/scan idea, and is short enough to land as the logo appears. Keep "Seeds Today, Bigger Tomorrows" as the on-screen tagline under it.

**Sources shown on screen:** Pakistan Bureau of Statistics, Labour Force Survey 2024–25 (agriculture 33.1% of employed, 25.5 M);
Crop Reporting Service, Agriculture Dept. Punjab, Cost of Production: Wheat 2023–24 (Rs 104,292/acre total; Rs 87,187 excluding harvesting);
seed-company bans as reported by SecuringIndustry.com.

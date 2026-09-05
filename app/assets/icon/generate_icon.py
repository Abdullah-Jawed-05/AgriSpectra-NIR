"""One-off generator for the AgriSpectra app icon source images.

Not part of the build — run manually whenever the mark changes, then
re-run `flutter pub run flutter_launcher_icons` to regenerate the actual
platform icons from icon.png / icon_foreground.png.

Draws the exact same seed-silhouette-plus-scan-band path as
app/lib/presentation/widgets/agrispectra_mark.dart and
app/lib/export/scan_report_pdf.dart (three renderers, one shape, kept in
sync by hand since each runs on a different graphics stack).
"""

from __future__ import annotations

from PIL import Image, ImageDraw

TEAL = (14, 110, 93, 255)  # 0xFF0E6E5D — AppColors.accent
WHITE = (247, 248, 247, 255)  # 0xFFF7F8F7 — AppColors.background


def cubic_bezier(p0, p1, p2, p3, steps=40):
    pts = []
    for i in range(steps + 1):
        t = i / steps
        mt = 1 - t
        x = mt**3 * p0[0] + 3 * mt**2 * t * p1[0] + 3 * mt * t**2 * p2[0] + t**3 * p3[0]
        y = mt**3 * p0[1] + 3 * mt**2 * t * p1[1] + 3 * mt * t**2 * p2[1] + t**3 * p3[1]
        pts.append((x, y))
    return pts


def seed_polygon(cx: float, cy: float, scale: float) -> list[tuple[float, float]]:
    """The seed silhouette in a local 0..100 space, centered at (cx, cy)
    and scaled by `scale` (100 units -> `scale` px)."""

    def p(x, y):
        return (cx + (x - 50) * scale / 100, cy + (y - 50) * scale / 100)

    top, bottom = p(50, 14), p(50, 90)
    right1, right2 = p(71, 30), p(71, 70)
    left1, left2 = p(29, 70), p(29, 30)

    pts = cubic_bezier(top, right1, right2, bottom)
    pts += cubic_bezier(bottom, left1, left2, top)
    return pts


def band_box(cx: float, cy: float, scale: float) -> tuple[float, float, float, float]:
    x0 = cx + (20 - 50) * scale / 100
    x1 = cx + (80 - 50) * scale / 100
    y0 = cy + (42 - 50) * scale / 100
    y1 = cy + (53 - 50) * scale / 100
    return x0, y0, x1, y1


def make_flat_icon(size: int) -> Image.Image:
    """Full-bleed: teal background, white seed with a teal cutout band —
    for iOS / web / legacy Android, which apply their own corner masking."""
    img = Image.new('RGBA', (size, size), TEAL)
    draw = ImageDraw.Draw(img)
    cx = cy = size / 2
    scale = size * 0.74
    draw.polygon(seed_polygon(cx, cy, scale), fill=WHITE)
    draw.rectangle(band_box(cx, cy, scale), fill=TEAL)
    return img


def make_adaptive_foreground(size: int) -> Image.Image:
    """Transparent background, seed scaled down to sit inside Android's
    adaptive-icon safe zone (~66% of canvas) — the background layer
    (solid teal, see pubspec.yaml's flutter_launcher_icons config) shows
    through both the surrounding margin and the cutout band."""
    img = Image.new('RGBA', (size, size), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)
    cx = cy = size / 2
    scale = size * 0.5
    draw.polygon(seed_polygon(cx, cy, scale), fill=WHITE)
    draw.rectangle(band_box(cx, cy, scale), fill=(0, 0, 0, 0))
    return img


if __name__ == '__main__':
    make_flat_icon(1024).save('icon.png')
    make_adaptive_foreground(1024).save('icon_foreground.png')
    print('Wrote icon.png and icon_foreground.png')

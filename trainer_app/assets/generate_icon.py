"""One-off generator for the Trainer app's window/taskbar icon.

Reuses the exact same seed-silhouette-plus-scan-band mark as
app/assets/icon/generate_icon.py (the phone app) so the two tools read as
siblings, per docs/TRAINER_APP_BUILD_PROMPT.md §1. Not part of the build —
run manually if the mark ever changes.
"""

from __future__ import annotations

from PIL import Image, ImageDraw

TEAL = (14, 110, 93, 255)  # 0xFF0E6E5D
WHITE = (247, 248, 247, 255)


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


def make_icon(size: int) -> Image.Image:
    img = Image.new("RGBA", (size, size), TEAL)
    draw = ImageDraw.Draw(img)
    cx = cy = size / 2
    scale = size * 0.74
    draw.polygon(seed_polygon(cx, cy, scale), fill=WHITE)
    draw.rectangle(band_box(cx, cy, scale), fill=TEAL)
    return img


if __name__ == "__main__":
    make_icon(1024).save("icon.png")
    print("Wrote icon.png")

"""Color/texture/damage feature extraction — the Python counterpart to
app/lib/ml/feature_extractor.dart. Geometry features come from
segmentation.py (mirroring the Dart SeedFinder) since they're computed as
part of finding the blob in the first place.

Keep this in sync with the Dart implementation deliberately: a model
trained on features computed here is only valid for on-device use if the
app extracts the same features the same way (see segmentation.py
docstring). Two things below are NOT just "close to" the Dart side, they're
literal ports of its formulas, on purpose:

- `_rgb_to_hsv` / `_rgb_to_lab` reproduce app/lib/ml/feature_extractor.dart's
  `_rgbToHsv` / `_rgbToLab` exactly, in float64, rather than going through
  cv2.cvtColor's 8-bit-quantized HSV/Lab conversion (2-degree hue steps, a
  uint8 round-trip for Lab) — that quantization is a real, avoidable source
  of drift from what the app computes at inference time.
- `_hole_ratio` flood-fills from every border pixel of the crop, not a
  single corner (see its docstring) — the same definition as
  app/lib/ml/feature_extractor.dart's `_countHolePixels`.
"""

from __future__ import annotations

from collections import deque

import cv2
import numpy as np

from .segmentation import SegmentedSeed


def _rgb_to_hsv(r: np.ndarray, g: np.ndarray, b: np.ndarray) -> tuple[np.ndarray, np.ndarray, np.ndarray]:
    """Exact port of feature_extractor.dart's _rgbToHsv: hue in degrees
    0..360, saturation/value in 0..1 float precision."""
    rn, gn, bn = r / 255.0, g / 255.0, b / 255.0
    maxv = np.maximum(np.maximum(rn, gn), bn)
    minv = np.minimum(np.minimum(rn, gn), bn)
    delta = maxv - minv

    is_r = (delta != 0) & (maxv == rn)
    is_g = (delta != 0) & (maxv == gn) & ~is_r
    is_b = (delta != 0) & ~is_r & ~is_g

    safe_delta = np.where(delta == 0, 1, delta)  # avoid div-by-zero; masked out by is_r/is_g/is_b below
    hue = np.zeros_like(rn)
    hue = np.where(is_r, 60 * (((gn - bn) / safe_delta) % 6), hue)
    hue = np.where(is_g, 60 * (((bn - rn) / safe_delta) + 2), hue)
    hue = np.where(is_b, 60 * (((rn - gn) / safe_delta) + 4), hue)
    hue = np.where(hue < 0, hue + 360, hue)

    safe_maxv = np.where(maxv == 0, 1, maxv)
    saturation = np.where(maxv == 0, 0.0, delta / safe_maxv)
    return hue, saturation, maxv


def _rgb_to_lab(r: np.ndarray, g: np.ndarray, b: np.ndarray) -> tuple[np.ndarray, np.ndarray, np.ndarray]:
    """Exact port of feature_extractor.dart's _rgbToLab: sRGB -> linear ->
    XYZ -> CIE Lab, D65 white point, full float precision."""

    def to_linear(c: np.ndarray) -> np.ndarray:
        v = c / 255.0
        return np.where(v <= 0.04045, v / 12.92, ((v + 0.055) / 1.055) ** 2.4)

    rl, gl, bl = to_linear(r), to_linear(g), to_linear(b)
    x = rl * 0.4124 + gl * 0.3576 + bl * 0.1805
    y = rl * 0.2126 + gl * 0.7152 + bl * 0.0722
    z = rl * 0.0193 + gl * 0.1192 + bl * 0.9505

    xn, yn, zn = 0.95047, 1.0, 1.08883

    def f(t: np.ndarray) -> np.ndarray:
        return np.where(t > 0.008856, np.cbrt(t), (7.787 * t) + (16 / 116))

    fx, fy, fz = f(x / xn), f(y / yn), f(z / zn)
    l = (116 * fy) - 16
    a = 500 * (fx - fy)
    b_lab = 200 * (fy - fz)
    return l, a, b_lab


def color_features(seed: SegmentedSeed) -> dict:
    mask = seed.mask > 0
    bgr = seed.crop_bgr
    if not mask.any():
        return {
            "mean_r": 0.0,
            "mean_g": 0.0,
            "mean_b": 0.0,
            "mean_hue": 0.0,
            "mean_saturation": 0.0,
            "mean_value": 0.0,
            "mean_lab_l": 0.0,
            "mean_lab_a": 0.0,
            "mean_lab_b": 0.0,
            "color_variance_rgb": 0.0,
            "discoloration_ratio": 0.0,
        }

    pixels_bgr = bgr[mask].astype(np.float64)
    b_ch, g_ch, r_ch = pixels_bgr[:, 0], pixels_bgr[:, 1], pixels_bgr[:, 2]
    mean_r, mean_g, mean_b = float(r_ch.mean()), float(g_ch.mean()), float(b_ch.mean())
    variance = float(r_ch.var() + g_ch.var() + b_ch.var())

    hue, sat, val = _rgb_to_hsv(r_ch, g_ch, b_ch)
    mean_h = float(hue.mean())
    mean_s = float(sat.mean())
    mean_v = float(val.mean())

    lab_l, lab_a, lab_b = _rgb_to_lab(r_ch, g_ch, b_ch)
    mean_l, mean_a, mean_b_lab = float(lab_l.mean()), float(lab_a.mean()), float(lab_b.mean())

    # Discoloration proxy: fraction of foreground pixels whose hue departs
    # more than 40 degrees from the seed's own mean hue (circular
    # difference) — matches feature_extractor.dart's discolorationRatio.
    hue_diff = np.abs(hue - mean_h)
    hue_diff = np.minimum(hue_diff, 360 - hue_diff)
    discoloration_ratio = float(np.mean(hue_diff > 40))

    return {
        "mean_r": mean_r,
        "mean_g": mean_g,
        "mean_b": mean_b,
        "mean_hue": mean_h,
        "mean_saturation": mean_s,
        "mean_value": mean_v,
        "mean_lab_l": mean_l,
        "mean_lab_a": mean_a,
        "mean_lab_b": mean_b_lab,
        "color_variance_rgb": variance,
        "discoloration_ratio": discoloration_ratio,
    }


def _sobel_gradient_magnitude(gray: np.ndarray) -> np.ndarray:
    """|Gx| + |Gy| via a 3x3 Sobel kernel, OpenCV's default
    BORDER_REFLECT_101 edge handling — matches
    feature_extractor.dart's _sobelMagnitude."""
    sobel_x = cv2.Sobel(gray, cv2.CV_32F, 1, 0, ksize=3)
    sobel_y = cv2.Sobel(gray, cv2.CV_32F, 0, 1, ksize=3)
    return np.abs(sobel_x) + np.abs(sobel_y)


# Matches feature_extractor.dart's _edgeGradientThreshold. Calibrated for
# the |Gx|+|Gy| scale a 3x3 Sobel kernel produces.
_EDGE_GRADIENT_THRESHOLD = 60


def texture_features(seed: SegmentedSeed) -> dict:
    mask = seed.mask > 0
    gray = cv2.cvtColor(seed.crop_bgr, cv2.COLOR_BGR2GRAY)
    if not mask.any():
        return {"edge_density": 0.0, "entropy": 0.0, "surface_irregularity": 0.0, "local_contrast": 0.0}

    gradient = _sobel_gradient_magnitude(gray)
    fg_gradient = gradient[mask]
    edge_density = float(np.mean(fg_gradient > _EDGE_GRADIENT_THRESHOLD))
    local_contrast = float(np.clip(fg_gradient.mean() / 255, 0, 1))

    hist, _ = np.histogram(gray[mask], bins=256, range=(0, 256))
    probs = hist / hist.sum()
    probs = probs[probs > 0]
    entropy = float(-(probs * np.log2(probs)).sum() / 8.0)

    return {
        "edge_density": edge_density,
        "entropy": entropy,
        "surface_irregularity": edge_density,
        "local_contrast": local_contrast,
    }


def _hole_ratio(mask: np.ndarray) -> float:
    """Background pixels enclosed by foreground (topological holes):
    flood-fill every background pixel reachable (4-connected) from the
    crop's border, then any background pixel the flood never reaches is an
    enclosed pocket.

    Deliberately seeds the flood from the *whole* border, not a single
    corner (a naive `cv2.floodFill(..., (0, 0), ...)` silently
    misclassifies the entire outside as "holes" whenever the mask happens
    to touch its own bounding-box corner) — matches
    feature_extractor.dart's `_countHolePixels`.
    """
    h, w = mask.shape
    background = ~mask
    reached = np.zeros((h, w), dtype=bool)
    q: deque[tuple[int, int]] = deque()

    def seed_pixel(y: int, x: int) -> None:
        if 0 <= y < h and 0 <= x < w and background[y, x] and not reached[y, x]:
            reached[y, x] = True
            q.append((y, x))

    for x in range(w):
        seed_pixel(0, x)
        seed_pixel(h - 1, x)
    for y in range(h):
        seed_pixel(y, 0)
        seed_pixel(y, w - 1)

    while q:
        y, x = q.popleft()
        seed_pixel(y - 1, x)
        seed_pixel(y + 1, x)
        seed_pixel(y, x - 1)
        seed_pixel(y, x + 1)

    holes = background & ~reached
    total_fg = int(mask.sum())
    return float(np.clip(holes.sum() / total_fg, 0, 1)) if total_fg > 0 else 0.0


def damage_indicators(seed: SegmentedSeed, color: dict) -> dict:
    mask = seed.mask > 0
    gray = cv2.cvtColor(seed.crop_bgr, cv2.COLOR_BGR2GRAY)
    if not mask.any():
        return {
            "dark_region_ratio": 0.0,
            "crack_like_edge_ratio": 0.0,
            "hole_ratio": 0.0,
            "abnormal_pigmentation_score": 0.0,
        }

    dark_ratio = float(np.mean(gray[mask] < 60))
    hole_ratio = _hole_ratio(mask)

    avg_luminance = float(gray[mask].mean())
    pigmentation_score = float(
        np.clip(color["discoloration_ratio"] * 0.6 + (0.4 if avg_luminance < 70 else 0.0), 0, 1)
    )

    texture = texture_features(seed)

    return {
        "dark_region_ratio": dark_ratio,
        "crack_like_edge_ratio": texture["edge_density"],
        "hole_ratio": hole_ratio,
        "abnormal_pigmentation_score": pigmentation_score,
    }


def extract_all(seed: SegmentedSeed) -> dict:
    """Flat feature dict, one row's worth, matching SeedFeatures.toJson()'s
    field names in the Dart domain layer (app/lib/domain/entities/seed_features.dart)."""
    color = color_features(seed)
    texture = texture_features(seed)
    damage = damage_indicators(seed, color)

    return {
        "area_px": seed.area_px,
        "perimeter_px": seed.perimeter_px,
        "width_px": seed.width_px,
        "length_px": seed.length_px,
        "aspect_ratio": seed.aspect_ratio,
        "circularity": seed.circularity,
        "eccentricity": seed.eccentricity,
        "convexity": seed.convexity,
        **color,
        **texture,
        **damage,
    }

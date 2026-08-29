"""Color/texture/damage feature extraction — the Python counterpart to
app/lib/ml/feature_extractor.dart. Geometry features come from
segmentation.py (mirroring the Dart SeedFinder) since they're computed as
part of finding the blob in the first place.

Keep this in sync with the Dart implementation deliberately: a model
trained on features computed here is only valid for on-device use if the
app extracts the same features the same way (see segmentation.py docstring).
"""

from __future__ import annotations

import cv2
import numpy as np

from .segmentation import SegmentedSeed


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
    mean_b, mean_g, mean_r = pixels_bgr.mean(axis=0)
    variance = float(pixels_bgr.var(axis=0).sum())

    hsv = cv2.cvtColor(bgr, cv2.COLOR_BGR2HSV)
    pixels_hsv = hsv[mask].astype(np.float64)
    mean_h = float(pixels_hsv[:, 0].mean()) * 2  # OpenCV hue is 0..179
    mean_s = float(pixels_hsv[:, 1].mean()) / 255
    mean_v = float(pixels_hsv[:, 2].mean()) / 255

    lab = cv2.cvtColor(bgr, cv2.COLOR_BGR2LAB)
    pixels_lab = lab[mask].astype(np.float64)
    mean_l = float(pixels_lab[:, 0].mean()) * 100 / 255
    mean_a = float(pixels_lab[:, 1].mean()) - 128
    mean_b_lab = float(pixels_lab[:, 2].mean()) - 128

    hue_diff = np.abs(pixels_hsv[:, 0] * 2 - mean_h)
    hue_diff = np.minimum(hue_diff, 360 - hue_diff)
    discoloration_ratio = float(np.mean(hue_diff > 40))

    return {
        "mean_r": float(mean_r),
        "mean_g": float(mean_g),
        "mean_b": float(mean_b),
        "mean_hue": mean_h,
        "mean_saturation": mean_s,
        "mean_value": mean_v,
        "mean_lab_l": mean_l,
        "mean_lab_a": mean_a,
        "mean_lab_b": mean_b_lab,
        "color_variance_rgb": variance,
        "discoloration_ratio": discoloration_ratio,
    }


def texture_features(seed: SegmentedSeed) -> dict:
    mask = seed.mask > 0
    gray = cv2.cvtColor(seed.crop_bgr, cv2.COLOR_BGR2GRAY)
    if not mask.any():
        return {"edge_density": 0.0, "entropy": 0.0, "surface_irregularity": 0.0, "local_contrast": 0.0}

    sobel_x = cv2.Sobel(gray, cv2.CV_32F, 1, 0, ksize=3)
    sobel_y = cv2.Sobel(gray, cv2.CV_32F, 0, 1, ksize=3)
    gradient = np.abs(sobel_x) + np.abs(sobel_y)

    fg_gradient = gradient[mask]
    edge_density = float(np.mean(fg_gradient > 60))
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

    # Holes: background pixels strictly inside the mask (topological holes),
    # found the same way the Dart segmenter does — fill from the border and
    # anything unfilled-but-background inside is an enclosed pocket.
    inv_mask = (~mask).astype(np.uint8) * 255
    h, w = inv_mask.shape
    flood_mask = np.zeros((h + 2, w + 2), np.uint8)
    filled = inv_mask.copy()
    cv2.floodFill(filled, flood_mask, (0, 0), 128)
    holes = (inv_mask == 255) & (filled != 128)
    hole_ratio = float(np.clip(holes.sum() / mask.sum(), 0, 1))

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

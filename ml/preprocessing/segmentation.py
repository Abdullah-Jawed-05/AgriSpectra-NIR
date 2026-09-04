"""Classical seed detection/segmentation for the Python training pipeline.

Deliberately mirrors app/lib/ml/seed_finder.dart (Otsu threshold + connected
components, both polarities tried, filtered by area fraction, moment-based
ellipse, traced-contour perimeter/hull) so that features computed here for
training and features computed on-device at inference time come from the
same algorithm. If these two ever drift apart, a model trained here will not
transfer to what the app actually extracts at runtime — keep them in sync
deliberately, not accidentally.
"""

from __future__ import annotations

from dataclasses import dataclass

import cv2
import numpy as np

MIN_AREA_FRACTION = 0.00025
MAX_AREA_FRACTION = 0.08


@dataclass
class SegmentedSeed:
    seed_id: str
    crop_bgr: np.ndarray
    mask: np.ndarray  # uint8, 0/255, same shape as crop_bgr[:, :, 0]
    bbox: tuple[int, int, int, int]  # x, y, w, h
    area_px: float
    perimeter_px: float
    width_px: float
    length_px: float
    aspect_ratio: float
    circularity: float
    eccentricity: float
    convexity: float


def _otsu_binary(gray: np.ndarray) -> tuple[np.ndarray, np.ndarray]:
    """Returns (dark_foreground_mask, light_foreground_mask), both uint8 0/255."""
    _, dark = cv2.threshold(gray, 0, 255, cv2.THRESH_BINARY_INV + cv2.THRESH_OTSU)
    light = cv2.bitwise_not(dark)
    return dark, light


def _valid_components(mask: np.ndarray, image_area: int):
    n_labels, labels, stats, centroids = cv2.connectedComponentsWithStats(mask, connectivity=8)
    min_area = image_area * MIN_AREA_FRACTION
    max_area = image_area * MAX_AREA_FRACTION
    valid = []
    for label in range(1, n_labels):  # label 0 is background
        area = stats[label, cv2.CC_STAT_AREA]
        if min_area <= area <= max_area:
            valid.append(label)
    return n_labels, labels, stats, centroids, valid


def _moment_ellipse(component_mask: np.ndarray) -> tuple[float, float, float]:
    """Equivalent-ellipse width/length/eccentricity from the mask's second
    central moments — the same formula as _buildSegmentedSeed in
    app/lib/ml/seed_finder.dart. Deliberately NOT cv2.fitEllipse: fitEllipse
    fits a conic to the boundary *contour* (a different, harder-to-replicate
    algorithm), whereas the moment-based equivalent ellipse is well-defined
    for any mask, numerically simple, and trivial to keep identical on both
    sides of the training/inference split.
    """
    m = cv2.moments(component_mask, binaryImage=True)
    area = m["m00"]
    if area <= 0:
        return 0.0, 0.0, 0.0
    cx, cy = m["m10"] / area, m["m01"] / area
    mu20 = m["mu20"] / area
    mu02 = m["mu02"] / area
    mu11 = m["mu11"] / area

    common = float(np.sqrt((mu20 - mu02) ** 2 + 4 * mu11**2))
    lambda1 = max(0.0, (mu20 + mu02 + common) / 2)
    lambda2 = max(0.0, (mu20 + mu02 - common) / 2)
    length = 4 * np.sqrt(lambda1)
    width = 4 * np.sqrt(lambda2)
    eccentricity = float(np.sqrt(max(0.0, 1 - (lambda2 / lambda1)))) if lambda1 > 0 else 0.0
    return float(width), float(length), eccentricity


def find_seeds(image_bgr: np.ndarray, working_max_dim: int = 1100) -> list[SegmentedSeed]:
    h0, w0 = image_bgr.shape[:2]
    scale = min(1.0, working_max_dim / max(h0, w0))
    image = (
        cv2.resize(
            image_bgr,
            (int(w0 * scale), int(h0 * scale)),
            interpolation=cv2.INTER_LINEAR,
        )
        if scale < 1.0
        else image_bgr
    )

    gray = cv2.cvtColor(image, cv2.COLOR_BGR2GRAY)
    dark_mask, light_mask = _otsu_binary(gray)
    image_area = gray.shape[0] * gray.shape[1]

    dark_result = _valid_components(dark_mask, image_area)
    light_result = _valid_components(light_mask, image_area)

    use_dark = len(dark_result[4]) >= len(light_result[4])
    n_labels, labels, stats, centroids, valid = dark_result if use_dark else light_result

    seeds: list[SegmentedSeed] = []
    for i, label in enumerate(valid):
        x, y, w, h, area = stats[label]
        component_mask = (labels[y : y + h, x : x + w] == label).astype(np.uint8) * 255
        crop = image[y : y + h, x : x + w]

        contours, _ = cv2.findContours(component_mask, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_NONE)
        if not contours:
            continue
        contour = max(contours, key=cv2.contourArea)
        perimeter = cv2.arcLength(contour, True)
        circularity = float(np.clip(4 * np.pi * area / (perimeter**2), 0, 1)) if perimeter > 0 else 0.0

        hull = cv2.convexHull(contour)
        hull_area = cv2.contourArea(hull)
        convexity = float(np.clip(area / hull_area, 0, 1)) if hull_area > 0 else 0.0

        width_px, length_px, eccentricity = _moment_ellipse(component_mask)
        aspect_ratio = length_px / width_px if width_px > 0 else 0.0

        seeds.append(
            SegmentedSeed(
                seed_id=f"seed_{i + 1:03d}",
                crop_bgr=crop,
                mask=component_mask,
                bbox=(int(x), int(y), int(w), int(h)),
                area_px=float(area),
                perimeter_px=float(perimeter),
                width_px=width_px,
                length_px=length_px,
                aspect_ratio=aspect_ratio,
                circularity=circularity,
                eccentricity=eccentricity,
                convexity=convexity,
            )
        )
    return seeds

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

from .seed_splitter import SPLIT_AREA_MULTIPLE, split_component

MIN_AREA_FRACTION = 0.00025
MAX_AREA_FRACTION = 0.08

_EXPOSURE_TARGET_MEAN = 128.0
_MIN_CHANNEL_SCALE = 0.5
_MAX_CHANNEL_SCALE = 2.0


def _normalise_lighting(image_bgr: np.ndarray) -> np.ndarray:
    """Gray-world white balance + an exposure pull to a fixed mid-grey.
    Without this, colour features and the Otsu threshold encode which
    lighting the photo was shot under, not the seed (see
    docs/VALIDATION.md's cross-session result). Must stay identical to
    app/lib/ml/seed_finder.dart::_normaliseLighting.
    """
    b, g, r = (image_bgr[:, :, i].mean() for i in range(3))
    overall = (r + g + b) / 3
    if overall <= 0:
        return image_bgr

    exposure = float(np.clip(_EXPOSURE_TARGET_MEAN / overall, _MIN_CHANNEL_SCALE, _MAX_CHANNEL_SCALE))
    scale_b = float(np.clip(overall / b, _MIN_CHANNEL_SCALE, _MAX_CHANNEL_SCALE)) * exposure
    scale_g = float(np.clip(overall / g, _MIN_CHANNEL_SCALE, _MAX_CHANNEL_SCALE)) * exposure
    scale_r = float(np.clip(overall / r, _MIN_CHANNEL_SCALE, _MAX_CHANNEL_SCALE)) * exposure

    out = image_bgr.astype(np.float32)
    out[:, :, 0] *= scale_b
    out[:, :, 1] *= scale_g
    out[:, :, 2] *= scale_r
    return np.clip(np.round(out), 0, 255).astype(np.uint8)


# --- Background-texture gate -------------------------------------------------
# Mirrors app/lib/ml/image_quality_gate.dart::_tileTextureStats + the hard
# reject rule. A seed photo shot on a woven mat / fabric / wood grain /
# printed surface fragments into dozens of spurious blobs; such images poison
# a training set (see docs/VALIDATION.md — Barley Dataset V2). Tuned on 158
# clean + 270 textured barley photos: 0% false-reject on the clean set,
# ~98% caught on the textured set.
_TEXTURE_WORKING_MAX = 900
_TEXTURE_TILE_PX = 48
_TEXTURE_BUSY_TILE_LAPVAR = 40.0
_TEXTURE_FLAT_TILE_STDDEV = 6.0
_TEXTURE_REJECT_BUSY_RATIO = 0.62
_TEXTURE_REJECT_MEDIAN_STDDEV = 3.2

_LAPLACIAN_4 = np.array([[0, -1, 0], [-1, 4, -1], [0, -1, 0]], dtype=np.float32)


@dataclass
class BackgroundTexture:
    median_tile_stddev: float
    busy_tile_ratio: float
    flat_tile_ratio: float

    @property
    def is_textured(self) -> bool:
        return (
            self.busy_tile_ratio > _TEXTURE_REJECT_BUSY_RATIO
            or self.median_tile_stddev > _TEXTURE_REJECT_MEDIAN_STDDEV
        )


def assess_background_texture(image_bgr: np.ndarray) -> BackgroundTexture:
    """Grid pass over a downscaled grey copy: per tile, the luminance
    std-dev and the variance of a 4-neighbour Laplacian. The *median*
    tile std-dev tracks the background (robust to a few seed tiles); the
    busy-tile ratio measures how much of the frame carries real
    high-frequency structure.
    """
    h0, w0 = image_bgr.shape[:2]
    scale = min(1.0, _TEXTURE_WORKING_MAX / max(h0, w0))
    img = (
        cv2.resize(image_bgr, (int(w0 * scale), int(h0 * scale)), interpolation=cv2.INTER_AREA)
        if scale < 1.0
        else image_bgr
    )
    gray = cv2.cvtColor(img, cv2.COLOR_BGR2GRAY).astype(np.float32)
    lap = cv2.filter2D(gray, cv2.CV_32F, _LAPLACIAN_4, borderType=cv2.BORDER_REFLECT_101)

    h, w = gray.shape
    tile = _TEXTURE_TILE_PX
    std_devs: list[float] = []
    busy = flat = tiles = 0
    for ty in range(0, h - tile + 1, tile):
        for tx in range(0, w - tile + 1, tile):
            # sample every other pixel — parity with the Dart gate
            g_tile = gray[ty : ty + tile : 2, tx : tx + tile : 2]
            # interior only for the Laplacian, as the Dart loop does
            l_tile = lap[ty + 1 : ty + tile - 1 : 2, tx + 1 : tx + tile - 1 : 2]
            if g_tile.size == 0 or l_tile.size == 0:
                continue
            std_devs.append(float(g_tile.std()))
            if float(l_tile.var()) > _TEXTURE_BUSY_TILE_LAPVAR:
                busy += 1
            if float(g_tile.std()) < _TEXTURE_FLAT_TILE_STDDEV:
                flat += 1
            tiles += 1

    if tiles == 0:
        return BackgroundTexture(0.0, 0.0, 1.0)
    return BackgroundTexture(
        median_tile_stddev=float(np.median(std_devs)),
        busy_tile_ratio=busy / tiles,
        flat_tile_ratio=flat / tiles,
    )


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


def geometry_from_mask(mask: np.ndarray) -> dict:
    """The full geometry feature set for one binary (0/255) mask: area,
    perimeter, width/length/aspect ratio/eccentricity (moment-based
    ellipse), circularity, convexity. Factored out of `find_seeds` so
    `augment_dataset.py` can recompute geometry for an augmented mask
    (rotated/scaled) using the exact same definitions — there must be only
    one place this math lives, or augmented and real rows would carry
    subtly different feature semantics.
    """
    area = float(cv2.countNonZero(mask))
    if area <= 0:
        return {
            "area_px": 0.0,
            "perimeter_px": 0.0,
            "width_px": 0.0,
            "length_px": 0.0,
            "aspect_ratio": 0.0,
            "circularity": 0.0,
            "eccentricity": 0.0,
            "convexity": 0.0,
        }

    contours, _ = cv2.findContours(mask, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_NONE)
    contour = max(contours, key=cv2.contourArea) if contours else None

    perimeter = cv2.arcLength(contour, True) if contour is not None else 0.0
    circularity = float(np.clip(4 * np.pi * area / (perimeter**2), 0, 1)) if perimeter > 0 else 0.0

    if contour is not None:
        hull = cv2.convexHull(contour)
        hull_area = cv2.contourArea(hull)
    else:
        hull_area = 0.0
    convexity = float(np.clip(area / hull_area, 0, 1)) if hull_area > 0 else 0.0

    width_px, length_px, eccentricity = _moment_ellipse(mask)
    aspect_ratio = length_px / width_px if width_px > 0 else 0.0

    return {
        "area_px": area,
        "perimeter_px": float(perimeter),
        "width_px": width_px,
        "length_px": length_px,
        "aspect_ratio": aspect_ratio,
        "circularity": circularity,
        "eccentricity": eccentricity,
        "convexity": convexity,
    }


def pick_primary_seed(seeds: list[SegmentedSeed]) -> SegmentedSeed | None:
    """For a photo known to contain one subject — a macro shot of a single
    seed, which is how the barley training sets were collected — pick the
    blob that is actually the seed out of everything `find_seeds` returned.
    The rest is background: mat/paper texture, shadows, lighting gradients.

    Scores each blob by how much it looks like a coherent coloured object
    (mean saturation of its own pixels x convexity, with a mild size
    preference), inside a plausible size band relative to the median blob
    — this drops the one giant gradient region and the specks. NOT used by
    the on-device pipeline, which scans real multi-seed batches; this is a
    `prepare_dataset.py --one-seed` concern only.
    """
    import statistics

    if len(seeds) <= 1:
        return seeds[0] if seeds else None

    med = statistics.median(s.area_px for s in seeds)
    lo, hi = 0.2 * med, 20 * med
    candidates = [s for s in seeds if lo <= s.area_px <= hi] or seeds

    best, best_score = None, -1.0
    for s in candidates:
        m = s.mask > 0
        if not m.any():
            continue
        hsv = cv2.cvtColor(s.crop_bgr, cv2.COLOR_BGR2HSV)
        saturation = float(hsv[m][:, 1].mean()) / 255
        score = saturation * max(s.convexity, 0.01) * (s.area_px**0.25)
        if score > best_score:
            best, best_score = s, score
    return best


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
    image = _normalise_lighting(image)

    gray = cv2.cvtColor(image, cv2.COLOR_BGR2GRAY)
    dark_mask, light_mask = _otsu_binary(gray)
    image_area = gray.shape[0] * gray.shape[1]

    dark_result = _valid_components(dark_mask, image_area)
    light_result = _valid_components(light_mask, image_area)

    use_dark = len(dark_result[4]) >= len(light_result[4])
    n_labels, labels, stats, centroids, valid = dark_result if use_dark else light_result

    # Touching-seed split gate: a component is only a split candidate if
    # it's clearly bigger than a typical single seed (25th percentile of
    # component areas) — mirrors ClassicalCVSeedFinder._splitMergedComponents.
    comp_areas = sorted(int(stats[l][4]) for l in valid)
    typical_area = comp_areas[round((len(comp_areas) - 1) * 0.25)] if comp_areas else 0
    split_threshold = typical_area * SPLIT_AREA_MULTIPLE

    seeds: list[SegmentedSeed] = []
    for label in valid:
        x, y, w, h, area = (int(v) for v in stats[label])
        component_mask = (labels[y : y + h, x : x + w] == label).astype(np.uint8) * 255

        sub_masks = [component_mask]
        if len(valid) >= 2 and area >= split_threshold > 0:
            parts = split_component(component_mask)
            if len(parts) >= 2:
                sub_masks = [p.astype(np.uint8) * 255 for p in parts]

        for sub in sub_masks:
            ys, xs = np.nonzero(sub)
            if ys.size == 0:
                continue
            sy0, sy1, sx0, sx1 = ys.min(), ys.max() + 1, xs.min(), xs.max() + 1
            local = sub[sy0:sy1, sx0:sx1]
            crop = image[y + sy0 : y + sy1, x + sx0 : x + sx1]

            geometry = geometry_from_mask(local)
            if geometry["perimeter_px"] <= 0:
                continue

            seeds.append(
                SegmentedSeed(
                    seed_id=f"seed_{len(seeds) + 1:03d}",
                    crop_bgr=crop,
                    mask=local,
                    bbox=(int(x + sx0), int(y + sy0), int(sx1 - sx0), int(sy1 - sy0)),
                    **geometry,
                )
            )
    return seeds

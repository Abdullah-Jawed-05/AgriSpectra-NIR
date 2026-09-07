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

# --- colour-distance segmentation (mirrors seed_finder.dart) ---------------
# Seeds photographed on plain paper are often barely darker than it, so a
# luminance Otsu catches the furrow lines / inter-grain shadows as "seeds"
# and misses the grains. Segment on CIE-Lab chroma (distance from the
# neutral grey axis) instead: a tan/brown grain is chromatic, plain
# paper and a cast shadow are near-neutral. Luminance is kept only as a
# fallback for the case where chroma finds nothing (very dark seeds).
_SHADOW_CHROMA_MAX = 4.0          # a blob this close to neutral is a shadow
_MIN_SEED_AREA_FRACTION = 0.40    # drop blobs < this * median kept-blob area
_PILE_OVERSIZE_FRACTION = 0.05    # a rejected merged blob bigger than this share
                                  # of the frame => the seeds are piled/touching
_SEEDLIKE_MIN_FILL = 0.30         # component area / bbox area, to score a candidate mask
_MIN_CHROMA_FOR_COLOUR = 3.0      # below this peak chroma the image is greyscale
                                  # -> skip the colour channel, use luminance


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


def _chroma_field(image_bgr: np.ndarray) -> np.ndarray:
    """Per-pixel CIE-Lab chroma = sqrt(a*^2 + b*^2): distance from the
    neutral grey axis. Chromatic seed high, plain paper / cast shadow low.
    Uses the same hand-rolled Lab as feature_extractor.dart (imported
    lazily to dodge the features<->segmentation import cycle)."""
    from .features import _rgb_to_lab  # noqa: PLC0415

    b = image_bgr[:, :, 0].astype(np.float64)
    g = image_bgr[:, :, 1].astype(np.float64)
    r = image_bgr[:, :, 2].astype(np.float64)
    _, a_lab, b_lab = _rgb_to_lab(r, g, b)
    return np.sqrt(a_lab * a_lab + b_lab * b_lab)


def _otsu_above(field: np.ndarray) -> np.ndarray:
    """Foreground = field values above an Otsu split of the 0..255-scaled
    field. uint8 0/255 mask."""
    f = field - float(field.min())
    m = float(f.max())
    if m < 1e-6:
        return np.zeros(field.shape, np.uint8)
    f8 = np.clip(f / m * 255.0, 0, 255).astype(np.uint8)
    t, _ = cv2.threshold(f8, 0, 255, cv2.THRESH_BINARY + cv2.THRESH_OTSU)
    return ((f8 > t).astype(np.uint8)) * 255


def _morph_clean(mask: np.ndarray) -> np.ndarray:
    k = np.ones((3, 3), np.uint8)
    return cv2.morphologyEx(cv2.morphologyEx(mask, cv2.MORPH_OPEN, k), cv2.MORPH_CLOSE, k)


def _count_seedlike(mask: np.ndarray, image_area: int) -> int:
    """How many components in `mask` look like a single seed — area in the
    valid band and not a thin sliver. Used to pick between candidate masks."""
    n, _, st, _ = cv2.connectedComponentsWithStats(mask, connectivity=8)
    lo, hi = image_area * MIN_AREA_FRACTION, image_area * MAX_AREA_FRACTION
    c = 0
    for i in range(1, n):
        a = st[i, cv2.CC_STAT_AREA]
        if lo <= a <= hi and a / max(st[i, cv2.CC_STAT_WIDTH] * st[i, cv2.CC_STAT_HEIGHT], 1) >= _SEEDLIKE_MIN_FILL:
            c += 1
    return c


@dataclass
class SegmentationResult:
    seeds: list["SegmentedSeed"]
    channel: str            # "chroma" or "lum_dark"
    piled: bool             # seeds are piled/touching -> per-seed detail is unreliable
    foreground_fraction: float


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
    """Back-compat wrapper — returns just the seed list. Use `segment` for
    the channel / pile metadata."""
    return segment(image_bgr, working_max_dim).seeds


def segment(image_bgr: np.ndarray, working_max_dim: int = 1100) -> SegmentationResult:
    h0, w0 = image_bgr.shape[:2]
    scale = min(1.0, working_max_dim / max(h0, w0))
    image = (
        cv2.resize(image_bgr, (int(w0 * scale), int(h0 * scale)), interpolation=cv2.INTER_LINEAR)
        if scale < 1.0
        else image_bgr
    )
    image = _normalise_lighting(image)
    image_area = image.shape[0] * image.shape[1]

    chroma = _chroma_field(image)

    chroma_mask = None
    if float(chroma.max()) >= _MIN_CHROMA_FOR_COLOUR:
        m = _morph_clean(_otsu_above(chroma))
        if _count_seedlike(m, image_area) > 0:
            chroma_mask = m

    if chroma_mask is not None:
        mask, channel = chroma_mask, "chroma"
    else:
        gray = cv2.cvtColor(image, cv2.COLOR_BGR2GRAY).astype(np.float64)
        mask, channel = _morph_clean(_otsu_above(-gray)), "lum_dark"

    foreground_fraction = float((mask > 0).mean())

    # Shadow rejection only makes sense on the chroma channel — there a
    # near-neutral blob is a cast shadow. On the luminance fallback a
    # low-chroma blob just means the seeds aren't colourful.
    use_shadow_filter = channel == "chroma"

    n_labels, labels, stats, _ = cv2.connectedComponentsWithStats(mask, connectivity=8)
    min_area = image_area * MIN_AREA_FRACTION
    max_area = image_area * MAX_AREA_FRACTION
    valid = [i for i in range(1, n_labels) if min_area <= stats[i, cv2.CC_STAT_AREA] <= max_area]

    def not_shadow_mask(m: np.ndarray) -> bool:
        return (not use_shadow_filter) or float(chroma[m].mean()) >= _SHADOW_CHROMA_MAX

    # A big *seed-coloured* blob rejected as over-size means the seeds are
    # piled / touching — per-seed detail below is unreliable.
    oversize = 0
    for i in range(1, n_labels):
        a = int(stats[i, cv2.CC_STAT_AREA])
        if a <= max_area or a <= _PILE_OVERSIZE_FRACTION * image_area:
            continue
        if not_shadow_mask(labels == i):
            oversize += a
    piled = oversize > _PILE_OVERSIZE_FRACTION * image_area

    comp_areas = sorted(int(stats[l][cv2.CC_STAT_AREA]) for l in valid)
    typical_area = comp_areas[round((len(comp_areas) - 1) * 0.25)] if comp_areas else 0
    split_threshold = typical_area * SPLIT_AREA_MULTIPLE

    # (bbox_x, bbox_y, local_mask uint8 0/255) per candidate piece.
    pieces: list[tuple[int, int, np.ndarray]] = []
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
            pieces.append((x + sx0, y + sy0, sub[sy0:sy1, sx0:sx1]))

    # Shadow rejection: a near-neutral blob is a cast shadow, not a seed.
    kept: list[tuple[int, int, np.ndarray]] = []
    for px, py, local in pieces:
        m = local > 0
        if not m.any():
            continue
        region = np.zeros(chroma.shape, bool)
        region[py : py + local.shape[0], px : px + local.shape[1]] = m
        if not_shadow_mask(region):
            kept.append((px, py, local))

    # Fragment rejection: a blob far below the batch's typical seed size is
    # a furrow line / speck, not a seed.
    if kept:
        med = float(np.median([int((lm > 0).sum()) for _, _, lm in kept]))
        kept = [k for k in kept if int((k[2] > 0).sum()) >= _MIN_SEED_AREA_FRACTION * med]

    seeds: list[SegmentedSeed] = []
    for px, py, local in kept:
        geometry = geometry_from_mask(local)
        if geometry["perimeter_px"] <= 0:
            continue
        crop = image[py : py + local.shape[0], px : px + local.shape[1]]
        seeds.append(
            SegmentedSeed(
                seed_id=f"seed_{len(seeds) + 1:03d}",
                crop_bgr=crop,
                mask=local,
                bbox=(int(px), int(py), int(local.shape[1]), int(local.shape[0])),
                **geometry,
            )
        )

    return SegmentationResult(seeds=seeds, channel=channel, piled=piled, foreground_fraction=foreground_fraction)

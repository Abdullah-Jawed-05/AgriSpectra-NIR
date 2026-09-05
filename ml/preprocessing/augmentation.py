"""Data augmentation for Model V1 training (§18 of the build spec).

Operates on already-segmented `(crop_bgr, mask)` pairs — one seed at a
time, post `prepare_dataset.py` — rather than on raw tray photos. §18's
augmentation list (rotation, scale, brightness, contrast, blur, noise) is
about making the *feature values* the classifier trains on more realistic
and diverse, and those are computed from the segmented crop, not the whole
photo; augmenting at the crop level also means every original seed row can
be re-labelled with confidence (the label is per-seed, not per-photo) and
skips re-running detection, which nothing here needs.

Translation is in §18's list but is deliberately not implemented: a
single-seed crop is already tightly bound to its own bounding box, so
"translating" it just shifts it partially out of frame — a meaningless
augmentation at this pipeline stage (it matters for augmenting whole tray
photos before detection, which this is not).

Every transform takes and returns a `(crop_bgr, mask)` pair so the mask
always stays aligned with the crop — feature extraction depends on that
alignment completely.
"""

from __future__ import annotations

import cv2
import numpy as np

Pair = tuple[np.ndarray, np.ndarray]


def rotate(crop_bgr: np.ndarray, mask: np.ndarray, degrees: float) -> Pair:
    """Small rotation about the crop's own center. Both crop and mask must
    be warped identically and stay in sync; the mask uses nearest-neighbor
    so it stays strictly binary (no antialiased edge values that would
    silently expand or blur what "foreground" means downstream).
    """
    h, w = mask.shape[:2]
    center = (w / 2, h / 2)
    m = cv2.getRotationMatrix2D(center, degrees, 1.0)
    rotated_crop = cv2.warpAffine(crop_bgr, m, (w, h), flags=cv2.INTER_LINEAR, borderMode=cv2.BORDER_CONSTANT)
    rotated_mask = cv2.warpAffine(
        mask, m, (w, h), flags=cv2.INTER_NEAREST, borderMode=cv2.BORDER_CONSTANT, borderValue=0
    )
    return rotated_crop, rotated_mask


def scale(crop_bgr: np.ndarray, mask: np.ndarray, factor: float) -> Pair:
    """Uniform scale around the crop's own center, canvas size unchanged
    (matches what a slightly-nearer/farther capture would look like once
    segmented back to a tight bounding box)."""
    h, w = mask.shape[:2]
    center = (w / 2, h / 2)
    m = cv2.getRotationMatrix2D(center, 0, factor)
    scaled_crop = cv2.warpAffine(crop_bgr, m, (w, h), flags=cv2.INTER_LINEAR, borderMode=cv2.BORDER_CONSTANT)
    scaled_mask = cv2.warpAffine(
        mask, m, (w, h), flags=cv2.INTER_NEAREST, borderMode=cv2.BORDER_CONSTANT, borderValue=0
    )
    return scaled_crop, scaled_mask


def flip(crop_bgr: np.ndarray, mask: np.ndarray, horizontal: bool, vertical: bool) -> Pair:
    """A seed photographed from directly above has no canonical up/down or
    left/right — reflection is a realistic, identity-preserving
    augmentation here, not a distortion (unlike, say, flipping a photo of
    text)."""
    if not horizontal and not vertical:
        return crop_bgr, mask
    code = -1 if (horizontal and vertical) else (1 if horizontal else 0)
    return cv2.flip(crop_bgr, code), cv2.flip(mask, code)


def brightness_contrast(crop_bgr: np.ndarray, mask: np.ndarray, brightness: float, contrast: float) -> Pair:
    """`brightness` shifts pixel values additively (roughly -40..40);
    `contrast` scales them around 0 (roughly 0.8..1.2). Mask is untouched —
    this transform only changes color, never the shape."""
    adjusted = cv2.convertScaleAbs(crop_bgr, alpha=contrast, beta=brightness)
    return adjusted, mask


def blur(crop_bgr: np.ndarray, mask: np.ndarray, sigma: float) -> Pair:
    """Small Gaussian blur — simulates a slightly-off-focus capture.
    Kernel size is derived from sigma so it stays proportionate."""
    k = max(3, int(sigma * 3) | 1)  # odd kernel size, floor of 3
    return cv2.GaussianBlur(crop_bgr, (k, k), sigmaX=sigma), mask


def noise(crop_bgr: np.ndarray, mask: np.ndarray, sigma: float, rng: np.random.Generator) -> Pair:
    """Additive Gaussian sensor noise, small sigma (roughly 3..10 on a
    0..255 scale) — never enough to obscure the seed's own texture."""
    noisy = crop_bgr.astype(np.float32) + rng.normal(0, sigma, crop_bgr.shape).astype(np.float32)
    return np.clip(noisy, 0, 255).astype(np.uint8), mask


def random_augment(crop_bgr: np.ndarray, mask: np.ndarray, rng: np.random.Generator) -> Pair:
    """One randomly-composed augmented variant: always a small
    rotation+scale+flip (geometry-preserving, "this could have been
    photographed at a slightly different angle/distance/orientation"),
    plus brightness/contrast always (lighting varies shoot to shoot), plus
    blur and/or noise each some of the time (not every photo is
    soft-focus or noisy). Every parameter is drawn fresh per call — the
    caller controls reproducibility by seeding `rng` once, upstream.
    """
    result = rotate(crop_bgr, mask, degrees=float(rng.uniform(-15, 15)))
    result = scale(*result, factor=float(rng.uniform(0.9, 1.1)))
    result = flip(*result, horizontal=bool(rng.random() < 0.5), vertical=bool(rng.random() < 0.5))
    result = brightness_contrast(
        *result,
        brightness=float(rng.uniform(-20, 20)),
        contrast=float(rng.uniform(0.85, 1.15)),
    )
    if rng.random() < 0.35:
        result = blur(*result, sigma=float(rng.uniform(0.6, 1.4)))
    if rng.random() < 0.35:
        result = noise(*result, sigma=float(rng.uniform(3, 9)), rng=rng)
    return result

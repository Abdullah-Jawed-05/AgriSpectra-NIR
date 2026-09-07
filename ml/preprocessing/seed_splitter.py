"""Touching-seed splitter — the Python mirror of
app/lib/ml/seed_splitter.dart (§11).

Marker Voronoi partition, NOT cv2.watershed: chamfer (3,4) distance
transform -> relative regional maxima -> multi-source BFS assignment. This
is chosen precisely because it is trivial to keep bit-identical across the
two languages; cv2.watershed's tie-breaking is not. Every constant, loop
order, and neighbour ordering here matches the Dart file — change them
together or `parity_check` will (correctly) complain.
"""
from __future__ import annotations

from collections import deque

import numpy as np

_MIN_PEAK_DISTANCE_FRACTION = 0.45
_PEAK_PLATEAU_RADIUS = 3
_MIN_MARKER_SEPARATION = 16.0
_MIN_PART_FRACTION = 0.15

# Split-trigger gate, mirrors ClassicalCVSeedFinder._splitAreaMultiple and
# the 25th-percentile reference in seed_finder.dart.
SPLIT_AREA_MULTIPLE = 1.6


def split_component(mask: np.ndarray) -> list[np.ndarray]:
    """`mask` is a 2-D uint8 array (0 / non-zero). Returns a list of
    boolean arrays the same shape, one per detected seed — or a list with
    fewer than 2 entries meaning "leave it as one seed".
    """
    h, w = mask.shape
    raw = mask != 0
    if not raw.any():
        return []

    clean = _clean_mask(raw)
    if not clean.any():
        return []

    dist = _chamfer_distance(clean)
    markers = _find_markers(clean, dist)
    if len(markers) < 2:
        return []

    labels = _voronoi_partition(clean, markers)

    raw_flat = raw.reshape(-1)
    lab_flat = labels.reshape(-1)
    raw_total = int(raw_flat.sum())
    parts: dict[int, list[int]] = {}
    for i in np.nonzero(raw_flat)[0]:
        lb = int(lab_flat[i])
        if lb > 0:
            parts.setdefault(lb, []).append(int(i))
    if len(parts) < 2:
        return []

    ordered = [parts[k] for k in sorted(parts)]
    merged = _absorb_slivers(ordered, raw_total)
    if len(merged) < 2:
        return []

    out = []
    for idxs in merged:
        m = np.zeros(h * w, dtype=bool)
        m[np.asarray(idxs, dtype=np.int64)] = True
        out.append(m.reshape(h, w))
    return out


def _clean_mask(fg: np.ndarray) -> np.ndarray:
    """Fill border-disconnected background pockets, then a 1px close."""
    h, w = fg.shape
    out = fg.copy()

    reached = np.zeros_like(out)
    q = deque()
    for x in range(w):
        for y in (0, h - 1):
            if not out[y, x] and not reached[y, x]:
                reached[y, x] = True
                q.append((y, x))
    for y in range(h):
        for x in (0, w - 1):
            if not out[y, x] and not reached[y, x]:
                reached[y, x] = True
                q.append((y, x))
    while q:
        y, x = q.popleft()
        for dy, dx in ((-1, 0), (1, 0), (0, -1), (0, 1)):
            ny, nx = y + dy, x + dx
            if 0 <= ny < h and 0 <= nx < w and not out[ny, nx] and not reached[ny, nx]:
                reached[ny, nx] = True
                q.append((ny, nx))
    out |= ~reached & ~fg  # background not reached from the border -> hole

    return _erode(_dilate(out))


def _dilate(m: np.ndarray) -> np.ndarray:
    o = m.copy()
    o[:-1, :] |= m[1:, :]
    o[1:, :] |= m[:-1, :]
    o[:, :-1] |= m[:, 1:]
    o[:, 1:] |= m[:, :-1]
    return o


def _erode(m: np.ndarray) -> np.ndarray:
    # Border pixels treat a missing neighbour as "inside" (matches the
    # `x > 0 ? ... : true` guards in seed_splitter.dart::_erode).
    inside = m.copy()
    inside[:-1, :] &= m[1:, :]
    inside[1:, :] &= m[:-1, :]
    inside[:, :-1] &= m[:, 1:]
    inside[:, 1:] &= m[:, :-1]
    return inside


def _chamfer_distance(fg: np.ndarray) -> np.ndarray:
    h, w = fg.shape
    big = 1 << 28
    d = np.where(fg, big, 0).astype(np.int64)

    for y in range(h):
        for x in range(w):
            if d[y, x] == 0:
                continue
            v = d[y, x]
            if x > 0:
                v = min(v, d[y, x - 1] + 3)
            if y > 0:
                v = min(v, d[y - 1, x] + 3)
            if x > 0 and y > 0:
                v = min(v, d[y - 1, x - 1] + 4)
            if x < w - 1 and y > 0:
                v = min(v, d[y - 1, x + 1] + 4)
            d[y, x] = v
    for y in range(h - 1, -1, -1):
        for x in range(w - 1, -1, -1):
            if d[y, x] == 0:
                continue
            v = d[y, x]
            if x < w - 1:
                v = min(v, d[y, x + 1] + 3)
            if y < h - 1:
                v = min(v, d[y + 1, x] + 3)
            if x < w - 1 and y < h - 1:
                v = min(v, d[y + 1, x + 1] + 4)
            if x > 0 and y < h - 1:
                v = min(v, d[y + 1, x - 1] + 4)
            d[y, x] = v
    return d


def _find_markers(fg: np.ndarray, dist: np.ndarray) -> list[list[int]]:
    h, w = fg.shape
    r = _PEAK_PLATEAU_RADIUS
    max_dist = int(dist.max())
    min_peak = max(6, round(max_dist * _MIN_PEAK_DISTANCE_FRACTION))

    is_max = np.zeros((h, w), dtype=bool)
    for y in range(h):
        for x in range(w):
            if not fg[y, x] or dist[y, x] < min_peak:
                continue
            v = dist[y, x]
            y0, y1 = max(0, y - r), min(h, y + r + 1)
            x0, x1 = max(0, x - r), min(w, x + r + 1)
            if dist[y0:y1, x0:x1].max() <= v:
                is_max[y, x] = True

    seen = np.zeros((h, w), dtype=bool)
    candidates: list[list[int]] = []
    for sy in range(h):
        for sx in range(w):
            if not is_max[sy, sx] or seen[sy, sx]:
                continue
            group: list[int] = []
            q = deque([(sy, sx)])
            seen[sy, sx] = True
            while q:
                y, x = q.popleft()
                group.append(y * w + x)
                for dy in (-1, 0, 1):
                    for dx in (-1, 0, 1):
                        if dy == 0 and dx == 0:
                            continue
                        ny, nx = y + dy, x + dx
                        if 0 <= ny < h and 0 <= nx < w and is_max[ny, nx] and not seen[ny, nx]:
                            seen[ny, nx] = True
                            q.append((ny, nx))
            candidates.append(group)

    def peak(g: list[int]) -> int:
        return max(int(dist[i // w, i % w]) for i in g)

    candidates.sort(key=lambda g: (-peak(g), -len(g), g[0]))

    kept: list[list[int]] = []
    kept_centres: list[tuple[float, float]] = []
    for g in candidates:
        cx = sum(i % w for i in g) / len(g)
        cy = sum(i // w for i in g) / len(g)
        too_close = any(
            (c[0] - cx) ** 2 + (c[1] - cy) ** 2 < _MIN_MARKER_SEPARATION ** 2
            for c in kept_centres
        )
        if not too_close:
            kept.append(g)
            kept_centres.append((cx, cy))
    return kept


def _voronoi_partition(fg: np.ndarray, markers: list[list[int]]) -> np.ndarray:
    h, w = fg.shape
    labels = np.zeros(h * w, dtype=np.int64)
    fg_flat = fg.reshape(-1)
    q = deque()
    for m, group in enumerate(markers):
        for i in group:
            labels[i] = m + 1
            q.append(i)
    steps = ((0, -1), (1, 0), (0, 1), (-1, 0), (1, -1), (-1, -1), (1, 1), (-1, 1))
    while q:
        i = q.popleft()
        x, y = i % w, i // w
        lb = labels[i]
        for dx, dy in steps:
            nx, ny = x + dx, y + dy
            if 0 <= nx < w and 0 <= ny < h:
                ni = ny * w + nx
                if fg_flat[ni] and labels[ni] == 0:
                    labels[ni] = lb
                    q.append(ni)
    return labels.reshape(h, w)


def _absorb_slivers(parts: list[list[int]], total: int) -> list[list[int]]:
    min_size = int(total * _MIN_PART_FRACTION)
    big = [p for p in parts if len(p) >= min_size]
    slivers = [p for p in parts if len(p) < min_size]
    if len(big) < 2:
        return []
    if not slivers:
        return big
    for s in slivers:
        big[0].extend(s)
    big.sort(key=len, reverse=True)
    return big

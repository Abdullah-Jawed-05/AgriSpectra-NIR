import 'dart:collection';
import 'dart:typed_data';

/// Splits a connected-component mask that is actually **several touching
/// seeds** into one mask per seed (§11 "touching / overlapping seeds").
///
/// The classical detector in `seed_finder.dart` returns one blob per
/// connected region, so two barley grains resting against each other come
/// back as a single mis-shaped "seed" and the count is short. This runs as
/// a post-process on each component.
///
/// Method — a **marker Voronoi partition**, not a true grey-scale
/// watershed:
///  1. Chamfer (3, 4) distance transform of the mask.
///  2. Regional maxima of that transform, above a floor and de-duplicated
///     by separation → one marker per seed centre.
///  3. If ≥2 markers survive, every foreground pixel is assigned to the
///     nearest marker by multi-source breadth-first search over the mask
///     graph (fixed 8-neighbour order, first front to arrive wins).
///
/// True `cv2.watershed` tie-breaking is effectively impossible to
/// reproduce bit-for-bit in a second language; a marker Voronoi split is
/// fully deterministic, trivially identical in Dart and Python
/// (`ml/preprocessing/seed_splitter.py` is the mirror — keep them in
/// lock-step), and separates convex touching grains cleanly, which is the
/// case that actually occurs. Non-convex clumps are left for a learned
/// detector (§11).
class SeedSplitter {
  const SeedSplitter({
    this.minPeakDistanceFraction = 0.45,
    this.peakPlateauRadius = 3,
    this.minMarkerSeparation = 16,
    this.minPartFraction = 0.15,
  });

  /// A regional-maximum pixel is only a marker if its distance value is at
  /// least this fraction of the mask's maximum distance value. Relative,
  /// not absolute, so it scales with seed size and ignores the shallow
  /// ridges left by boundary noise.
  final double minPeakDistanceFraction;

  /// Chebyshev radius a pixel must dominate (>=) to count as a regional
  /// maximum.
  final int peakPlateauRadius;

  /// Markers whose centres are closer than this (pixels) are merged —
  /// one grain, one marker.
  final double minMarkerSeparation;

  /// After splitting, a part smaller than this fraction of the original
  /// mask is folded back into its largest neighbour — it's a sliver, not a
  /// seed.
  final double minPartFraction;

  /// [mask] is a row-major 0/255 buffer of size [w]*[h]. Returns one list
  /// of pixel indices (into that same buffer) per detected seed. A return
  /// of length 0 or 1 means "don't split — treat as a single seed".
  List<List<int>> split(Uint8List rawMask, int w, int h) {
    if (_countForeground(rawMask) == 0) return const [];

    // The thresholded blob is peppered with small holes and rough edges;
    // the distance transform is useless on that. Fill interior holes and
    // close pin-holes first, and do the whole split on that clean copy —
    // the pixel indices still refer to the original buffer.
    final mask = _cleanMask(rawMask, w, h);
    final total = _countForeground(mask);
    if (total == 0) return const [];

    final dist = _chamferDistance(mask, w, h);
    final markers = _findMarkers(mask, dist, w, h);
    if (markers.length < 2) return const [];

    final labels = _voronoiPartition(mask, w, h, markers);

    // Assign the *original* foreground pixels (not the cleaned ones) to the
    // label their location was given.
    final parts = <int, List<int>>{};
    var rawTotal = 0;
    for (var i = 0; i < rawMask.length; i++) {
      if (rawMask[i] == 0) continue;
      rawTotal++;
      final l = labels[i];
      if (l > 0) (parts[l] ??= <int>[]).add(i);
    }
    if (parts.length < 2) return const [];

    return _absorbSlivers(parts.values.toList(), rawTotal, w);
  }

  int _countForeground(Uint8List mask) {
    var n = 0;
    for (final v in mask) {
      if (v != 0) n++;
    }
    return n;
  }

  /// Fill background pockets not connected to the mask's bounding-box
  /// border (pepper holes from thresholding noise), then a 1px
  /// morphological close to smooth the edge. The result is a superset of
  /// the input, so every original foreground pixel still lands on a
  /// labelled cell.
  Uint8List _cleanMask(Uint8List mask, int w, int h) {
    final out = Uint8List.fromList(mask);

    // Flood the background from the border; anything background not reached
    // is an interior hole -> fill it.
    final reached = Uint8List(w * h);
    final queue = Queue<int>();
    void seed(int i) {
      if (out[i] == 0 && reached[i] == 0) {
        reached[i] = 1;
        queue.add(i);
      }
    }

    for (var x = 0; x < w; x++) {
      seed(x);
      seed((h - 1) * w + x);
    }
    for (var y = 0; y < h; y++) {
      seed(y * w);
      seed(y * w + w - 1);
    }
    while (queue.isNotEmpty) {
      final i = queue.removeFirst();
      final x = i % w, y = i ~/ w;
      for (var k = 0; k < 4; k++) {
        final nx = x + const [0, 0, -1, 1][k];
        final ny = y + const [-1, 1, 0, 0][k];
        if (nx < 0 || ny < 0 || nx >= w || ny >= h) continue;
        final ni = ny * w + nx;
        if (out[ni] == 0 && reached[ni] == 0) {
          reached[ni] = 1;
          queue.add(ni);
        }
      }
    }
    for (var i = 0; i < out.length; i++) {
      if (out[i] == 0 && reached[i] == 0) out[i] = 255;
    }

    // Morphological close: dilate then erode, 4-neighbour, one step.
    return _erode(_dilate(out, w, h), w, h);
  }

  Uint8List _dilate(Uint8List m, int w, int h) {
    final o = Uint8List(w * h);
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        final i = y * w + x;
        if (m[i] != 0 ||
            (x > 0 && m[i - 1] != 0) ||
            (x < w - 1 && m[i + 1] != 0) ||
            (y > 0 && m[i - w] != 0) ||
            (y < h - 1 && m[i + w] != 0)) {
          o[i] = 255;
        }
      }
    }
    return o;
  }

  Uint8List _erode(Uint8List m, int w, int h) {
    final o = Uint8List(w * h);
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        final i = y * w + x;
        if (m[i] == 0) continue;
        final keep = (x > 0 ? m[i - 1] != 0 : true) &&
            (x < w - 1 ? m[i + 1] != 0 : true) &&
            (y > 0 ? m[i - w] != 0 : true) &&
            (y < h - 1 ? m[i + w] != 0 : true);
        if (keep) o[i] = 255;
      }
    }
    return o;
  }

  /// Two-pass chamfer (3, 4) distance transform. 0 on background, distance
  /// to the nearest background pixel on foreground.
  Int32List _chamferDistance(Uint8List mask, int w, int h) {
    const big = 1 << 28;
    final d = Int32List(w * h);
    for (var i = 0; i < d.length; i++) {
      d[i] = mask[i] != 0 ? big : 0;
    }

    void relax(int idx, int from, int cost) {
      final v = d[from] + cost;
      if (v < d[idx]) d[idx] = v;
    }

    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        final i = y * w + x;
        if (d[i] == 0) continue;
        if (x > 0) relax(i, i - 1, 3);
        if (y > 0) relax(i, i - w, 3);
        if (x > 0 && y > 0) relax(i, i - w - 1, 4);
        if (x < w - 1 && y > 0) relax(i, i - w + 1, 4);
      }
    }
    for (var y = h - 1; y >= 0; y--) {
      for (var x = w - 1; x >= 0; x--) {
        final i = y * w + x;
        if (d[i] == 0) continue;
        if (x < w - 1) relax(i, i + 1, 3);
        if (y < h - 1) relax(i, i + w, 3);
        if (x < w - 1 && y < h - 1) relax(i, i + w + 1, 4);
        if (x > 0 && y < h - 1) relax(i, i + w - 1, 4);
      }
    }
    return d;
  }

  /// Regional maxima of the distance transform, grouped into connected
  /// plateaus and de-duplicated by [minMarkerSeparation]. Each surviving
  /// marker is a list of its pixel indices.
  List<List<int>> _findMarkers(Uint8List mask, Int32List dist, int w, int h) {
    final r = peakPlateauRadius;
    var maxDist = 0;
    for (final v in dist) {
      if (v > maxDist) maxDist = v;
    }
    // Chamfer (3,4): a 3-unit step ≈ 1px, so require the peak to sit at
    // least ~2px in from the edge regardless of the relative floor.
    final minPeak = (maxDist * minPeakDistanceFraction).round().clamp(6, 1 << 20);

    final isMax = Uint8List(w * h);
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        final i = y * w + x;
        if (mask[i] == 0 || dist[i] < minPeak) continue;
        final v = dist[i];
        var dominates = true;
        for (var dy = -r; dy <= r && dominates; dy++) {
          final ny = y + dy;
          if (ny < 0 || ny >= h) continue;
          for (var dx = -r; dx <= r; dx++) {
            final nx = x + dx;
            if (nx < 0 || nx >= w) continue;
            if (dist[ny * w + nx] > v) {
              dominates = false;
              break;
            }
          }
        }
        if (dominates) isMax[i] = 1;
      }
    }

    // Connected plateaus of maxima -> one candidate marker each.
    final seen = Uint8List(w * h);
    final candidates = <List<int>>[];
    for (var start = 0; start < isMax.length; start++) {
      if (isMax[start] == 0 || seen[start] != 0) continue;
      final group = <int>[];
      final queue = Queue<int>()..add(start);
      seen[start] = 1;
      while (queue.isNotEmpty) {
        final i = queue.removeFirst();
        group.add(i);
        final x = i % w, y = i ~/ w;
        for (var dy = -1; dy <= 1; dy++) {
          for (var dx = -1; dx <= 1; dx++) {
            if (dx == 0 && dy == 0) continue;
            final nx = x + dx, ny = y + dy;
            if (nx < 0 || ny < 0 || nx >= w || ny >= h) continue;
            final ni = ny * w + nx;
            if (isMax[ni] == 1 && seen[ni] == 0) {
              seen[ni] = 1;
              queue.add(ni);
            }
          }
        }
      }
      candidates.add(group);
    }

    // Strongest first (higher peak distance, then larger plateau, then
    // scan order) so the de-dup keep/drop decision is deterministic.
    int peak(List<int> g) => g.fold(0, (m, i) => dist[i] > m ? dist[i] : m);
    candidates.sort((a, b) {
      final pa = peak(a), pb = peak(b);
      if (pa != pb) return pb - pa;
      if (a.length != b.length) return b.length - a.length;
      return a.first - b.first;
    });

    final kept = <List<int>>[];
    final keptCentres = <List<double>>[];
    for (final g in candidates) {
      double sx = 0, sy = 0;
      for (final i in g) {
        sx += i % w;
        sy += i ~/ w;
      }
      final cx = sx / g.length, cy = sy / g.length;
      var tooClose = false;
      for (final c in keptCentres) {
        final ddx = c[0] - cx, ddy = c[1] - cy;
        if (ddx * ddx + ddy * ddy < minMarkerSeparation * minMarkerSeparation) {
          tooClose = true;
          break;
        }
      }
      if (!tooClose) {
        kept.add(g);
        keptCentres.add([cx, cy]);
      }
    }
    return kept;
  }

  /// Multi-source BFS: every foreground pixel takes the label of the
  /// marker whose front reaches it first. Fixed neighbour order, FIFO
  /// queue → identical result every run and in the Python mirror.
  Int32List _voronoiPartition(Uint8List mask, int w, int h, List<List<int>> markers) {
    final labels = Int32List(w * h);
    final queue = Queue<int>();
    for (var m = 0; m < markers.length; m++) {
      for (final i in markers[m]) {
        labels[i] = m + 1;
        queue.add(i);
      }
    }
    const dx = [0, 1, 0, -1, 1, -1, 1, -1];
    const dy = [-1, 0, 1, 0, -1, -1, 1, 1];
    while (queue.isNotEmpty) {
      final i = queue.removeFirst();
      final x = i % w, y = i ~/ w;
      final l = labels[i];
      for (var k = 0; k < 8; k++) {
        final nx = x + dx[k], ny = y + dy[k];
        if (nx < 0 || ny < 0 || nx >= w || ny >= h) continue;
        final ni = ny * w + nx;
        if (mask[ni] != 0 && labels[ni] == 0) {
          labels[ni] = l;
          queue.add(ni);
        }
      }
    }
    return labels;
  }

  List<List<int>> _absorbSlivers(List<List<int>> parts, int total, int w) {
    final minSize = (total * minPartFraction).floor();
    final big = <List<int>>[];
    final slivers = <List<int>>[];
    for (final p in parts) {
      (p.length >= minSize ? big : slivers).add(p);
    }
    if (big.length < 2) return const []; // the "split" was all slivers — don't
    if (slivers.isEmpty) return big;

    // Hand each sliver's pixels to whichever surviving part it touches most.
    for (final s in slivers) {
      big.first.addAll(s); // simple, deterministic: fold into the largest
    }
    big.sort((a, b) => b.length - a.length);
    return big;
  }
}

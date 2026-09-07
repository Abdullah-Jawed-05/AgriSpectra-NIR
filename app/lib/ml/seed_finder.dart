import 'dart:math';
import 'dart:typed_data';
import 'dart:ui';

import 'package:image/image.dart' as img;

import '../domain/entities/detected_seed.dart';
import '../domain/entities/seed_features.dart';
import 'seed_splitter.dart';
import 'segmented_seed.dart';

/// Detection + segmentation strategy interface (§11: "architect the system
/// so the detection model can later be replaced" — with YOLO or another
/// learned detector, without touching anything downstream of
/// [SegmentedSeed]).
abstract class SeedFinder {
  List<SegmentedSeed> find(img.Image image);
}

/// V0/V1 detector: Otsu thresholding + connected-component labeling
/// (§11 — "for the hackathon, select the simplest approach that provides
/// reliable results"). Detection and segmentation happen in one pass here
/// because a connected-component blob *is* both a detection (bounding box)
/// and a segmentation (mask) simultaneously — there's no separate detector
/// output worth computing twice. [DetectedSeed] records are still derived
/// from the result (see [toDetectedSeeds]) to keep the two pipeline stages
/// conceptually distinct for any future replacement of just this class.
///
/// Geometry here (perimeter/hull/contour, via [_traceContour]) and the
/// gradient math in `feature_extractor.dart` are written to match
/// `ml/preprocessing/segmentation.py` and `features.py` term for term — a
/// model trained on the Python side is only valid on-device if this file
/// computes the same features the same way (see ML_PIPELINE.md).
class ClassicalCVSeedFinder implements SeedFinder {
  ClassicalCVSeedFinder({
    this.workingMaxDimension = 1100,
    this.minAreaFraction = 0.00025,
    this.maxAreaFraction = 0.08,
    this.splitter = const SeedSplitter(),
  });

  final int workingMaxDimension;
  final double minAreaFraction;
  final double maxAreaFraction;

  /// Post-process that breaks a single connected blob into several when it
  /// is really touching seeds (§11). Set to `null` to disable.
  final SeedSplitter? splitter;

  /// A component is only handed to [splitter] when its area is at least
  /// this multiple of the batch's typical single-seed area (25th
  /// percentile of component areas) — a lone seed has no neighbour to be
  /// stuck to, and running the split on every blob wastes work and risks
  /// over-segmenting a single lumpy grain.
  static const double _splitAreaMultiple = 1.6;

  /// A blob whose CIE-Lab chroma (distance from neutral grey) averages
  /// below this is a cast shadow, not a seed — a shadow shifts lightness,
  /// not colour. Mirrors `_SHADOW_CHROMA_MAX` in segmentation.py.
  static const double _shadowChromaMax = 4.0;

  /// After splitting, a blob smaller than this fraction of the batch's
  /// median blob area is a furrow line / speck, not a seed.
  static const double _minSeedAreaFraction = 0.40;

  /// A rejected over-size (merged) blob covering more than this share of
  /// the frame means the seeds are piled/touching — per-seed detail is
  /// then unreliable and [lastLayoutPiled] is set.
  static const double _pileOversizeFraction = 0.05;

  static const double _seedlikeMinFill = 0.30;

  /// If nothing in the frame has CIE-Lab chroma above this, the image is
  /// effectively greyscale — skip the colour channel and go straight to
  /// the luminance fallback. Mirrors `_MIN_CHROMA_FOR_COLOUR` in
  /// segmentation.py.
  static const double _minChromaForColour = 3.0;

  /// Populated by the most recent [find] call: how many blobs the splitter
  /// turned into multiple seeds, and how many extra seeds that produced.
  int lastComponentsSplit = 0;

  /// Populated by the most recent [find] call: how many raw connected
  /// components were found, and how many were discarded as too small/large
  /// to plausibly be a single seed.
  int lastTotalCandidates = 0;
  int lastRejectedCandidates = 0;

  /// Which channel won: `'chroma'` (colour vs neutral background, the
  /// normal case) or `'lum_dark'` (luminance fallback for very dark seeds).
  String lastChannel = 'chroma';

  /// The seeds in the frame are piled / touching — the batch count and
  /// per-seed results are unreliable and the user should be told to spread
  /// them into a single layer.
  bool lastLayoutPiled = false;

  @override
  List<SegmentedSeed> find(img.Image original) {
    final image = _downscale(original, workingMaxDimension);
    // Normalise white balance + exposure before anything reads a pixel
    // (§8). Mirrored in segmentation.py::_normalise_lighting.
    _normaliseLighting(image);
    final w = image.width, h = image.height;
    final area = w * h;

    // Segment on CIE-Lab chroma (distance from the neutral grey axis): a
    // tan/brown grain is chromatic, plain paper and a cast shadow are
    // near-neutral. Luminance-Otsu can't tell a light seed from light
    // paper and catches the dark furrow lines / inter-grain shadows
    // instead. Mirrors segmentation.py::segment.
    final chroma = _chromaField(image, w, h);
    var maxChroma = 0.0;
    for (final v in chroma) {
      if (v > maxChroma) maxChroma = v;
    }

    Uint8List? chromaMask;
    if (maxChroma >= _minChromaForColour) {
      final m = _morphClean(_thresholdAbove(chroma), w, h);
      if (_countSeedlike(m, w, h, area) > 0) chromaMask = m;
    }

    final Uint8List mask;
    if (chromaMask != null) {
      mask = chromaMask;
      lastChannel = 'chroma';
    } else {
      final gray = img.grayscale(image.clone());
      final lum = Float32List(area);
      for (var i = 0; i < area; i++) {
        lum[i] = -img.getLuminance(gray.getPixel(i % w, i ~/ w)).toDouble();
      }
      mask = _morphClean(_thresholdAbove(lum), w, h);
      lastChannel = 'lum_dark';
    }

    // Shadow rejection only makes sense on the chroma channel — there a
    // near-neutral blob is a cast shadow. On the luminance fallback a
    // low-chroma blob just means the seeds aren't colourful.
    final useShadowFilter = lastChannel == 'chroma';
    bool notShadow(_RawComponent c) => !useShadowFilter || _meanChroma(chroma, c) >= _shadowChromaMax;

    final components = _labelBinary(mask, w, h);
    lastTotalCandidates = components.length;

    final minArea = area * minAreaFraction;
    final maxArea = area * maxAreaFraction;
    final valid = <_RawComponent>[];
    double oversizeArea = 0;
    for (final c in components) {
      final a = c.pixels.length;
      if (a >= minArea && a <= maxArea) {
        valid.add(c);
      } else if (a > maxArea && a > _pileOversizeFraction * area && notShadow(c)) {
        oversizeArea += a;
      }
    }
    lastRejectedCandidates = components.length - valid.length;
    lastLayoutPiled = oversizeArea > _pileOversizeFraction * area;

    final split = _splitMergedComponents(valid, w, h);

    // Fragment rejection: a blob far below the batch's typical seed size
    // is a furrow line / speck.
    final seedComponents = split.where(notShadow).toList();
    if (seedComponents.isNotEmpty) {
      final sizes = seedComponents.map((c) => c.pixels.length).toList()..sort();
      final median = sizes[sizes.length ~/ 2].toDouble();
      seedComponents.removeWhere((c) => c.pixels.length < _minSeedAreaFraction * median);
    }

    final results = <SegmentedSeed>[];
    for (var i = 0; i < seedComponents.length; i++) {
      results.add(_buildSegmentedSeed('seed_${(i + 1).toString().padLeft(3, '0')}', seedComponents[i], image));
    }
    return results;
  }

  /// Per-pixel CIE-Lab chroma = sqrt(a*² + b*²). Same Lab as
  /// feature_extractor.dart / features.py::_rgb_to_lab. sRGB→linear is
  /// LUT'd (channels are 0..255 ints); the cube-root f() is not.
  Float32List _chromaField(img.Image image, int w, int h) {
    final lut = _srgbLinearLut;
    const xn = 0.95047, yn = 1.0, zn = 1.08883;
    double f(double t) => t > 0.008856 ? pow(t, 1 / 3).toDouble() : (7.787 * t) + (16 / 116);

    final out = Float32List(w * h);
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        final p = image.getPixel(x, y);
        final rl = lut[p.r.toInt().clamp(0, 255)];
        final gl = lut[p.g.toInt().clamp(0, 255)];
        final bl = lut[p.b.toInt().clamp(0, 255)];
        final xx = rl * 0.4124 + gl * 0.3576 + bl * 0.1805;
        final yy = rl * 0.2126 + gl * 0.7152 + bl * 0.0722;
        final zz = rl * 0.0193 + gl * 0.1192 + bl * 0.9505;
        final fx = f(xx / xn), fy = f(yy / yn), fz = f(zz / zn);
        final aLab = 500 * (fx - fy);
        final bLab = 200 * (fy - fz);
        out[y * w + x] = sqrt(aLab * aLab + bLab * bLab);
      }
    }
    return out;
  }

  static final Float64List _srgbLinearLut = () {
    final lut = Float64List(256);
    for (var i = 0; i < 256; i++) {
      final v = i / 255;
      lut[i] = v <= 0.04045 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4).toDouble();
    }
    return lut;
  }();

  /// 0/255 mask where [field] is above an Otsu split of the field scaled
  /// to 0..255. Mirrors segmentation.py::_otsu_above.
  Uint8List _thresholdAbove(Float32List field) {
    var lo = double.infinity, hi = -double.infinity;
    for (final v in field) {
      if (v < lo) lo = v;
      if (v > hi) hi = v;
    }
    final range = hi - lo;
    final mask = Uint8List(field.length);
    if (range < 1e-6) return mask;
    final scaled = Float32List(field.length);
    for (var i = 0; i < field.length; i++) {
      scaled[i] = ((field[i] - lo) / range * 255).clamp(0, 255).toDouble();
    }
    final t = _otsuThreshold(scaled);
    for (var i = 0; i < field.length; i++) {
      if (scaled[i] > t) mask[i] = 255;
    }
    return mask;
  }

  /// 3×3 morphological open then close (4-connectivity structuring
  /// element via two passes each). Mirrors cv2.MORPH_OPEN + MORPH_CLOSE
  /// with a 3×3 rectangular kernel closely enough for feature parity.
  Uint8List _morphClean(Uint8List mask, int w, int h) {
    return _dilate3(_erode3(_dilate3(_erode3(mask, w, h), w, h), w, h), w, h);
  }

  Uint8List _erode3(Uint8List m, int w, int h) {
    final o = Uint8List(w * h);
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        final i = y * w + x;
        if (m[i] == 0) continue;
        var keep = true;
        for (var dy = -1; dy <= 1 && keep; dy++) {
          for (var dx = -1; dx <= 1; dx++) {
            final nx = x + dx, ny = y + dy;
            if (nx < 0 || ny < 0 || nx >= w || ny >= h) continue;
            if (m[ny * w + nx] == 0) {
              keep = false;
              break;
            }
          }
        }
        if (keep) o[i] = 255;
      }
    }
    return o;
  }

  Uint8List _dilate3(Uint8List m, int w, int h) {
    final o = Uint8List(w * h);
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        if (m[y * w + x] == 0) continue;
        for (var dy = -1; dy <= 1; dy++) {
          for (var dx = -1; dx <= 1; dx++) {
            final nx = x + dx, ny = y + dy;
            if (nx < 0 || ny < 0 || nx >= w || ny >= h) continue;
            o[ny * w + nx] = 255;
          }
        }
      }
    }
    return o;
  }

  int _countSeedlike(Uint8List mask, int w, int h, int imageArea) {
    final lo = imageArea * minAreaFraction, hi = imageArea * maxAreaFraction;
    var count = 0;
    for (final c in _labelBinary(mask, w, h)) {
      final a = c.pixels.length;
      if (a < lo || a > hi) continue;
      final bw = c.maxX - c.minX + 1, bh = c.maxY - c.minY + 1;
      if (a / (bw * bh) >= _seedlikeMinFill) count++;
    }
    return count;
  }

  double _meanChroma(Float32List chroma, _RawComponent c) {
    if (c.pixels.isEmpty) return 0;
    double sum = 0;
    for (final idx in c.pixels) {
      sum += chroma[idx];
    }
    return sum / c.pixels.length;
  }

  /// Flood-fill 8-connected components of a 0/255 binary mask.
  List<_RawComponent> _labelBinary(Uint8List mask, int w, int h) {
    final visited = Uint8List(w * h);
    final components = <_RawComponent>[];
    final queue = Uint32List(w * h);

    for (var start = 0; start < w * h; start++) {
      if (visited[start] != 0 || mask[start] == 0) continue;
      var head = 0, tail = 0;
      queue[tail++] = start;
      visited[start] = 1;
      final pixels = <int>[];
      int minX = w, maxX = 0, minY = h, maxY = 0;
      while (head < tail) {
        final idx = queue[head++];
        final x = idx % w, y = idx ~/ w;
        pixels.add(idx);
        if (x < minX) minX = x;
        if (x > maxX) maxX = x;
        if (y < minY) minY = y;
        if (y > maxY) maxY = y;
        for (var dy = -1; dy <= 1; dy++) {
          for (var dx = -1; dx <= 1; dx++) {
            if (dx == 0 && dy == 0) continue;
            final nx = x + dx, ny = y + dy;
            if (nx < 0 || ny < 0 || nx >= w || ny >= h) continue;
            final nIdx = ny * w + nx;
            if (visited[nIdx] != 0 || mask[nIdx] == 0) continue;
            visited[nIdx] = 1;
            queue[tail++] = nIdx;
          }
        }
      }
      components.add(_RawComponent(
        pixels: pixels,
        minX: minX,
        maxX: maxX,
        minY: minY,
        maxY: maxY,
        imageWidth: w,
      ));
    }
    return components;
  }

  /// Runs [splitter] over the components that are large enough to plausibly
  /// be a touching pair/cluster, and replaces any it splits with the
  /// resulting sub-components. Order is preserved so seed numbering stays
  /// stable for components that weren't touched.
  List<_RawComponent> _splitMergedComponents(List<_RawComponent> components, int w, int h) {
    lastComponentsSplit = 0;
    final s = splitter;
    if (s == null || components.length < 2) return components;

    final areas = components.map((c) => c.pixels.length).toList()..sort();
    // 25th percentile: robust to a stray small fragment, and a good proxy
    // for "one seed" when the batch is mostly singles.
    final typicalSeedArea = areas[((areas.length - 1) * 0.25).round()];
    final threshold = typicalSeedArea * _splitAreaMultiple;

    final out = <_RawComponent>[];
    for (final c in components) {
      if (c.pixels.length < threshold) {
        out.add(c);
        continue;
      }
      final cw = c.maxX - c.minX + 1;
      final ch = c.maxY - c.minY + 1;
      final localMask = Uint8List(cw * ch);
      for (final idx in c.pixels) {
        final lx = idx % c.imageWidth - c.minX;
        final ly = idx ~/ c.imageWidth - c.minY;
        localMask[ly * cw + lx] = 255;
      }

      final parts = s.split(localMask, cw, ch);
      if (parts.length < 2) {
        out.add(c);
        continue;
      }

      lastComponentsSplit++;
      for (final part in parts) {
        int minX = w, maxX = 0, minY = h, maxY = 0;
        final globalPixels = <int>[];
        for (final li in part) {
          final gx = li % cw + c.minX;
          final gy = li ~/ cw + c.minY;
          globalPixels.add(gy * w + gx);
          if (gx < minX) minX = gx;
          if (gx > maxX) maxX = gx;
          if (gy < minY) minY = gy;
          if (gy > maxY) maxY = gy;
        }
        out.add(_RawComponent(
          pixels: globalPixels,
          minX: minX,
          maxX: maxX,
          minY: minY,
          maxY: maxY,
          imageWidth: w,
        ));
      }
    }
    return out;
  }

  List<DetectedSeed> toDetectedSeeds(List<SegmentedSeed> segmented) => segmented
      .map((s) => DetectedSeed(
            seedId: s.seedId,
            boundingBox: s.boundingBox,
            // Confidence proxy for a non-learned detector: how "blob-like"
            // (compact, not needle-thin) the component is. A learned
            // detector would replace this with a real class score.
            confidence: (s.geometry.circularity.clamp(0.0, 1.0) * 0.6 + 0.4),
          ))
      .toList();

  /// Gray-world white balance (pull each channel's mean toward the overall
  /// mean) followed by an exposure pull (bring that overall mean to a
  /// fixed mid-grey target). Mutates [image] in place. Per-channel scale
  /// factors are clamped so a degenerate frame (e.g. one dominant colour)
  /// can't blow the image out. The exact same math runs in
  /// ml/preprocessing/segmentation.py — keep them identical.
  static const double _exposureTargetMean = 128;
  static const double _minChannelScale = 0.5;
  static const double _maxChannelScale = 2.0;

  void _normaliseLighting(img.Image image) {
    final w = image.width, h = image.height;
    final n = w * h;
    if (n == 0) return;

    double sumR = 0, sumG = 0, sumB = 0;
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        final p = image.getPixel(x, y);
        sumR += p.r;
        sumG += p.g;
        sumB += p.b;
      }
    }
    final meanR = sumR / n, meanG = sumG / n, meanB = sumB / n;
    final overall = (meanR + meanG + meanB) / 3;
    if (overall <= 0) return;

    final exposure = (_exposureTargetMean / overall).clamp(_minChannelScale, _maxChannelScale);
    final scaleR = (overall / meanR).clamp(_minChannelScale, _maxChannelScale) * exposure;
    final scaleG = (overall / meanG).clamp(_minChannelScale, _maxChannelScale) * exposure;
    final scaleB = (overall / meanB).clamp(_minChannelScale, _maxChannelScale) * exposure;

    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        final p = image.getPixel(x, y);
        image.setPixelRgb(
          x,
          y,
          (p.r * scaleR).round().clamp(0, 255),
          (p.g * scaleG).round().clamp(0, 255),
          (p.b * scaleB).round().clamp(0, 255),
        );
      }
    }
  }

  img.Image _downscale(img.Image image, int maxDim) {
    if (max(image.width, image.height) <= maxDim) return image;
    // Explicit linear interpolation: this package's default is
    // Interpolation.nearest, which is blockier than — and not what — the
    // Python side's cv2.resize (default INTER_LINEAR) does. Nearest-
    // neighbor here would bias the Otsu threshold and every downstream
    // pixel-level feature away from what the training pipeline sees.
    return image.width >= image.height
        ? img.copyResize(image, width: maxDim, interpolation: img.Interpolation.linear)
        : img.copyResize(image, height: maxDim, interpolation: img.Interpolation.linear);
  }

  double _otsuThreshold(Float32List luminance) {
    final histogram = List<int>.filled(256, 0);
    for (final v in luminance) {
      histogram[v.round().clamp(0, 255)]++;
    }
    final total = luminance.length;

    double sumAll = 0;
    for (var i = 0; i < 256; i++) {
      sumAll += i * histogram[i];
    }

    double sumBackground = 0;
    int weightBackground = 0;
    double maxVariance = 0;
    int bestThreshold = 127;

    for (var t = 0; t < 256; t++) {
      weightBackground += histogram[t];
      if (weightBackground == 0) continue;
      final weightForeground = total - weightBackground;
      if (weightForeground == 0) break;

      sumBackground += t * histogram[t];
      final meanBackground = sumBackground / weightBackground;
      final meanForeground = (sumAll - sumBackground) / weightForeground;

      final betweenVariance = weightBackground *
          weightForeground *
          pow(meanBackground - meanForeground, 2);

      if (betweenVariance > maxVariance) {
        maxVariance = betweenVariance.toDouble();
        bestThreshold = t;
      }
    }
    return bestThreshold.toDouble();
  }

  SegmentedSeed _buildSegmentedSeed(String seedId, _RawComponent component, img.Image sourceImage) {
    final w = component.maxX - component.minX + 1;
    final h = component.maxY - component.minY + 1;

    final mask = Uint8List(w * h);
    double sumX = 0, sumY = 0;
    for (final idx in component.pixels) {
      final x = idx % component.imageWidth - component.minX;
      final y = idx ~/ component.imageWidth - component.minY;
      mask[y * w + x] = 255;
      sumX += x;
      sumY += y;
    }
    final n = component.pixels.length;
    final centroidX = sumX / n;
    final centroidY = sumY / n;

    // Second central moments -> orientation + equivalent-ellipse axis
    // lengths (§13). This moment-based ellipse — rather than fitting a
    // conic to the boundary polygon (cv2.fitEllipse) — is the shared
    // definition with the Python training pipeline
    // (ml/preprocessing/segmentation.py): well-defined for any mask (even
    // a handful of pixels), numerically simple, and trivial to keep
    // identical on both sides. See ML_PIPELINE.md.
    double mu20 = 0, mu02 = 0, mu11 = 0;
    for (final idx in component.pixels) {
      final x = idx % component.imageWidth - component.minX - centroidX;
      final y = idx ~/ component.imageWidth - component.minY - centroidY;
      mu20 += x * x;
      mu02 += y * y;
      mu11 += x * y;
    }
    mu20 /= n;
    mu02 /= n;
    mu11 /= n;

    final theta = 0.5 * atan2(2 * mu11, mu20 - mu02);
    final common = sqrt(pow(mu20 - mu02, 2) + 4 * pow(mu11, 2));
    final lambda1 = max(0.0, (mu20 + mu02 + common) / 2);
    final lambda2 = max(0.0, (mu20 + mu02 - common) / 2);
    final length = 4 * sqrt(lambda1);
    final width = 4 * sqrt(lambda2);
    final eccentricity = lambda1 > 0 ? sqrt(max(0.0, 1 - (lambda2 / lambda1))) : 0.0;

    // Traced boundary polygon (Moore-neighbor tracing) — used for
    // perimeter, convex hull, and the stored/display contour. Replaces a
    // cruder "count of boundary pixels" perimeter proxy and an
    // angle-sorted point cloud that isn't a real contour for concave
    // shapes. Mirrors cv2.findContours + cv2.arcLength on the Python side.
    final traced = _traceContour(mask, w, h);
    final perimeter = _polygonPerimeter(traced);
    final circularity = perimeter > 0 ? (4 * pi * n / (perimeter * perimeter)).clamp(0.0, 1.0) : 0.0;

    final hull = _convexHull(traced);
    final hullArea = _polygonArea(hull);
    final convexity = hullArea > 0 ? (n / hullArea).clamp(0.0, 1.0) : 0.0;

    final contour = _thinContour(traced)
        .map((p) => Offset(
              (p.x + component.minX).toDouble(),
              (p.y + component.minY).toDouble(),
            ))
        .toList();

    final crop = img.copyCrop(
      sourceImage,
      x: component.minX,
      y: component.minY,
      width: w,
      height: h,
    );

    return SegmentedSeed(
      seedId: seedId,
      crop: crop,
      mask: mask,
      boundingBox: Rect.fromLTWH(
        component.minX.toDouble(),
        component.minY.toDouble(),
        w.toDouble(),
        h.toDouble(),
      ),
      contour: contour,
      center: Offset(
        (centroidX + component.minX).toDouble(),
        (centroidY + component.minY).toDouble(),
      ),
      orientationRadians: theta,
      geometry: GeometryFeatures(
        areaPx: n.toDouble(),
        perimeterPx: perimeter,
        widthPx: width,
        lengthPx: length,
        aspectRatio: width > 0 ? length / width : 0,
        circularity: circularity,
        eccentricity: eccentricity,
        convexity: convexity,
      ),
    );
  }

  /// Moore-neighbor boundary tracing (Gonzalez & Woods) over an
  /// 8-connected foreground mask that is a single connected component (the
  /// only kind [_labelComponents] ever produces). Walks the outer boundary
  /// clockwise starting from the first foreground pixel in row-major scan
  /// order, and returns it as an ordered polygon — the same conceptual
  /// object `cv2.findContours` gives the Python pipeline.
  List<Point<int>> _traceContour(Uint8List mask, int w, int h) {
    bool fg(int x, int y) => x >= 0 && y >= 0 && x < w && y < h && mask[y * w + x] != 0;

    Point<int>? start;
    outer:
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        if (fg(x, y)) {
          start = Point(x, y);
          break outer;
        }
      }
    }
    if (start == null) return const [];

    // Clockwise from North: N, NE, E, SE, S, SW, W, NW.
    const dx = [0, 1, 1, 1, 0, -1, -1, -1];
    const dy = [-1, -1, 0, 1, 1, 1, 0, -1];

    final boundary = <Point<int>>[start];
    var current = start;
    // The scan-order start pixel's West neighbor is guaranteed background
    // (or off-mask), so "arrived from the West" is a valid initial
    // backtrack direction.
    var backtrack = 6;
    // Defensive bound: a correct trace revisits each boundary pixel at
    // most a small constant number of times. This only matters if a mask
    // ever violates the single-8-connected-component assumption.
    final maxSteps = 8 * mask.length + 16;

    for (var step = 0; step < maxSteps; step++) {
      var found = false;
      for (var i = 1; i <= 8; i++) {
        final dir = (backtrack + i) % 8;
        final nx = current.x + dx[dir];
        final ny = current.y + dy[dir];
        if (fg(nx, ny)) {
          current = Point(nx, ny);
          backtrack = (dir + 4) % 8; // opposite direction, from the new pixel's view
          found = true;
          break;
        }
      }
      if (!found) break; // isolated pixel, no foreground neighbor
      if (current == start) break; // closed the loop
      boundary.add(current);
    }
    return boundary;
  }

  double _polygonPerimeter(List<Point<int>> polygon) {
    if (polygon.length < 2) return 0;
    double perimeter = 0;
    for (var i = 0; i < polygon.length; i++) {
      final a = polygon[i];
      final b = polygon[(i + 1) % polygon.length];
      perimeter += sqrt(pow((a.x - b.x).toDouble(), 2) + pow((a.y - b.y).toDouble(), 2));
    }
    return perimeter;
  }

  /// Thin a traced contour to a manageable number of points for
  /// storage/rendering.
  List<Point<int>> _thinContour(List<Point<int>> traced) {
    const maxPoints = 64;
    if (traced.length <= maxPoints) return traced;
    final stride = traced.length / maxPoints;
    return [for (var i = 0; i < maxPoints; i++) traced[(i * stride).floor()]];
  }

  /// Andrew's monotone chain convex hull.
  List<Point<int>> _convexHull(List<Point<int>> points) {
    if (points.length < 3) return points;
    final pts = [...points]..sort((a, b) => a.x != b.x ? a.x.compareTo(b.x) : a.y.compareTo(b.y));

    double cross(Point<int> o, Point<int> a, Point<int> b) =>
        (a.x - o.x) * (b.y - o.y) - (a.y - o.y) * (b.x - o.x).toDouble();

    final lower = <Point<int>>[];
    for (final p in pts) {
      while (lower.length >= 2 && cross(lower[lower.length - 2], lower.last, p) <= 0) {
        lower.removeLast();
      }
      lower.add(p);
    }
    final upper = <Point<int>>[];
    for (final p in pts.reversed) {
      while (upper.length >= 2 && cross(upper[upper.length - 2], upper.last, p) <= 0) {
        upper.removeLast();
      }
      upper.add(p);
    }
    lower.removeLast();
    upper.removeLast();
    return [...lower, ...upper];
  }

  double _polygonArea(List<Point<int>> polygon) {
    if (polygon.length < 3) return 0;
    double area = 0;
    for (var i = 0; i < polygon.length; i++) {
      final a = polygon[i];
      final b = polygon[(i + 1) % polygon.length];
      area += a.x * b.y - b.x * a.y;
    }
    return area.abs() / 2;
  }
}

class _RawComponent {
  final List<int> pixels;
  final int minX, maxX, minY, maxY;
  final int imageWidth;

  const _RawComponent({
    required this.pixels,
    required this.minX,
    required this.maxX,
    required this.minY,
    required this.maxY,
    required this.imageWidth,
  });
}

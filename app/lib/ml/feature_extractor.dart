import 'dart:math';
import 'dart:typed_data';

import 'package:image/image.dart' as img;

import '../domain/entities/seed_features.dart';
import 'segmented_seed.dart';

/// Computes color, texture, and damage-heuristic features (§13) over the
/// masked pixels of a [SegmentedSeed]. Geometry is already known from
/// segmentation (see [SegmentedSeed.geometry]) — this class only adds what
/// segmentation didn't already compute.
///
/// Every sub-extractor here is written to walk each seed's cropped pixels
/// a small, fixed number of times. It's tempting to write these
/// independently (grayscale conversion, texture, damage) since they're
/// conceptually separate — but on a real device, with up to 50 seeds per
/// scan, extra full pixel passes per seed are the difference between a
/// snappy result and a visibly slow "Preparing results" screen. `extract()`
/// is the one place that shares the grayscale conversion and Sobel pass
/// across everything that needs them.
///
/// The gradient math and hole detector here are written to match
/// `ml/preprocessing/features.py` term for term (Sobel gradient magnitude,
/// its edge threshold, border-flood-fill holes) — see that file's
/// docstring and `seed_finder.dart`'s class doc for why.
class FeatureExtractor {
  const FeatureExtractor();

  /// A pixel counts as an "edge" once its Sobel gradient magnitude passes
  /// this. Calibrated for the |Gx|+|Gy| scale a 3x3 Sobel kernel produces
  /// (much larger than a simple forward-difference), matching the Python
  /// pipeline's threshold exactly.
  static const double _edgeGradientThreshold = 60;

  static const List<int> _sobelX = [-1, 0, 1, -2, 0, 2, -1, 0, 1];
  static const List<int> _sobelY = [-1, -2, -1, 0, 0, 0, 1, 2, 1];

  SeedFeatures extract(SegmentedSeed seed) {
    // img.grayscale() mutates its argument in place and returns the same
    // object — without cloning first, `seed.crop` itself would desaturate
    // here, and every color feature computed below (_colorFeatures reads
    // seed.crop.getPixel for r/g/b) would see grayscale data instead of the
    // seed's real color. This was a real bug: color features have been
    // computed from already-grayscaled crops since the original MVP.
    final gray = img.grayscale(seed.crop.clone());
    final gradient = _sobelMagnitude(gray);

    final color = _colorFeatures(seed);
    final texture = _textureFeatures(seed, gray, gradient);
    final damage = _damageIndicators(seed, gray, color, texture);

    return SeedFeatures(
      geometry: seed.geometry,
      color: color,
      texture: texture,
      damage: damage,
    );
  }

  ColorFeatures _colorFeatures(SegmentedSeed seed) {
    double sumR = 0, sumG = 0, sumB = 0;
    double sumH = 0, sumS = 0, sumV = 0;
    double sumL = 0, sumA = 0, sumBLab = 0;
    int n = 0;

    final rs = <double>[], gs = <double>[], bs = <double>[], hues = <double>[];

    for (var y = 0; y < seed.crop.height; y++) {
      for (var x = 0; x < seed.crop.width; x++) {
        if (!seed.isForeground(x, y)) continue;
        final p = seed.crop.getPixel(x, y);
        final r = p.r.toDouble(), g = p.g.toDouble(), b = p.b.toDouble();
        rs.add(r);
        gs.add(g);
        bs.add(b);
        sumR += r;
        sumG += g;
        sumB += b;

        final hsv = _rgbToHsv(r, g, b);
        hues.add(hsv[0]);
        sumH += hsv[0];
        sumS += hsv[1];
        sumV += hsv[2];

        final lab = _rgbToLab(r, g, b);
        sumL += lab[0];
        sumA += lab[1];
        sumBLab += lab[2];

        n++;
      }
    }

    if (n == 0) {
      return const ColorFeatures(
        meanR: 0,
        meanG: 0,
        meanB: 0,
        meanHue: 0,
        meanSaturation: 0,
        meanValue: 0,
        meanLabL: 0,
        meanLabA: 0,
        meanLabB: 0,
        colorVarianceRgb: 0,
        discolorationRatio: 0,
      );
    }

    final meanR = sumR / n, meanG = sumG / n, meanB = sumB / n;

    double varSum = 0;
    for (var i = 0; i < rs.length; i++) {
      varSum += pow(rs[i] - meanR, 2) + pow(gs[i] - meanG, 2) + pow(bs[i] - meanB, 2);
    }
    final variance = varSum / n;

    // Discoloration proxy: fraction of foreground pixels whose hue departs
    // more than 40 degrees from the seed's own mean hue — a crude but
    // honest "how uniform is this seed's color" signal, not a claim about
    // what caused the variation. Reuses the hues collected above instead
    // of re-reading pixels and recomputing HSV a second time.
    final meanHue = sumH / n;
    int outliers = 0;
    for (final hue in hues) {
      var diff = (hue - meanHue).abs();
      if (diff > 180) diff = 360 - diff;
      if (diff > 40) outliers++;
    }

    return ColorFeatures(
      meanR: meanR,
      meanG: meanG,
      meanB: meanB,
      meanHue: meanHue,
      meanSaturation: sumS / n,
      meanValue: sumV / n,
      meanLabL: sumL / n,
      meanLabA: sumA / n,
      meanLabB: sumBLab / n,
      colorVarianceRgb: variance,
      discolorationRatio: outliers / n,
    );
  }

  /// 3x3 Sobel gradient magnitude (|Gx| + |Gy|) over the whole crop, with
  /// OpenCV's default BORDER_REFLECT_101 edge handling — the same
  /// definition `cv2.Sobel` gives the Python pipeline. Deliberately
  /// computed over every pixel (foreground and background) and only
  /// *read* at foreground locations afterward, matching how the Python
  /// side does it: a seed's edge pixels legitimately see gradient
  /// contribution from the background they sit against, on both sides
  /// identically.
  Float32List _sobelMagnitude(img.Image gray) {
    final w = gray.width, h = gray.height;
    final lum = Float32List(w * h);
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        lum[y * w + x] = img.getLuminance(gray.getPixel(x, y)).toDouble();
      }
    }

    final out = Float32List(w * h);
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        double gx = 0, gy = 0;
        var k = 0;
        for (var dy = -1; dy <= 1; dy++) {
          final ry = _reflect101(y + dy, h);
          for (var dx = -1; dx <= 1; dx++) {
            final rx = _reflect101(x + dx, w);
            final v = lum[ry * w + rx];
            gx += _sobelX[k] * v;
            gy += _sobelY[k] * v;
            k++;
          }
        }
        out[y * w + x] = gx.abs() + gy.abs();
      }
    }
    return out;
  }

  /// BORDER_REFLECT_101: reflects without repeating the edge sample, e.g.
  /// for width 5, index -1 maps to 1, -2 maps to 2, 5 maps to 3.
  int _reflect101(int i, int n) {
    if (n == 1) return 0;
    final period = 2 * (n - 1);
    var m = i % period;
    if (m < 0) m += period;
    return m < n ? m : period - m;
  }

  TextureFeatures _textureFeatures(SegmentedSeed seed, img.Image gray, Float32List gradient) {
    final w = gray.width, h = gray.height;

    int edgePixels = 0;
    int foregroundPixels = 0;
    final histogram = List<int>.filled(256, 0);
    double contrastSum = 0;

    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        if (!seed.isForeground(x, y)) continue;
        foregroundPixels++;
        final l = img.getLuminance(gray.getPixel(x, y));
        histogram[l.round().clamp(0, 255)]++;

        final g = gradient[y * w + x];
        contrastSum += g;
        if (g > _edgeGradientThreshold) edgePixels++;
      }
    }

    if (foregroundPixels == 0) {
      return const TextureFeatures(
        edgeDensity: 0,
        entropy: 0,
        surfaceIrregularity: 0,
        localContrast: 0,
      );
    }

    double entropy = 0;
    for (final count in histogram) {
      if (count == 0) continue;
      final p = count / foregroundPixels;
      entropy -= p * (log(p) / ln2);
    }

    return TextureFeatures(
      edgeDensity: edgePixels / foregroundPixels,
      entropy: entropy / 8.0, // normalize against max entropy (8 bits)
      surfaceIrregularity: (edgePixels / foregroundPixels).clamp(0.0, 1.0),
      localContrast: (contrastSum / foregroundPixels / 255).clamp(0.0, 1.0),
    );
  }

  DamageIndicators _damageIndicators(
    SegmentedSeed seed,
    img.Image gray,
    ColorFeatures color,
    TextureFeatures texture,
  ) {
    int darkPixels = 0, foreground = 0;
    double luminanceSum = 0;

    for (var y = 0; y < gray.height; y++) {
      for (var x = 0; x < gray.width; x++) {
        if (!seed.isForeground(x, y)) continue;
        foreground++;
        final l = img.getLuminance(gray.getPixel(x, y)).toDouble();
        luminanceSum += l;
        if (l < 60) darkPixels++;
      }
    }

    if (foreground == 0) {
      return const DamageIndicators(
        darkRegionRatio: 0,
        crackLikeEdgeRatio: 0,
        holeRatio: 0,
        abnormalPigmentationScore: 0,
      );
    }

    final holePixels = _countHolePixels(seed);
    final avgLuminance = luminanceSum / foreground;

    return DamageIndicators(
      darkRegionRatio: darkPixels / foreground,
      crackLikeEdgeRatio: texture.edgeDensity,
      holeRatio: (holePixels / foreground).clamp(0.0, 1.0),
      abnormalPigmentationScore:
          (color.discolorationRatio * 0.6 + (avgLuminance < 70 ? 0.4 : 0.0)).clamp(0.0, 1.0),
    );
  }

  /// Background pixels enclosed by foreground (topological holes — "small
  /// enclosed voids," §13): flood-fill every background pixel reachable
  /// (4-connected) from the crop's border, then any background pixel that
  /// flood never reaches is an enclosed pocket. Seeding from the whole
  /// border, not just one corner, matters — a shape that happens to touch
  /// its own bounding-box corner would otherwise silently misclassify its
  /// entire outside as "holes." Matches
  /// `ml/preprocessing/features.py::_hole_ratio`.
  int _countHolePixels(SegmentedSeed seed) {
    final w = seed.crop.width, h = seed.crop.height;
    final reached = Uint8List(w * h);
    final queue = Uint32List(w * h);
    var head = 0, tail = 0;

    void trySeedPixel(int x, int y) {
      if (x < 0 || y < 0 || x >= w || y >= h) return;
      final idx = y * w + x;
      if (reached[idx] != 0 || seed.isForeground(x, y)) return;
      reached[idx] = 1;
      queue[tail++] = idx;
    }

    for (var x = 0; x < w; x++) {
      trySeedPixel(x, 0);
      trySeedPixel(x, h - 1);
    }
    for (var y = 0; y < h; y++) {
      trySeedPixel(0, y);
      trySeedPixel(w - 1, y);
    }

    while (head < tail) {
      final idx = queue[head++];
      final x = idx % w, y = idx ~/ w;
      trySeedPixel(x - 1, y);
      trySeedPixel(x + 1, y);
      trySeedPixel(x, y - 1);
      trySeedPixel(x, y + 1);
    }

    var holes = 0;
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        if (!seed.isForeground(x, y) && reached[y * w + x] == 0) holes++;
      }
    }
    return holes;
  }

  List<double> _rgbToHsv(double r, double g, double b) {
    final rN = r / 255, gN = g / 255, bN = b / 255;
    final maxV = [rN, gN, bN].reduce(max);
    final minV = [rN, gN, bN].reduce(min);
    final delta = maxV - minV;

    double hue = 0;
    if (delta != 0) {
      if (maxV == rN) {
        hue = 60 * (((gN - bN) / delta) % 6);
      } else if (maxV == gN) {
        hue = 60 * (((bN - rN) / delta) + 2);
      } else {
        hue = 60 * (((rN - gN) / delta) + 4);
      }
    }
    if (hue < 0) hue += 360;
    final saturation = maxV == 0 ? 0.0 : delta / maxV;
    return [hue, saturation, maxV];
  }

  List<double> _rgbToLab(double r, double g, double b) {
    // sRGB -> linear -> XYZ -> CIE Lab, D65 white point.
    double toLinear(double c) {
      final v = c / 255;
      return v <= 0.04045 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4).toDouble();
    }

    final rl = toLinear(r), gl = toLinear(g), bl = toLinear(b);

    final x = rl * 0.4124 + gl * 0.3576 + bl * 0.1805;
    final y = rl * 0.2126 + gl * 0.7152 + bl * 0.0722;
    final z = rl * 0.0193 + gl * 0.1192 + bl * 0.9505;

    const xn = 0.95047, yn = 1.0, zn = 1.08883;
    double f(double t) => t > 0.008856 ? pow(t, 1 / 3).toDouble() : (7.787 * t) + (16 / 116);

    final fx = f(x / xn), fy = f(y / yn), fz = f(z / zn);

    final l = (116 * fy) - 16;
    final a = 500 * (fx - fy);
    final labB = 200 * (fy - fz);
    return [l, a, labB];
  }
}

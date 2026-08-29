import 'dart:math';

import 'package:image/image.dart' as img;

import '../domain/entities/seed_features.dart';
import 'segmented_seed.dart';

/// Computes color, texture, and damage-heuristic features (§13) over the
/// masked pixels of a [SegmentedSeed]. Geometry is already known from
/// segmentation (see [SegmentedSeed.geometry]) — this class only adds what
/// segmentation didn't already compute.
class FeatureExtractor {
  const FeatureExtractor();

  SeedFeatures extract(SegmentedSeed seed) {
    final color = _colorFeatures(seed);
    final texture = _textureFeatures(seed);
    final damage = _damageIndicators(seed, color);

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

    final rs = <double>[], gs = <double>[], bs = <double>[];

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
    // what caused the variation.
    final meanHue = sumH / n;
    int outliers = 0;
    for (var y = 0; y < seed.crop.height; y++) {
      for (var x = 0; x < seed.crop.width; x++) {
        if (!seed.isForeground(x, y)) continue;
        final p = seed.crop.getPixel(x, y);
        final hsv = _rgbToHsv(p.r.toDouble(), p.g.toDouble(), p.b.toDouble());
        var diff = (hsv[0] - meanHue).abs();
        if (diff > 180) diff = 360 - diff;
        if (diff > 40) outliers++;
      }
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

  TextureFeatures _textureFeatures(SegmentedSeed seed) {
    final gray = img.grayscale(seed.crop);
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

        final right = x + 1 < w && seed.isForeground(x + 1, y)
            ? img.getLuminance(gray.getPixel(x + 1, y))
            : l;
        final down = y + 1 < h && seed.isForeground(x, y + 1)
            ? img.getLuminance(gray.getPixel(x, y + 1))
            : l;
        final gradient = (l - right).abs() + (l - down).abs();
        contrastSum += gradient;
        if (gradient > 30) edgePixels++;
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

  DamageIndicators _damageIndicators(SegmentedSeed seed, ColorFeatures color) {
    final gray = img.grayscale(seed.crop);
    int darkPixels = 0, holeCandidates = 0, foreground = 0;
    final meanLuminance = <double>[];

    for (var y = 0; y < gray.height; y++) {
      for (var x = 0; x < gray.width; x++) {
        if (!seed.isForeground(x, y)) continue;
        foreground++;
        final l = img.getLuminance(gray.getPixel(x, y)).toDouble();
        meanLuminance.add(l);
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

    // "Holes": small fully-enclosed background pockets strictly inside the
    // bounding box (not touching its border) — a simple proxy without a
    // full topology pass.
    final w = seed.crop.width, h = seed.crop.height;
    for (var y = 1; y < h - 1; y++) {
      for (var x = 1; x < w - 1; x++) {
        if (seed.isForeground(x, y)) continue;
        final surroundedByForeground = seed.isForeground(x - 1, y) &&
            seed.isForeground(x + 1, y) &&
            seed.isForeground(x, y - 1) &&
            seed.isForeground(x, y + 1);
        if (surroundedByForeground) holeCandidates++;
      }
    }

    final avgLuminance = meanLuminance.reduce((a, b) => a + b) / meanLuminance.length;
    final crackRatio = _textureFeatures(seed).edgeDensity;

    return DamageIndicators(
      darkRegionRatio: darkPixels / foreground,
      crackLikeEdgeRatio: crackRatio,
      holeRatio: (holeCandidates / foreground).clamp(0.0, 1.0),
      abnormalPigmentationScore:
          (color.discolorationRatio * 0.6 + (avgLuminance < 70 ? 0.4 : 0.0)).clamp(0.0, 1.0),
    );
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

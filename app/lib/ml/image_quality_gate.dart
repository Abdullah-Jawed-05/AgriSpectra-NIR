import 'dart:math';

import 'package:image/image.dart' as img;

import '../domain/entities/image_quality_report.dart';

/// Pre-inference image quality assessment (§10). Nothing downstream runs
/// on an image this gate rejects — the caller must show [ImageQualityReport
/// .warnings] instead of silently degrading.
class ImageQualityGate {
  const ImageQualityGate({
    this.minResolutionPx = 720,
    this.minAcceptableScore = 0.55,
    this.workingMaxDimension = 900,
  });

  final int minResolutionPx;
  final double minAcceptableScore;

  /// A phone camera frame can be 12MP+; none of these metrics are
  /// statistical estimates that need full resolution, so everything past
  /// the resolution check itself runs on a downscaled copy. Without this,
  /// a full-resolution image means multiple whole-image pixel passes
  /// (grayscale conversion + exposure/glare/background), which is the
  /// dominant cost of the entire analysis pipeline on a real device —
  /// resolution is checked against the *original* dimensions first, then
  /// every subsequent metric runs on the downscaled copy.
  final int workingMaxDimension;

  /// Working-image tile edge for the background-texture pass. Big enough
  /// that a single seed edge doesn't dominate a tile, small enough that a
  /// woven / printed / grained background lights up most tiles.
  static const int _textureTilePx = 48;

  /// A tile whose Laplacian-response variance clears this is "busy" (has
  /// real high-frequency structure, not just a smooth gradient). On the
  /// barley reference sets, clean matte-paper captures keep <45% of tiles
  /// busy; woven-mat captures sit above 85%.
  static const double _busyTileLapVar = 40;

  /// A tile whose luminance std-dev is below this is "flat" — part of an
  /// even backdrop rather than seed or texture.
  static const double _flatTileStdDev = 6;

  /// Hard-reject thresholds for a patterned background: seeds shot on a
  /// woven mat / fabric / wood grain fragment into dozens of spurious
  /// blobs and nothing downstream can recover. Tuned on 158 clean + 270
  /// textured barley photos: the median-tile-std cutoff alone false-
  /// rejects 0 of the clean set, and either condition catches ~97% of the
  /// textured set. The busy-tile cutoff is deliberately well above the
  /// clean set's p90 (~0.42) so a higher-ISO capture isn't punished for
  /// sensor noise. See docs/VALIDATION.md.
  static const double _rejectBusyTileRatio = 0.80;
  static const double _rejectMedianTileStdDev = 3.2;

  ImageQualityReport evaluate(img.Image original) {
    final warnings = <String>[];

    final resolutionOk = min(original.width, original.height) >= minResolutionPx;
    if (!resolutionOk) {
      warnings.add(
        'Image resolution is too low (${original.width}x${original.height}). '
        'Move closer or use a higher-resolution camera setting.',
      );
    }

    final image = _downscale(original, workingMaxDimension);
    final gray = img.grayscale(image);

    final blurScore = _blurScore(gray);
    if (blurScore < 0.4) {
      warnings.add('Image appears blurry. Hold the phone steady and let it focus before capturing.');
    }

    // Exposure, glare, and global contrast are all derived from the same
    // per-pixel luminance value, so they're computed together in one pass
    // rather than three separate whole-image loops.
    final stats = _luminanceStats(gray);

    final overexposed = stats.overexposedRatio;
    final underexposed = stats.underexposedRatio;
    if (overexposed > 0.05) warnings.add('Image is overexposed. Reduce lighting or move out of direct sun.');
    if (underexposed > 0.15) warnings.add('Image is underexposed. Increase lighting.');
    final exposurePenalty = (overexposed * 3 + underexposed * 2).clamp(0.0, 1.0);
    final exposureScore = (1.0 - exposurePenalty).clamp(0.0, 1.0);

    final glareScore = (1.0 - (stats.brightRatio * 6)).clamp(0.0, 1.0);
    if (glareScore < 0.6) {
      warnings.add('Strong glare detected. Adjust lighting or angle to reduce reflections.');
    }

    // Background assessment has two failure modes, both fatal for
    // segmentation:
    //  1. A busy / textured background (woven mat, fabric, wood grain,
    //     printed surface) — the dominant real-world failure. Its own
    //     structure fragments into dozens of seed-sized blobs.
    //  2. A background too close in tone to the seeds — nothing to
    //     threshold against.
    final texture = _tileTextureStats(gray);

    final textureHardReject = texture.busyTileRatio > _rejectBusyTileRatio ||
        texture.medianTileStdDev > _rejectMedianTileStdDev;

    // Graded 1 (clean) -> 0 (textured), from whichever signal is worse.
    final byMedian =
        (1.0 - (texture.medianTileStdDev - 2.5) / 4.0).clamp(0.0, 1.0);
    final byBusy = (1.0 - (texture.busyTileRatio - 0.45) / 0.40).clamp(0.0, 1.0);
    final textureScore = min(byMedian, byBusy);

    // A clear uniform backdrop (many flat tiles) means contrast is fine
    // regardless of the global spread — otherwise a small seed on a large
    // plain field would read as "low contrast". Only when there's no such
    // backdrop do we fall back to the global std-dev.
    final contrastScore = texture.flatTileRatio >= 0.35
        ? 1.0
        : (stats.stdDev / 28.0).clamp(0.0, 1.0);

    final backgroundScore = min(textureScore, contrastScore);

    if (textureHardReject) {
      warnings.add(
        'The background is textured or patterned (woven fabric, mat, wood '
        'grain, printed surface). It breaks the seed outlines into fragments. '
        'Place the seeds on a plain sheet of matte paper or a smooth, '
        'evenly-coloured surface.',
      );
    } else if (textureScore < 0.6) {
      warnings.add(
        'The background looks slightly textured. For the most reliable '
        'result, use a plain sheet of matte paper or a smooth, evenly-'
        'coloured surface.',
      );
    } else if (contrastScore < 0.5) {
      warnings.add('Background is too similar to the seeds. Use a plain, contrasting background.');
    }

    final resolutionScore = resolutionOk ? 1.0 : 0.3;

    final qualityScore = (blurScore * 0.30 +
            exposureScore * 0.25 +
            glareScore * 0.15 +
            backgroundScore * 0.20 +
            resolutionScore * 0.10)
        .clamp(0.0, 1.0);

    return ImageQualityReport(
      usable: qualityScore >= minAcceptableScore && resolutionOk && !textureHardReject,
      qualityScore: qualityScore,
      blurScore: blurScore,
      exposureScore: exposureScore,
      glareScore: glareScore,
      backgroundScore: backgroundScore,
      textureScore: textureScore,
      warnings: warnings,
    );
  }

  /// Grid pass over the working image: for each [_textureTilePx] tile,
  /// the luminance std-dev and the variance of a cheap 4-neighbour
  /// Laplacian. From those:
  ///  - [_TileTextureStats.medianTileStdDev] — robust to a few seed tiles,
  ///    so it tracks the *background*: near-zero for paper, high for a mat.
  ///  - [_TileTextureStats.busyTileRatio] — how much of the frame carries
  ///    real high-frequency structure.
  ///  - [_TileTextureStats.flatTileRatio] — how much is an even backdrop.
  _TileTextureStats _tileTextureStats(img.Image gray) {
    final w = gray.width, h = gray.height;
    final tile = _textureTilePx;
    // Sample every other pixel inside a tile — enough for these stats and
    // a quarter of the work.
    const sampleStep = 2;

    final stdDevs = <double>[];
    var busy = 0, flat = 0, tiles = 0;

    for (var ty = 0; ty + tile <= h; ty += tile) {
      for (var tx = 0; tx + tile <= w; tx += tile) {
        double sum = 0, sumSq = 0;
        double lapSum = 0, lapSumSq = 0;
        var n = 0, lapN = 0;
        for (var y = ty; y < ty + tile; y += sampleStep) {
          for (var x = tx; x < tx + tile; x += sampleStep) {
            final l = img.getLuminance(gray.getPixel(x, y));
            sum += l;
            sumSq += l * l;
            n++;
            // 4-neighbour Laplacian, staying inside the tile.
            if (x > tx && x < tx + tile - 1 && y > ty && y < ty + tile - 1) {
              final lap = 4 * l -
                  img.getLuminance(gray.getPixel(x - 1, y)) -
                  img.getLuminance(gray.getPixel(x + 1, y)) -
                  img.getLuminance(gray.getPixel(x, y - 1)) -
                  img.getLuminance(gray.getPixel(x, y + 1));
              lapSum += lap;
              lapSumSq += lap * lap;
              lapN++;
            }
          }
        }
        if (n == 0 || lapN == 0) continue;
        final mean = sum / n;
        final variance = (sumSq / n) - (mean * mean);
        final stdDev = sqrt(max(0, variance));
        final lapMean = lapSum / lapN;
        final lapVar = (lapSumSq / lapN) - (lapMean * lapMean);

        stdDevs.add(stdDev);
        if (lapVar > _busyTileLapVar) busy++;
        if (stdDev < _flatTileStdDev) flat++;
        tiles++;
      }
    }

    if (tiles == 0) {
      return const _TileTextureStats(
        medianTileStdDev: 0,
        busyTileRatio: 0,
        flatTileRatio: 1,
      );
    }

    stdDevs.sort();
    final mid = stdDevs.length ~/ 2;
    final median = stdDevs.length.isOdd
        ? stdDevs[mid]
        : (stdDevs[mid - 1] + stdDevs[mid]) / 2;

    return _TileTextureStats(
      medianTileStdDev: median,
      busyTileRatio: busy / tiles,
      flatTileRatio: flat / tiles,
    );
  }

  img.Image _downscale(img.Image image, int maxDim) {
    if (max(image.width, image.height) <= maxDim) return image;
    return image.width >= image.height
        ? img.copyResize(image, width: maxDim)
        : img.copyResize(image, height: maxDim);
  }

  /// Variance of the Laplacian, normalized into a rough 0..1 "sharpness"
  /// score. This is the standard cheap blur proxy — a genuinely blurry
  /// image has low high-frequency energy, so the Laplacian response is
  /// low-variance.
  double _blurScore(img.Image gray) {
    const kernel = [0, 1, 0, 1, -4, 1, 0, 1, 0];
    final w = gray.width, h = gray.height;
    // Sample on a grid rather than every pixel — this only needs to be a
    // fast pre-inference gate, not a precise metric.
    final stepX = max(1, w ~/ 200);
    final stepY = max(1, h ~/ 200);

    double sum = 0, sumSq = 0;
    int n = 0;
    for (var y = 1; y < h - 1; y += stepY) {
      for (var x = 1; x < w - 1; x += stepX) {
        double acc = 0;
        var k = 0;
        for (var dy = -1; dy <= 1; dy++) {
          for (var dx = -1; dx <= 1; dx++) {
            acc += kernel[k] * img.getLuminance(gray.getPixel(x + dx, y + dy));
            k++;
          }
        }
        sum += acc;
        sumSq += acc * acc;
        n++;
      }
    }
    if (n == 0) return 0;
    final mean = sum / n;
    final variance = (sumSq / n) - (mean * mean);
    // Empirically, variance below ~50 reads as visibly blurry on phone
    // photos at this sampling density; above ~600 is comfortably sharp.
    return (variance / 600).clamp(0.0, 1.0);
  }

  _LuminanceStats _luminanceStats(img.Image gray) {
    final total = gray.width * gray.height;
    int overexposedCount = 0, underexposedCount = 0, brightCount = 0;
    double sum = 0, sumSq = 0;

    for (final pixel in gray) {
      final l = img.getLuminance(pixel);
      sum += l;
      sumSq += l * l;
      if (l >= 250) overexposedCount++;
      if (l <= 5) underexposedCount++;
      if (l > 248) brightCount++;
    }

    final mean = sum / total;
    final variance = (sumSq / total) - (mean * mean);

    return _LuminanceStats(
      overexposedRatio: overexposedCount / total,
      underexposedRatio: underexposedCount / total,
      brightRatio: brightCount / total,
      stdDev: sqrt(max(0, variance)),
    );
  }
}

class _TileTextureStats {
  final double medianTileStdDev;
  final double busyTileRatio;
  final double flatTileRatio;

  const _TileTextureStats({
    required this.medianTileStdDev,
    required this.busyTileRatio,
    required this.flatTileRatio,
  });
}

class _LuminanceStats {
  final double overexposedRatio;
  final double underexposedRatio;
  final double brightRatio;
  final double stdDev;

  const _LuminanceStats({
    required this.overexposedRatio,
    required this.underexposedRatio,
    required this.brightRatio,
    required this.stdDev,
  });
}

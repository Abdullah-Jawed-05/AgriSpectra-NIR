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

    // Exposure, glare, and background contrast are all derived from the
    // same per-pixel luminance value, so they're computed together in one
    // pass rather than three separate whole-image loops.
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

    // A plain contrasting tray background against seeds typically produces
    // luminance std-dev well above 35 in practice; below ~15 is flat/low
    // contrast — see _backgroundScore's original derivation.
    final backgroundScore = (stats.stdDev / 45).clamp(0.0, 1.0);
    if (backgroundScore < 0.4) {
      warnings.add('Background is too similar to the seeds. Use a plain, contrasting background.');
    }

    final resolutionScore = resolutionOk ? 1.0 : 0.3;

    final qualityScore = (blurScore * 0.30 +
            exposureScore * 0.25 +
            glareScore * 0.2 +
            backgroundScore * 0.15 +
            resolutionScore * 0.1)
        .clamp(0.0, 1.0);

    return ImageQualityReport(
      usable: qualityScore >= minAcceptableScore && resolutionOk,
      qualityScore: qualityScore,
      blurScore: blurScore,
      exposureScore: exposureScore,
      glareScore: glareScore,
      backgroundScore: backgroundScore,
      warnings: warnings,
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

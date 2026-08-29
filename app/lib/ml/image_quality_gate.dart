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
  });

  final int minResolutionPx;
  final double minAcceptableScore;

  ImageQualityReport evaluate(img.Image image) {
    final warnings = <String>[];

    final resolutionOk = min(image.width, image.height) >= minResolutionPx;
    if (!resolutionOk) {
      warnings.add(
        'Image resolution is too low (${image.width}x${image.height}). '
        'Move closer or use a higher-resolution camera setting.',
      );
    }

    final gray = img.grayscale(image);

    final blurScore = _blurScore(gray);
    if (blurScore < 0.4) {
      warnings.add('Image appears blurry. Hold the phone steady and let it focus before capturing.');
    }

    final exposureScore = _exposureScore(gray, warnings);
    final glareScore = _glareScore(gray);
    if (glareScore < 0.6) {
      warnings.add('Strong glare detected. Adjust lighting or angle to reduce reflections.');
    }

    final backgroundScore = _backgroundScore(gray);
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

  double _exposureScore(img.Image gray, List<String> warnings) {
    final histogram = List<int>.filled(256, 0);
    for (final pixel in gray) {
      histogram[img.getLuminance(pixel).round().clamp(0, 255)]++;
    }
    final total = gray.width * gray.height;

    final overexposed = histogram.sublist(250).fold(0, (a, b) => a + b) / total;
    final underexposed = histogram.sublist(0, 6).fold(0, (a, b) => a + b) / total;

    if (overexposed > 0.05) warnings.add('Image is overexposed. Reduce lighting or move out of direct sun.');
    if (underexposed > 0.15) warnings.add('Image is underexposed. Increase lighting.');

    final penalty = (overexposed * 3 + underexposed * 2).clamp(0.0, 1.0);
    return (1.0 - penalty).clamp(0.0, 1.0);
  }

  double _glareScore(img.Image gray) {
    int brightPixels = 0;
    final total = gray.width * gray.height;
    for (final pixel in gray) {
      if (img.getLuminance(pixel) > 248) brightPixels++;
    }
    final glareRatio = brightPixels / total;
    return (1.0 - (glareRatio * 6)).clamp(0.0, 1.0);
  }

  /// Approximates "is the background distinct from the seeds" via overall
  /// image contrast (std. dev. of luminance). A low-contrast frame usually
  /// means the seeds blend into the background, which is exactly the
  /// condition that breaks thresholding-based detection downstream.
  double _backgroundScore(img.Image gray) {
    double sum = 0, sumSq = 0;
    final total = gray.width * gray.height;
    for (final pixel in gray) {
      final l = img.getLuminance(pixel);
      sum += l;
      sumSq += l * l;
    }
    final mean = sum / total;
    final variance = (sumSq / total) - (mean * mean);
    final stdDev = sqrt(max(0, variance));
    // A plain contrasting tray background against seeds typically produces
    // luminance std-dev well above 35 in practice; below ~15 is flat/low
    // contrast.
    return (stdDev / 45).clamp(0.0, 1.0);
  }
}

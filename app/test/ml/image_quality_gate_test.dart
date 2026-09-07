import 'dart:math';

import 'package:agrispectra/ml/image_quality_gate.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

/// A plain, evenly-lit backdrop with one dark seed-sized blob — what a
/// good capture looks like. Faint seeded noise so no region is perfectly
/// flat, but far below the pixel-to-pixel energy of a real textured
/// surface (a phone photo's sensor noise is spatially smoother than
/// i.i.d. noise and JPEG smooths it further).
img.Image _cleanCapture() {
  final rng = Random(7);
  final image = img.Image(width: 900, height: 900);
  for (final p in image) {
    final n = rng.nextInt(3) - 1;
    final inBlob = (p.x - 450) * (p.x - 450) + (p.y - 450) * (p.y - 450) < 90 * 90;
    final v = (inBlob ? 70 : 205) + n;
    p.setRgb(v, v, v);
  }
  return image;
}

/// A busy woven/printed surface: fine high-frequency texture across the
/// whole frame. Its global std-dev is *high* — the metric the old gate
/// rewarded — but it fragments segmentation into dozens of blobs.
img.Image _texturedBackground() {
  final rng = Random(11);
  final image = img.Image(width: 900, height: 900);
  for (final p in image) {
    // 3px woven weave + per-pixel grain.
    final weave = ((p.x ~/ 3) + (p.y ~/ 3)).isEven ? 40 : 0;
    final v = (110 + weave + rng.nextInt(50)).clamp(0, 255);
    p.setRgb(v, v, v);
  }
  return image;
}

void main() {
  const gate = ImageQualityGate();

  test('a plain backdrop with one blob passes the background checks', () {
    final report = gate.evaluate(_cleanCapture());

    expect(report.textureScore, greaterThan(0.8));
    expect(report.backgroundScore, greaterThan(0.7));
    expect(
      report.warnings.where((w) => w.toLowerCase().contains('textured')),
      isEmpty,
    );
  });

  test('a textured background is rejected even though its global contrast is high', () {
    final report = gate.evaluate(_texturedBackground());

    expect(report.usable, isFalse);
    expect(report.textureScore, lessThan(0.3));
    expect(
      report.warnings.any((w) => w.contains('textured or patterned')),
      isTrue,
      reason: 'must tell the user the background is the problem',
    );
  });
}

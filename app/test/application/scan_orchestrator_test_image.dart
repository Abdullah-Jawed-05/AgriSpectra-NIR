import 'dart:math';
import 'dart:typed_data';

import 'package:image/image.dart' as img;

/// A plain grey frame with a 3x5 grid of hard-edged dark blobs — passes
/// the quality gate (resolution, blur, texture) and gives the classical
/// detector 15 clean seeds to segment. Shared by the scan-orchestrator and
/// provider-graph tests.
Uint8List syntheticScanBytes() {
  final rng = Random(7);
  final image = img.Image(width: 1280, height: 960);
  for (final p in image) {
    final v = 210 + rng.nextInt(3) - 1;
    p.setRgb(v, v, v);
  }
  for (var gy = 0; gy < 3; gy++) {
    for (var gx = 0; gx < 5; gx++) {
      img.fillCircle(
        image,
        x: 180 + gx * 230,
        y: 210 + gy * 270,
        radius: 34,
        color: img.ColorRgb8(28, 28, 28),
      );
    }
  }
  return img.encodePng(image);
}

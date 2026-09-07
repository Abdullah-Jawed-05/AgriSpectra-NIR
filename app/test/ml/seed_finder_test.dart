import 'dart:math';

import 'package:agrispectra/ml/seed_finder.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

/// A plain background with one filled rectangular blob, high-contrast
/// enough for Otsu thresholding to isolate it cleanly.
///
/// Both regions get small pseudo-random per-pixel noise (seeded, so tests
/// stay deterministic) rather than one flat colour each. A perfectly flat
/// two-value image is a degenerate case for this Otsu implementation — the
/// threshold lands exactly on the darker value and the strict `<` for the
/// dark-foreground polarity then excludes it. The noise must be genuinely
/// random, not a periodic pattern: a diagonal dither can fragment a blob
/// into diagonal strips once lighting normalisation compresses its value
/// range against the threshold. Real photos carry real sensor noise;
/// fixtures have to add it deliberately.
img.Image _canvasWithBlob({
  required int canvasW,
  required int canvasH,
  required int blobX,
  required int blobY,
  required int blobW,
  required int blobH,
  required List<int> bgRgb,
  required List<int> blobRgb,
  // Optional rectangular "bite" cut out of the blob, to make it concave.
  int? biteX,
  int? biteY,
  int? biteW,
  int? biteH,
}) {
  final rng = Random(42);
  int jitter(int v) => (v + rng.nextInt(7) - 3).clamp(0, 255);
  bool inBite(int x, int y) =>
      biteX != null &&
      x >= biteX &&
      x < biteX + biteW! &&
      y >= biteY! &&
      y < biteY + biteH!;

  final image = img.Image(width: canvasW, height: canvasH);
  for (var y = 0; y < canvasH; y++) {
    for (var x = 0; x < canvasW; x++) {
      image.setPixelRgb(
        x,
        y,
        jitter(bgRgb[0]),
        jitter(bgRgb[1]),
        jitter(bgRgb[2]),
      );
    }
  }
  for (var y = blobY; y < blobY + blobH; y++) {
    for (var x = blobX; x < blobX + blobW; x++) {
      if (inBite(x, y)) continue;
      image.setPixelRgb(
        x,
        y,
        jitter(blobRgb[0]),
        jitter(blobRgb[1]),
        jitter(blobRgb[2]),
      );
    }
  }
  return image;
}

/// A plain background with one filled disk, same jitter treatment as
/// [_canvasWithBlob].
img.Image _canvasWithDisk({
  required int canvasW,
  required int canvasH,
  required int centerX,
  required int centerY,
  required int radius,
  required List<int> bgRgb,
  required List<int> blobRgb,
}) {
  final rng = Random(42);
  int jitter(int v) => (v + rng.nextInt(7) - 3).clamp(0, 255);

  final image = img.Image(width: canvasW, height: canvasH);
  final r2 = radius * radius;
  for (var y = 0; y < canvasH; y++) {
    for (var x = 0; x < canvasW; x++) {
      final dx = x - centerX, dy = y - centerY;
      final inDisk = dx * dx + dy * dy <= r2;
      final rgb = inDisk ? blobRgb : bgRgb;
      image.setPixelRgb(x, y, jitter(rgb[0]), jitter(rgb[1]), jitter(rgb[2]));
    }
  }
  return image;
}

void main() {
  final finder = ClassicalCVSeedFinder();

  test(
    'detects a single high-contrast blob and preserves its color '
    '(regression: img.grayscale() must not mutate the source image)',
    () {
      final image = _canvasWithBlob(
        canvasW: 400,
        canvasH: 300,
        blobX: 150,
        blobY: 100,
        blobW: 60,
        blobH: 50,
        bgRgb: [170, 170, 170],
        blobRgb: [200, 80, 40], // distinctly non-gray: r != g != b
      );

      final seeds = finder.find(image);
      expect(seeds, hasLength(1));

      final crop = seeds.single.crop;
      final p = crop.getPixel(crop.width ~/ 2, crop.height ~/ 2);
      // If img.grayscale() had mutated the source image in place (the bug
      // this guards against), every channel here would have collapsed to
      // the same luminance value. Exact values aren't checked — lighting
      // normalisation legitimately rescales them — only that the injected
      // colour's channel separation survives (r clearly > g clearly > b).
      expect(p.r - p.g, greaterThan(15));
      expect(p.g - p.b, greaterThan(8));
    },
  );

  test('a near-round blob is meaningfully more circular than a square one', () {
    final square = _canvasWithBlob(
      canvasW: 400,
      canvasH: 300,
      blobX: 150,
      blobY: 100,
      blobW: 60,
      blobH: 60,
      bgRgb: [170, 170, 170],
      blobRgb: [40, 40, 40],
    );
    final disk = _canvasWithDisk(
      canvasW: 400,
      canvasH: 300,
      centerX: 200,
      centerY: 150,
      radius: 34,
      bgRgb: [170, 170, 170],
      blobRgb: [40, 40, 40],
    );

    final squareSeeds = finder.find(square);
    final diskSeeds = finder.find(disk);
    expect(squareSeeds, hasLength(1));
    expect(diskSeeds, hasLength(1));

    // Relative, not a magic absolute constant: a disk is the shape that
    // maximizes circularity (theoretical max 1.0); a square is a fixed
    // amount less circular (theoretical pi/4 ~ 0.785) regardless of the
    // exact pixel-discretization/perimeter-tracing noise either measurement
    // carries.
    expect(diskSeeds.single.geometry.circularity, greaterThan(squareSeeds.single.geometry.circularity));
  });

  test('convexity is meaningfully lower for a notched (concave) blob than a solid one', () {
    final solid = _canvasWithBlob(
      canvasW: 400,
      canvasH: 300,
      blobX: 150,
      blobY: 100,
      blobW: 70,
      blobH: 50,
      bgRgb: [170, 170, 170],
      blobRgb: [40, 40, 40],
    );
    // Same footprint as `solid`, but with a rectangular bite taken out of
    // one side — a simple concave (non-convex) shape.
    final notched = _canvasWithBlob(
      canvasW: 400,
      canvasH: 300,
      blobX: 150,
      blobY: 100,
      blobW: 70,
      blobH: 50,
      bgRgb: [170, 170, 170],
      blobRgb: [40, 40, 40],
      biteX: 150,
      biteY: 115,
      biteW: 30,
      biteH: 20,
    );

    final solidSeeds = finder.find(solid);
    final notchedSeeds = finder.find(notched);
    expect(solidSeeds, hasLength(1));
    expect(notchedSeeds, hasLength(1));

    expect(solidSeeds.single.geometry.convexity, greaterThan(0.75));
    expect(notchedSeeds.single.geometry.convexity, lessThan(solidSeeds.single.geometry.convexity));
  });

  test('an elongated blob has aspect ratio well above 1', () {
    final image = _canvasWithBlob(
      canvasW: 400,
      canvasH: 300,
      blobX: 100,
      blobY: 130,
      blobW: 150,
      blobH: 20,
      bgRgb: [170, 170, 170],
      blobRgb: [40, 40, 40],
    );
    final seeds = finder.find(image);
    expect(seeds.single.geometry.aspectRatio, greaterThan(3));
  });
}

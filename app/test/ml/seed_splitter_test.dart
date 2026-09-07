import 'dart:math';
import 'dart:typed_data';

import 'package:agrispectra/ml/seed_finder.dart';
import 'package:agrispectra/ml/seed_splitter.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

/// Fills a row-major 0/255 mask with a disc.
void _disc(Uint8List m, int w, int h, int cx, int cy, int r) {
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      if ((x - cx) * (x - cx) + (y - cy) * (y - cy) <= r * r) m[y * w + x] = 255;
    }
  }
}

/// A 1000x800 grey scene with a dark grain at each centre. Noise is added
/// *after* drawing so neither the background nor the grains are a single
/// histogram spike — a flat two-value image is a degenerate case for this
/// Otsu implementation (see seed_finder_test.dart).
img.Image _sceneWithGrains(List<List<int>> centres) {
  final rng = Random(3);
  final image = img.Image(width: 1000, height: 800);
  for (final p in image) {
    p.setRgb(210, 210, 210);
  }
  for (final c in centres) {
    img.fillCircle(image, x: c[0], y: c[1], radius: 34, color: img.ColorRgb8(30, 30, 30));
  }
  for (final p in image) {
    final n = rng.nextInt(9) - 4;
    p.setRgb((p.r + n).clamp(0, 255).toInt(), (p.g + n).clamp(0, 255).toInt(), (p.b + n).clamp(0, 255).toInt());
  }
  return image;
}

void main() {
  const splitter = SeedSplitter();

  test('two overlapping discs split into two parts', () {
    const w = 120, h = 80;
    final m = Uint8List(w * h);
    _disc(m, w, h, 45, 40, 24);
    _disc(m, w, h, 75, 40, 24); // centres 30 apart, radii 24 -> overlap

    final parts = splitter.split(m, w, h);
    expect(parts.length, 2);
    // both parts are a real chunk of the blob
    final total = m.where((v) => v != 0).length;
    for (final p in parts) {
      expect(p.length, greaterThan(total * 0.3));
    }
  });

  test('a single disc is left alone', () {
    const w = 100, h = 100;
    final m = Uint8List(w * h);
    _disc(m, w, h, 50, 50, 30);
    expect(splitter.split(m, w, h), isEmpty);
  });

  test('three touching discs in a row split into three', () {
    const w = 180, h = 70;
    final m = Uint8List(w * h);
    _disc(m, w, h, 40, 35, 22);
    _disc(m, w, h, 78, 35, 22);
    _disc(m, w, h, 116, 35, 22);
    expect(splitter.split(m, w, h).length, 3);
  });

  test('an empty mask returns nothing', () {
    expect(splitter.split(Uint8List(64), 8, 8), isEmpty);
  });

  test('the seed finder splits a touching pair into two seeds', () {
    final image = _sceneWithGrains(const [
      [250, 250],
      [620, 430],
      [675, 430], // touching the one at 620
    ]);

    final finder = ClassicalCVSeedFinder();
    final seeds = finder.find(image);

    expect(finder.lastComponentsSplit, 1);
    expect(seeds.length, 3);
  });

  test('disabling the splitter leaves the touching pair merged', () {
    final image = _sceneWithGrains(const [
      [250, 250],
      [620, 430],
      [675, 430],
    ]);
    final seeds = ClassicalCVSeedFinder(splitter: null).find(image);
    expect(seeds.length, 2);
  });
}

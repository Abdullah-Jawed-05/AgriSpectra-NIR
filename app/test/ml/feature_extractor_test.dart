import 'dart:typed_data';
import 'dart:ui';

import 'package:agrispectra/domain/entities/seed_features.dart';
import 'package:agrispectra/ml/feature_extractor.dart';
import 'package:agrispectra/ml/segmented_seed.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

const _dummyGeometry = GeometryFeatures(
  areaPx: 0,
  perimeterPx: 0,
  widthPx: 0,
  lengthPx: 0,
  aspectRatio: 0,
  circularity: 0,
  eccentricity: 0,
  convexity: 0,
);

/// Builds a [SegmentedSeed] with a hand-specified foreground mask, so the
/// extractor's texture/damage math can be tested against known shapes
/// without going through full detection.
SegmentedSeed _seedFromMask({
  required int w,
  required int h,
  required bool Function(int x, int y) isForegroundFn,
  required List<int> fgRgb,
  List<int> bgRgb = const [0, 0, 0],
}) {
  final crop = img.Image(width: w, height: h);
  final mask = Uint8List(w * h);
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      final fg = isForegroundFn(x, y);
      mask[y * w + x] = fg ? 255 : 0;
      final rgb = fg ? fgRgb : bgRgb;
      crop.setPixelRgb(x, y, rgb[0], rgb[1], rgb[2]);
    }
  }
  return SegmentedSeed(
    seedId: 'test',
    crop: crop,
    mask: mask,
    boundingBox: Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()),
    contour: const [],
    center: Offset(w / 2, h / 2),
    orientationRadians: 0,
    geometry: _dummyGeometry,
  );
}

void main() {
  const extractor = FeatureExtractor();

  test(
    "color features reflect the seed's real color, and extract() does not "
    'mutate the crop (regression: img.grayscale() must be given a clone)',
    () {
      final seed = _seedFromMask(
        w: 20,
        h: 20,
        isForegroundFn: (x, y) => true,
        fgRgb: [200, 100, 50],
      );

      final features = extractor.extract(seed);

      expect(features.color.meanR, closeTo(200, 0.5));
      expect(features.color.meanG, closeTo(100, 0.5));
      expect(features.color.meanB, closeTo(50, 0.5));
      expect(features.color.meanSaturation, greaterThan(0.3));

      // The source crop itself must be untouched by extraction.
      final p = seed.crop.getPixel(10, 10);
      expect(p.r.round(), 200);
      expect(p.g.round(), 100);
      expect(p.b.round(), 50);
    },
  );

  test('a sharp brightness split has higher edge density than a uniform region', () {
    final split = _seedFromMask(w: 20, h: 20, isForegroundFn: (x, y) => true, fgRgb: [0, 0, 0]);
    for (var y = 0; y < 20; y++) {
      for (var x = 0; x < 20; x++) {
        final v = x < 10 ? 230 : 20;
        split.crop.setPixelRgb(x, y, v, v, v);
      }
    }
    final uniform = _seedFromMask(w: 20, h: 20, isForegroundFn: (x, y) => true, fgRgb: [120, 120, 120]);

    final splitFeatures = extractor.extract(split);
    final uniformFeatures = extractor.extract(uniform);

    expect(splitFeatures.texture.edgeDensity, greaterThan(uniformFeatures.texture.edgeDensity));
    expect(uniformFeatures.texture.edgeDensity, lessThan(0.05));
  });

  test('a fully solid blob has zero holes', () {
    final seed = _seedFromMask(w: 20, h: 20, isForegroundFn: (x, y) => true, fgRgb: [100, 100, 100]);
    expect(extractor.extract(seed).damage.holeRatio, 0);
  });

  test('a solid square with an enclosed background pocket has the expected hole ratio', () {
    bool isFg(int x, int y) {
      final inHole = x >= 7 && x < 13 && y >= 7 && y < 13; // 6x6 = 36px hole
      return !inHole;
    }

    final seed = _seedFromMask(w: 20, h: 20, isForegroundFn: isFg, fgRgb: [100, 100, 100]);
    // 400 total - 36 hole = 364 foreground; ratio = 36 / 364.
    expect(extractor.extract(seed).damage.holeRatio, closeTo(36 / 364, 0.01));
  });

  test(
    'a ring open to the border is not a hole '
    '(background reachable from outside is not enclosed)',
    () {
      bool isFg(int x, int y) {
        final inHole = x >= 7 && x < 13 && y >= 7 && y < 13;
        final inSlit = x >= 7 && x < 13 && y < 7; // connects the hole to the top border
        return !(inHole || inSlit);
      }

      final seed = _seedFromMask(w: 20, h: 20, isForegroundFn: isFg, fgRgb: [100, 100, 100]);
      expect(extractor.extract(seed).damage.holeRatio, 0);
    },
  );
}

import 'dart:typed_data';
import 'dart:ui';

import 'package:image/image.dart' as img;

import '../domain/entities/seed_features.dart';

/// Processing-time output of segmentation (§12) — deliberately not a
/// domain entity, because it carries a decoded [img.Image] and a raw mask
/// buffer that feature extraction needs, neither of which belong past the
/// ml/ layer. The pipeline converts this into a domain `ProcessedSeed`
/// (PNG-encoded crop, JSON-able geometry) once analysis is complete.
class SegmentedSeed {
  final String seedId;
  final img.Image crop;

  /// 0/255 bitmap, row-major, same dimensions as [crop].
  final Uint8List mask;

  final Rect boundingBox;
  final List<Offset> contour;
  final Offset center;
  final double orientationRadians;
  final GeometryFeatures geometry;

  const SegmentedSeed({
    required this.seedId,
    required this.crop,
    required this.mask,
    required this.boundingBox,
    required this.contour,
    required this.center,
    required this.orientationRadians,
    required this.geometry,
  });

  bool isForeground(int x, int y) {
    if (x < 0 || y < 0 || x >= crop.width || y >= crop.height) return false;
    return mask[y * crop.width + x] != 0;
  }
}

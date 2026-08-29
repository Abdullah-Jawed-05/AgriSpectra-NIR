import 'dart:typed_data';
import 'dart:ui';

import 'quality_prediction.dart';
import 'seed_features.dart';

/// The standardized internal seed representation (§12 of the build spec):
/// everything the pipeline knows about one seed after segmentation,
/// feature extraction, and classification.
class ProcessedSeed {
  final String seedId;

  /// PNG-encoded crop of just this seed, for display and storage.
  final Uint8List cropPng;

  /// Binary mask (0/255), row-major, sized [maskWidth] x [maskHeight],
  /// aligned to the crop's top-left corner.
  final Uint8List mask;
  final int maskWidth;
  final int maskHeight;

  final Rect boundingBox;
  final List<Offset> contour;
  final Offset center;

  /// Radians, principal axis of the fitted ellipse; 0 = pointing along +x.
  final double orientationRadians;

  final SeedFeatures features;
  final QualityPrediction? prediction;

  const ProcessedSeed({
    required this.seedId,
    required this.cropPng,
    required this.mask,
    required this.maskWidth,
    required this.maskHeight,
    required this.boundingBox,
    required this.contour,
    required this.center,
    required this.orientationRadians,
    required this.features,
    required this.prediction,
  });

  ProcessedSeed copyWith({QualityPrediction? prediction}) => ProcessedSeed(
        seedId: seedId,
        cropPng: cropPng,
        mask: mask,
        maskWidth: maskWidth,
        maskHeight: maskHeight,
        boundingBox: boundingBox,
        contour: contour,
        center: center,
        orientationRadians: orientationRadians,
        features: features,
        prediction: prediction ?? this.prediction,
      );
}

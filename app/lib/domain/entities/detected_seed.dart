import 'dart:ui';

/// Output of the seed-detection stage (§11): a bounding box and confidence.
/// Nothing about position within the frame has been analyzed yet — that
/// happens in segmentation (§12).
class DetectedSeed {
  final String seedId;
  final Rect boundingBox;
  final double confidence;

  const DetectedSeed({
    required this.seedId,
    required this.boundingBox,
    required this.confidence,
  });

  Map<String, Object?> toJson() => {
        'seed_id': seedId,
        'bounding_box': {
          'x': boundingBox.left,
          'y': boundingBox.top,
          'width': boundingBox.width,
          'height': boundingBox.height,
        },
        'confidence': confidence,
      };
}

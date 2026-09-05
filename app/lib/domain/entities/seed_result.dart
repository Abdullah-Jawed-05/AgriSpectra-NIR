import 'dart:typed_data';

import '../value_objects/quality_class.dart';
import 'quality_prediction.dart';
import 'seed_features.dart';

/// Persisted per-seed record (§25 `SeedResult` table). This is the
/// lightweight, storable counterpart to [ProcessedSeed] — it keeps
/// PNG-encoded crop bytes (stored as a BLOB column, not a filesystem path:
/// `dart:io` file storage isn't available on the web target this project
/// also builds for, and at hackathon scale a handful of small seed-crop
/// thumbnails per scan is well within SQLite BLOB territory) and a
/// JSON-able segmentation summary instead of the full mask buffer.
class SeedResult {
  final String seedId;
  final String scanId;
  final Uint8List cropPng;

  /// bounding box + contour + center + orientation, as stored JSON.
  final Map<String, Object?> segmentation;

  final SeedFeatures visualFeatures;
  final QualityPrediction prediction;
  final double confidence;
  final List<String> anomalies;

  /// A human's confirmed-or-corrected label, from the "Make Our App
  /// Better" review flow — distinct from [prediction], which is always
  /// the model's own (possibly wrong) guess. Null until reviewed. This is
  /// the ground truth `ml/scripts/prepare_dataset.py` actually wants;
  /// [prediction] is not a substitute for it.
  final QualityClass? verifiedLabel;
  final DateTime? verifiedAt;

  const SeedResult({
    required this.seedId,
    required this.scanId,
    required this.cropPng,
    required this.segmentation,
    required this.visualFeatures,
    required this.prediction,
    required this.confidence,
    required this.anomalies,
    this.verifiedLabel,
    this.verifiedAt,
  });

  SeedResult copyWith({QualityClass? verifiedLabel, DateTime? verifiedAt}) => SeedResult(
        seedId: seedId,
        scanId: scanId,
        cropPng: cropPng,
        segmentation: segmentation,
        visualFeatures: visualFeatures,
        prediction: prediction,
        confidence: confidence,
        anomalies: anomalies,
        verifiedLabel: verifiedLabel ?? this.verifiedLabel,
        verifiedAt: verifiedAt ?? this.verifiedAt,
      );
}

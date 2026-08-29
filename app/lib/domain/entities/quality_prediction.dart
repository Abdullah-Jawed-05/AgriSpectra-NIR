import '../value_objects/quality_class.dart';

/// One signed piece of evidence behind a prediction, e.g. "+ Normal color
/// distribution" or "- Minor surface discoloration" (§23 explainability).
class EvidenceFactor {
  final String description;
  final bool supportsGoodQuality;
  final double weight;

  const EvidenceFactor({
    required this.description,
    required this.supportsGoodQuality,
    required this.weight,
  });
}

/// A single-sensor (visual or NIR) prediction. The fusion layer combines
/// two of these into a [FusionResult] — see domain/entities/fusion_result.dart.
class QualityPrediction {
  final QualityClass qualityClass;

  /// 0..100 user-facing score.
  final double score;

  /// 0..1 model confidence.
  final double confidence;

  final List<EvidenceFactor> evidence;
  final List<String> anomalies;
  final String modelVersion;

  const QualityPrediction({
    required this.qualityClass,
    required this.score,
    required this.confidence,
    required this.evidence,
    required this.anomalies,
    required this.modelVersion,
  });

  Map<String, Object?> toJson() => {
        'quality_class': qualityClass.storageKey,
        'score': score,
        'confidence': confidence,
        'anomalies': anomalies,
        'model_version': modelVersion,
      };
}

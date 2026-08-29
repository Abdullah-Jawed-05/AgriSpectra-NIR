enum AssessmentMode { cameraOnly, nirOnly, multimodal }

/// The unified per-batch result object (§37). Mirrors the JSON shape from
/// the build spec exactly so a future API response can reuse this model.
class FusionResult {
  final String assessmentId;
  final AssessmentMode mode;
  final String crop;

  final double visualScore;
  final double? nirScore;
  final double combinedScore;
  final double confidence;

  final int seedCount;
  final int anomalies;

  final Map<String, String> modelVersions;

  const FusionResult({
    required this.assessmentId,
    required this.mode,
    required this.crop,
    required this.visualScore,
    required this.nirScore,
    required this.combinedScore,
    required this.confidence,
    required this.seedCount,
    required this.anomalies,
    required this.modelVersions,
  });

  Map<String, Object?> toJson() => {
        'assessment_id': assessmentId,
        'mode': mode.name,
        'crop': crop,
        'visual_score': visualScore,
        'nir_score': nirScore,
        'combined_score': combinedScore,
        'confidence': confidence,
        'seed_count': seedCount,
        'anomalies': anomalies,
        'model_versions': modelVersions,
      };
}

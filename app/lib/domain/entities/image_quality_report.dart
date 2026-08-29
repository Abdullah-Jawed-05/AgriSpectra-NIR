/// Output of the pre-inference image quality gate (§10 of the build spec).
/// If [usable] is false, the pipeline must stop before detection/inference
/// and surface [warnings] to the user instead.
class ImageQualityReport {
  final bool usable;
  final double qualityScore;
  final double blurScore;
  final double exposureScore;
  final double glareScore;
  final double backgroundScore;
  final List<String> warnings;

  const ImageQualityReport({
    required this.usable,
    required this.qualityScore,
    required this.blurScore,
    required this.exposureScore,
    required this.glareScore,
    required this.backgroundScore,
    required this.warnings,
  });

  Map<String, Object?> toJson() => {
        'usable': usable,
        'quality_score': qualityScore,
        'blur_score': blurScore,
        'exposure_score': exposureScore,
        'glare_score': glareScore,
        'background_score': backgroundScore,
        'warnings': warnings,
      };
}

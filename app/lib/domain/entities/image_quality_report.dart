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

  /// How free of background texture the frame is: 1.0 = clean plain
  /// backdrop, 0.0 = a woven/printed/grained surface that fragments
  /// segmentation. Folded into [backgroundScore]; kept separately so the
  /// "why was this rejected" copy can point at the real cause.
  final double textureScore;
  final List<String> warnings;

  const ImageQualityReport({
    required this.usable,
    required this.qualityScore,
    required this.blurScore,
    required this.exposureScore,
    required this.glareScore,
    required this.backgroundScore,
    this.textureScore = 1.0,
    required this.warnings,
  });

  Map<String, Object?> toJson() => {
        'usable': usable,
        'quality_score': qualityScore,
        'blur_score': blurScore,
        'exposure_score': exposureScore,
        'glare_score': glareScore,
        'background_score': backgroundScore,
        'texture_score': textureScore,
        'warnings': warnings,
      };
}

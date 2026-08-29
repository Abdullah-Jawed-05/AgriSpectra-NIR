/// User-facing confidence bucket. The numeric confidence (0..1) always
/// exists underneath — this is only how it is *displayed* to
/// non-technical users (§24 of the build spec: "Confidence: High", not
/// "Model confidence = 0.87").
enum ConfidenceLevel { high, medium, low }

extension ConfidenceLevelX on ConfidenceLevel {
  String get label => switch (this) {
        ConfidenceLevel.high => 'High',
        ConfidenceLevel.medium => 'Medium',
        ConfidenceLevel.low => 'Low',
      };
}

ConfidenceLevel confidenceLevelFrom(double confidence) {
  if (confidence >= 0.85) return ConfidenceLevel.high;
  if (confidence >= 0.6) return ConfidenceLevel.medium;
  return ConfidenceLevel.low;
}

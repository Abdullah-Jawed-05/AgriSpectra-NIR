import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../domain/value_objects/confidence_level.dart';
import '../../domain/value_objects/quality_class.dart';

/// "Confidence: High" rather than a raw number (§24: non-technical users
/// see the bucket; the underlying float is available for advanced/expandable
/// views).
class ConfidenceChip extends StatelessWidget {
  const ConfidenceChip({super.key, required this.confidence});
  final double confidence;

  @override
  Widget build(BuildContext context) {
    final level = confidenceLevelFrom(confidence);
    final color = switch (level) {
      ConfidenceLevel.high => AppColors.good,
      ConfidenceLevel.medium => AppColors.moderate,
      ConfidenceLevel.low => AppColors.low,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppRadius.sm),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.circle, size: 8, color: color),
          const SizedBox(width: 6),
          Text(
            'Confidence: ${level.label}',
            style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: color),
          ),
        ],
      ),
    );
  }
}

class QualityClassBadge extends StatelessWidget {
  const QualityClassBadge({super.key, required this.qualityClass});
  final QualityClass qualityClass;

  Color get _color => switch (qualityClass) {
        QualityClass.good => AppColors.good,
        QualityClass.damaged ||
        QualityClass.discolored ||
        QualityClass.shriveled ||
        QualityClass.shellFree =>
          AppColors.moderate,
        QualityClass.broken ||
        QualityClass.moldSuspect ||
        QualityClass.insectDamaged =>
          AppColors.low,
        QualityClass.unknown => AppColors.inkFaint,
      };

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: _color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppRadius.sm),
      ),
      child: Text(
        qualityClass.label,
        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: _color),
      ),
    );
  }
}

/// Large 0..100 score, color-coded by band. Used on the result screen and
/// seed cards.
class ScoreDisplay extends StatelessWidget {
  const ScoreDisplay({super.key, required this.score, this.size = 40});
  final double score;
  final double size;

  Color get _color {
    if (score >= 75) return AppColors.good;
    if (score >= 50) return AppColors.moderate;
    return AppColors.low;
  }

  @override
  Widget build(BuildContext context) {
    return RichText(
      text: TextSpan(
        children: [
          TextSpan(
            text: score.round().toString(),
            style: TextStyle(fontSize: size, fontWeight: FontWeight.w800, color: _color, height: 1),
          ),
          TextSpan(
            text: ' / 100',
            style: TextStyle(fontSize: size * 0.35, fontWeight: FontWeight.w600, color: AppColors.inkFaint),
          ),
        ],
      ),
    );
  }
}

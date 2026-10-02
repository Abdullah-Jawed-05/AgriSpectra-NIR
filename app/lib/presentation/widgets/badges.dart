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

/// Shared colour for a quality class — used by the badge, the result
/// screen's class summary, and the per-seed card accent so they read as
/// one system. Impurities is foreign matter, not a quality grade, so it's
/// neutral rather than on the good/moderate/low scale.
Color qualityClassColor(QualityClass qualityClass) => switch (qualityClass) {
      QualityClass.good => AppColors.good,
      QualityClass.damaged || QualityClass.shriveled => AppColors.moderate,
      QualityClass.broken => AppColors.low,
      QualityClass.impurities || QualityClass.unknown => AppColors.inkFaint,
    };

/// User-facing label for a class in the result view — `impurities` reads
/// better as "Non-seed" to a grower.
String qualityClassResultLabel(QualityClass qualityClass) =>
    qualityClass == QualityClass.impurities ? 'Non-seed' : qualityClass.label;

class QualityClassBadge extends StatelessWidget {
  const QualityClassBadge({super.key, required this.qualityClass});
  final QualityClass qualityClass;

  Color get _color => qualityClassColor(qualityClass);

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
///
/// The band is never color-only: a glyph (check / caution / low) carries
/// the same signal, so a grid of seed cards is scannable without relying
/// on hue discrimination, and the band reads before the number is read.
class ScoreDisplay extends StatelessWidget {
  const ScoreDisplay({super.key, required this.score, this.size = 40, this.showIcon = true});
  final double score;
  final double size;
  final bool showIcon;

  Color get _color {
    if (score >= 75) return AppColors.good;
    if (score >= 50) return AppColors.moderate;
    return AppColors.low;
  }

  IconData get _icon {
    if (score >= 75) return Icons.check_circle_rounded;
    if (score >= 50) return Icons.error_rounded;
    return Icons.cancel_rounded;
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        if (showIcon) ...[
          Icon(_icon, color: _color, size: size * 0.42),
          SizedBox(width: size * 0.12),
        ],
        RichText(
          text: TextSpan(
            children: [
              TextSpan(
                text: score.round().toString(),
                style: TextStyle(
                  fontSize: size,
                  fontWeight: FontWeight.w800,
                  color: _color,
                  height: 1,
                  letterSpacing: -size * 0.02,
                ),
              ),
              TextSpan(
                text: ' / 100',
                style: TextStyle(fontSize: size * 0.35, fontWeight: FontWeight.w600, color: AppColors.inkFaint),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../domain/entities/seed_result.dart';
import 'badges.dart';

/// One seed as a card in the batch grid (§22). A colour bar keyed to the
/// class runs down the left edge so a block of good (or non-seed) cards
/// reads at a glance.
class SeedCard extends StatelessWidget {
  const SeedCard({super.key, required this.result, required this.index, required this.onTap});

  final SeedResult result;
  final int index;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final accent = qualityClassColor(result.prediction.qualityClass);
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AspectRatio(
              aspectRatio: 1.3,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Container(
                    color: AppColors.surfaceAlt,
                    child: Image.memory(result.cropPng, fit: BoxFit.cover),
                  ),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Container(width: 5, color: accent),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(AppSpacing.sm),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Seed #${index + 1}', style: Theme.of(context).textTheme.labelLarge),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      ScoreDisplay(score: result.prediction.score, size: 18),
                    ],
                  ),
                  const SizedBox(height: 6),
                  QualityClassBadge(qualityClass: result.prediction.qualityClass),
                  if (result.anomalies.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        const Icon(Icons.warning_amber_rounded, size: 12, color: AppColors.moderate),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            '${result.anomalies.length} flagged',
                            style: const TextStyle(fontSize: 10.5, color: AppColors.moderate),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

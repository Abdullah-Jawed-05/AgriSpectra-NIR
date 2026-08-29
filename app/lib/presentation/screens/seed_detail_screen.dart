import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme.dart';
import '../../domain/entities/seed_result.dart';
import '../widgets/badges.dart';
import 'result_screen.dart';

class SeedDetailScreen extends ConsumerWidget {
  const SeedDetailScreen({super.key, required this.scanId, required this.seedId});
  final String scanId;
  final String seedId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scanAsync = ref.watch(scanByIdProvider(scanId));

    return Scaffold(
      appBar: AppBar(title: const Text('Seed Detail')),
      body: scanAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, st) => Center(child: Text('Failed to load: $e')),
        data: (scan) {
          SeedResult? seed;
          if (scan != null) {
            for (final r in scan.results) {
              if (r.seedId == seedId) {
                seed = r;
                break;
              }
            }
          }
          if (seed == null) return const Center(child: Text('Seed not found.'));
          return _SeedDetailBody(seed: seed);
        },
      ),
    );
  }
}

class _SeedDetailBody extends StatelessWidget {
  const _SeedDetailBody({required this.seed});
  final SeedResult seed;

  @override
  Widget build(BuildContext context) {
    final prediction = seed.prediction;
    final f = seed.visualFeatures;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(AppRadius.lg),
            child: AspectRatio(
              aspectRatio: 1.4,
              child: Container(
                color: AppColors.surfaceAlt,
                child: Image.memory(seed.cropPng, fit: BoxFit.contain),
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          Row(
            children: [
              ScoreDisplay(score: prediction.score),
              const SizedBox(width: AppSpacing.md),
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    QualityClassBadge(qualityClass: prediction.qualityClass),
                    const SizedBox(height: 6),
                    ConfidenceChip(confidence: prediction.confidence),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xl),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Why this score?', style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: AppSpacing.md),
                  ...prediction.evidence.map((e) => Padding(
                        padding: const EdgeInsets.symmetric(vertical: 3),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              e.supportsGoodQuality ? '+' : '−',
                              style: TextStyle(
                                fontWeight: FontWeight.w800,
                                color: e.supportsGoodQuality ? AppColors.good : AppColors.low,
                              ),
                            ),
                            const SizedBox(width: AppSpacing.sm),
                            Expanded(
                              child: Text(e.description, style: Theme.of(context).textTheme.bodyLarge),
                            ),
                          ],
                        ),
                      )),
                  if (prediction.anomalies.isNotEmpty) ...[
                    const Divider(height: AppSpacing.xl),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: prediction.anomalies
                          .map((a) => Chip(
                                label: Text(a.replaceAll('_', ' ')),
                                visualDensity: VisualDensity.compact,
                              ))
                          .toList(),
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Measured features', style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: AppSpacing.md),
                  _FeatureRow('Aspect ratio', f.geometry.aspectRatio.toStringAsFixed(2)),
                  _FeatureRow('Circularity', f.geometry.circularity.toStringAsFixed(2)),
                  _FeatureRow('Convexity', f.geometry.convexity.toStringAsFixed(2)),
                  _FeatureRow('Discoloration ratio', f.color.discolorationRatio.toStringAsFixed(2)),
                  _FeatureRow('Edge density', f.texture.edgeDensity.toStringAsFixed(2)),
                  _FeatureRow('Dark region ratio', f.damage.darkRegionRatio.toStringAsFixed(2)),
                ],
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.xl),
          Text(
            'These are visual indicators derived from the captured image — they describe '
            'observable appearance, not internal viability.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ],
      ),
    );
  }
}

class _FeatureRow extends StatelessWidget {
  const _FeatureRow(this.label, this.value);
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: Theme.of(context).textTheme.bodyMedium),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
        ],
      ),
    );
  }
}

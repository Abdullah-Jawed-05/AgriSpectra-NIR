import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/providers.dart';
import '../../core/theme/app_theme.dart';
import '../../domain/entities/fusion_result.dart';
import '../../domain/entities/scan.dart';
import '../../domain/entities/spectral_measurement.dart';
import '../widgets/badges.dart';
import '../widgets/batch_histogram_chart.dart';
import '../widgets/seed_card.dart';
import '../widgets/spectral_graph.dart';

final scanByIdProvider = FutureProvider.family<Scan?, String>((ref, scanId) {
  return ref.watch(scanRepositoryProvider).byId(scanId);
});

final spectralByScanIdProvider = FutureProvider.family<SpectralMeasurement?, String>((ref, scanId) {
  return ref.watch(scanRepositoryProvider).spectralByScanId(scanId);
});

class ResultScreen extends ConsumerWidget {
  const ResultScreen({super.key, required this.scanId});
  final String scanId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scanAsync = ref.watch(scanByIdProvider(scanId));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Batch Result'),
        actions: [
          IconButton(
            tooltip: 'Home',
            onPressed: () => context.go('/'),
            icon: const Icon(Icons.home_outlined),
          ),
        ],
      ),
      body: scanAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, st) => Center(child: Text('Failed to load scan: $e')),
        data: (scan) {
          if (scan == null) {
            return const Center(child: Text('Scan not found.'));
          }
          return _ResultBody(scan: scan);
        },
      ),
    );
  }
}

class _ResultBody extends ConsumerWidget {
  const _ResultBody({required this.scan});
  final Scan scan;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final spectralAsync = ref.watch(spectralByScanIdProvider(scan.scanId));

    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(scan.crop.toUpperCase(), style: Theme.of(context).textTheme.labelSmall),
          const SizedBox(height: 4),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              ScoreDisplay(score: scan.batchScore),
              const SizedBox(width: AppSpacing.md),
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: ConfidenceChip(confidence: scan.confidence),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            '${scan.batchStatistics.seedsAccepted} seeds analyzed · ${_modeLabel(scan.fusionResult.mode)}',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: AppSpacing.lg),
          _BreakdownCard(scan: scan),
          const SizedBox(height: AppSpacing.lg),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Score distribution', style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: AppSpacing.md),
                  SizedBox(height: 140, child: BatchHistogramChart(buckets: scan.batchStatistics.scoreHistogram)),
                ],
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          spectralAsync.maybeWhen(
            data: (spectral) => spectral == null
                ? const SizedBox.shrink()
                : Padding(
                    padding: const EdgeInsets.only(bottom: AppSpacing.lg),
                    child: Card(
                      child: Padding(
                        padding: const EdgeInsets.all(AppSpacing.lg),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Text('NIR spectral reading', style: Theme.of(context).textTheme.titleMedium),
                                const Spacer(),
                                if (spectral.isSimulated)
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                    decoration: BoxDecoration(
                                      color: AppColors.nirMuted,
                                      borderRadius: BorderRadius.circular(AppRadius.sm),
                                    ),
                                    child: const Text(
                                      'SIMULATED',
                                      style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: AppColors.nir),
                                    ),
                                  ),
                              ],
                            ),
                            const SizedBox(height: AppSpacing.md),
                            SizedBox(height: 160, child: SpectralGraph(measurement: spectral)),
                          ],
                        ),
                      ),
                    ),
                  ),
            orElse: () => const SizedBox.shrink(),
          ),
          Text('Individual seeds', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: AppSpacing.md),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: scan.results.length,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              mainAxisSpacing: AppSpacing.sm,
              crossAxisSpacing: AppSpacing.sm,
              childAspectRatio: 0.78,
            ),
            itemBuilder: (context, i) {
              final result = scan.results[i];
              return SeedCard(
                result: result,
                index: i,
                onTap: () => context.push('/scan/result/${scan.scanId}/seed/${result.seedId}'),
              );
            },
          ),
          const SizedBox(height: AppSpacing.xxl),
          Text(
            'AgriSpectra provides preliminary non-destructive seed-quality screening and is '
            'not a replacement for certified laboratory germination or seed-quality testing.',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontStyle: FontStyle.italic),
          ),
          const SizedBox(height: AppSpacing.xl),
        ],
      ),
    );
  }

  String _modeLabel(AssessmentMode mode) => switch (mode) {
        AssessmentMode.cameraOnly => 'Camera-only assessment',
        AssessmentMode.nirOnly => 'NIR-only assessment',
        AssessmentMode.multimodal => 'Multimodal assessment',
      };
}

class _BreakdownCard extends StatelessWidget {
  const _BreakdownCard({required this.scan});
  final Scan scan;

  @override
  Widget build(BuildContext context) {
    final stats = scan.batchStatistics;
    final fusion = scan.fusionResult;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _Row(label: 'Visual quality', value: fusion.visualScore.round().toString()),
            if (fusion.nirScore != null)
              _Row(label: 'NIR enhancement', value: fusion.nirScore!.round().toString())
            else
              _Row(label: 'NIR enhancement', value: 'unavailable', muted: true),
            _Row(label: 'Batch uniformity', value: '${(stats.uniformity * 100).round()}%'),
            _Row(label: 'Visible anomalies', value: '${stats.anomalyCount} seeds'),
            _Row(
              label: 'Batch purity',
              value: '${(stats.purityRatio * 100).round()}%'
                  '${stats.impurityCount > 0 ? ' · ${stats.impurityCount} non-seed' : ''}',
              muted: stats.impurityCount == 0,
            ),
            _Row(label: 'Rejected (unusable)', value: '${stats.seedsRejected}'),
            if (!scan.nirAvailable) ...[
              const Divider(height: AppSpacing.xl),
              Row(
                children: [
                  const Icon(Icons.info_outline, size: 16, color: AppColors.inkFaint),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text(
                      'Connect an AgriSpectra NIR device to enhance this assessment.',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.label, required this.value, this.muted = false});
  final String label;
  final String value;
  final bool muted;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: Theme.of(context).textTheme.bodyMedium),
          Text(
            value,
            style: TextStyle(
              fontSize: 13.5,
              fontWeight: FontWeight.w700,
              color: muted ? AppColors.inkFaint : AppColors.ink,
            ),
          ),
        ],
      ),
    );
  }
}

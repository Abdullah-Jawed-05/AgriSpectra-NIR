import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:printing/printing.dart';

import '../../core/providers.dart';
import '../../core/theme/app_theme.dart';
import '../../domain/entities/fusion_result.dart';
import '../../domain/entities/scan.dart';
import '../../domain/entities/seed_result.dart';
import '../../domain/entities/spectral_measurement.dart';
import '../../domain/value_objects/quality_class.dart';
import '../../export/scan_report_pdf.dart';
import '../widgets/badges.dart';
import '../widgets/batch_histogram_chart.dart';
import '../widgets/error_state.dart';
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
        error: (e, st) => ErrorState(
          title: "Couldn't load this scan.",
          detail: e,
          onRetry: () => ref.invalidate(scanByIdProvider(scanId)),
        ),
        data: (scan) {
          if (scan == null) {
            return const ErrorState(
              icon: Icons.search_off,
              title: 'Scan not found.',
              detail: 'It may have been deleted.',
            );
          }
          return _ResultBody(scan: scan);
        },
      ),
    );
  }
}

class _ResultBody extends ConsumerStatefulWidget {
  const _ResultBody({required this.scan});
  final Scan scan;

  @override
  ConsumerState<_ResultBody> createState() => _ResultBodyState();
}

class _ResultBodyState extends ConsumerState<_ResultBody> {
  final _scrollController = ScrollController();
  // A ValueNotifier rather than setState for the whole body: this flips
  // at most once per scroll direction change, and only the condensed
  // header itself needs to rebuild when it does.
  final _showCondensedHeader = ValueNotifier<bool>(false);

  /// Past this offset the hero score block has scrolled out of view, so
  /// the condensed header takes over — keeps the score/confidence visible
  /// while reviewing a long batch instead of losing context on scroll.
  static const _condensedThreshold = 160.0;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  void _onScroll() {
    final shouldShow = _scrollController.offset > _condensedThreshold;
    if (shouldShow != _showCondensedHeader.value) {
      _showCondensedHeader.value = shouldShow;
    }
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    _showCondensedHeader.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scan = widget.scan;
    final spectralAsync = ref.watch(spectralByScanIdProvider(scan.scanId));

    return Stack(
      children: [
        SingleChildScrollView(
          controller: _scrollController,
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(scan.crop.toUpperCase(), style: Theme.of(context).textTheme.labelSmall),
              const SizedBox(height: 6),
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  ScoreDisplay(score: scan.batchScore, size: 56),
                  const SizedBox(width: AppSpacing.md),
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: ConfidenceChip(confidence: scan.confidence),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                '${scan.batchStatistics.seedsAccepted} seeds analyzed · ${_modeLabel(scan.fusionResult.mode)}',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: AppSpacing.md),
              _ClassSummaryStrip(seeds: scan.results),
              const SizedBox(height: AppSpacing.md),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.picture_as_pdf_outlined, size: 18),
                  label: const Text('Save Report'),
                  onPressed: () => _saveReport(context, scan, spectralAsync.value),
                ),
              ),
              // A clearly larger gap ahead of the breakdown — spacing, not
              // another bordered box, is what signals "new section" here.
              const SizedBox(height: AppSpacing.xxl),
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
              const SizedBox(height: AppSpacing.sm),
              Text('Individual seeds', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: AppSpacing.md),
              _SeedsByClass(scan: scan),
              const SizedBox(height: AppSpacing.xxl),
              Text(
                'AgriSpectra provides preliminary non-destructive seed-quality screening and is '
                'not a replacement for certified laboratory germination or seed-quality testing.',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontStyle: FontStyle.italic),
              ),
              const SizedBox(height: AppSpacing.xl),
            ],
          ),
        ),
        ValueListenableBuilder<bool>(
          valueListenable: _showCondensedHeader,
          builder: (context, show, child) => IgnorePointer(
            ignoring: !show,
            child: AnimatedOpacity(
              opacity: show ? 1 : 0,
              duration: const Duration(milliseconds: 150),
              child: child,
            ),
          ),
          child: _CondensedScoreHeader(scan: scan),
        ),
      ],
    );
  }

  /// Generated on demand only, when the user taps this button — never
  /// automatically after a scan (§40 of the build spec covers report
  /// *content*, not when it's produced; producing a PDF nobody asked for
  /// on every scan would just be wasted work).
  Future<void> _saveReport(BuildContext context, Scan scan, SpectralMeasurement? spectral) async {
    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(const SnackBar(content: Text('Preparing report…'), duration: Duration(seconds: 2)));
    try {
      final bytes = await ScanReportPdf.build(scan: scan, spectral: spectral);
      await Printing.sharePdf(bytes: bytes, filename: 'agrispectra_${scan.scanId}.pdf');
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Could not generate report: $e')));
    }
  }

  String _modeLabel(AssessmentMode mode) => switch (mode) {
        AssessmentMode.cameraOnly => 'Camera-only assessment',
        AssessmentMode.nirOnly => 'NIR-only assessment',
        AssessmentMode.multimodal => 'Multimodal assessment',
      };
}

/// Slim pinned-feeling summary (score + confidence) that fades in once the
/// hero block has scrolled out of view, so the number every other stat on
/// this screen explains stays visible during a long seed-by-seed review.
class _CondensedScoreHeader extends StatelessWidget {
  const _CondensedScoreHeader({required this.scan});
  final Scan scan;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Theme.of(context).scaffoldBackgroundColor,
      child: Container(
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: Theme.of(context).dividerColor)),
        ),
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: AppSpacing.sm),
        child: Row(
          children: [
            Expanded(
              child: Text(
                scan.crop.toUpperCase(),
                style: Theme.of(context).textTheme.labelSmall,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            ScoreDisplay(score: scan.batchScore, size: 20),
            const SizedBox(width: AppSpacing.sm),
            ConfidenceChip(confidence: scan.confidence),
          ],
        ),
      ),
    );
  }
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
            _Row(
              label: 'Expected germination',
              value: stats.expectedGermination == null
                  ? 'unavailable'
                  : '${(stats.expectedGermination! * 100).round()}%',
              muted: stats.expectedGermination == null,
            ),
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

/// The order classes are shown in the result view — good first (the
/// reassuring number), then problems, then non-seed.
const _classDisplayOrder = [
  QualityClass.good,
  QualityClass.damaged,
  QualityClass.shriveled,
  QualityClass.broken,
  QualityClass.impurities,
  QualityClass.unknown,
];

Map<QualityClass, List<SeedResult>> _groupByClass(List<SeedResult> seeds) {
  final map = <QualityClass, List<SeedResult>>{};
  for (final s in seeds) {
    (map[s.prediction.qualityClass] ??= []).add(s);
  }
  return map;
}

/// Prominent, colour-coded counts right under the score — the user asked
/// for good seeds and impurities to read *vividly*, not be buried in a
/// grid.
class _ClassSummaryStrip extends StatelessWidget {
  const _ClassSummaryStrip({required this.seeds});
  final List<SeedResult> seeds;

  @override
  Widget build(BuildContext context) {
    if (seeds.isEmpty) return const SizedBox.shrink();
    final groups = _groupByClass(seeds);
    final present = _classDisplayOrder.where((c) => (groups[c]?.isNotEmpty ?? false)).toList();

    return Wrap(
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.sm,
      children: [
        for (final c in present)
          _CountChip(
            color: qualityClassColor(c),
            count: groups[c]!.length,
            label: qualityClassResultLabel(c),
          ),
      ],
    );
  }
}

class _CountChip extends StatelessWidget {
  const _CountChip({required this.color, required this.count, required this.label});
  final Color color;
  final int count;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppRadius.sm),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('$count',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: color)),
          const SizedBox(width: 6),
          Text(label,
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: color)),
        ],
      ),
    );
  }
}

/// The per-seed grid, split into a labelled section per class so good
/// seeds and non-seed objects are each their own clearly-headed block.
class _SeedsByClass extends StatelessWidget {
  const _SeedsByClass({required this.scan});
  final Scan scan;

  @override
  Widget build(BuildContext context) {
    final groups = _groupByClass(scan.results);
    final indexOf = {for (var i = 0; i < scan.results.length; i++) scan.results[i].seedId: i};

    return LayoutBuilder(
      builder: (context, constraints) {
        // Target a ~170px card so the grid gains columns on a tablet
        // instead of two cards stretched across the extra width; capped
        // at 5 so cards never get too small to read the score at a glance.
        final crossAxisCount = (constraints.maxWidth / 170).floor().clamp(2, 5);

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final c in _classDisplayOrder)
              if (groups[c]?.isNotEmpty ?? false) ...[
                Padding(
                  padding: const EdgeInsets.only(top: AppSpacing.md, bottom: AppSpacing.sm),
                  child: Row(
                    children: [
                      Container(width: 4, height: 16, color: qualityClassColor(c)),
                      const SizedBox(width: AppSpacing.sm),
                      Text(
                        '${qualityClassResultLabel(c)} · ${groups[c]!.length}',
                        style: Theme.of(context).textTheme.labelLarge?.copyWith(
                              color: qualityClassColor(c),
                              fontWeight: FontWeight.w700,
                            ),
                      ),
                    ],
                  ),
                ),
                GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: groups[c]!.length,
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: crossAxisCount,
                    mainAxisSpacing: AppSpacing.sm,
                    crossAxisSpacing: AppSpacing.sm,
                    childAspectRatio: 0.78,
                  ),
                  itemBuilder: (context, i) {
                    final result = groups[c]![i];
                    return SeedCard(
                      result: result,
                      index: indexOf[result.seedId] ?? 0,
                      onTap: () => context.push('/scan/result/${scan.scanId}/seed/${result.seedId}'),
                    );
                  },
                ),
              ],
          ],
        );
      },
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

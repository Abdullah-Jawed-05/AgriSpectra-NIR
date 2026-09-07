import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/constants/app_constants.dart';
import '../../core/providers.dart';
import '../../core/theme/app_theme.dart';
import '../../database/daos/scan_dao.dart';
import '../widgets/badges.dart';

final scanHistoryProvider = FutureProvider.autoDispose.family<List<ScanSummary>, String?>((ref, crop) {
  return ref.watch(scanRepositoryProvider).history(cropFilter: crop);
});

class HistoryScreen extends ConsumerStatefulWidget {
  const HistoryScreen({super.key});

  @override
  ConsumerState<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends ConsumerState<HistoryScreen> {
  String? _cropFilter;

  @override
  Widget build(BuildContext context) {
    final historyAsync = ref.watch(scanHistoryProvider(_cropFilter));
    final dateFormat = DateFormat('MMM d, yyyy · h:mm a');

    return Scaffold(
      appBar: AppBar(title: const Text('Scan History')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: AppSpacing.sm),
            child: SizedBox(
              height: 36,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [
                  _FilterChip(label: 'All', selected: _cropFilter == null, onTap: () => setState(() => _cropFilter = null)),
                  for (final c in Crop.values)
                    Padding(
                      padding: const EdgeInsets.only(left: AppSpacing.sm),
                      child: _FilterChip(
                        label: c.label,
                        selected: _cropFilter == c.label,
                        onTap: () => setState(() => _cropFilter = c.label),
                      ),
                    ),
                ],
              ),
            ),
          ),
          Expanded(
            child: historyAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, st) => _HistoryError(
                error: e,
                onRetry: () => ref.invalidate(scanHistoryProvider(_cropFilter)),
              ),
              data: (scans) {
                if (scans.isEmpty) {
                  return Center(
                    child: Text('No scans yet.', style: Theme.of(context).textTheme.bodyMedium),
                  );
                }
                return ListView.separated(
                  padding: const EdgeInsets.all(AppSpacing.lg),
                  itemCount: scans.length,
                  separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.sm),
                  itemBuilder: (context, i) {
                    final scan = scans[i];
                    return Card(
                      child: ListTile(
                        onTap: () => context.push('/scan/result/${scan.scanId}'),
                        title: Row(
                          children: [
                            Text(scan.crop, style: Theme.of(context).textTheme.titleMedium),
                            const SizedBox(width: AppSpacing.sm),
                            Text('${scan.numberOfSeeds} seeds', style: Theme.of(context).textTheme.bodyMedium),
                          ],
                        ),
                        subtitle: Text(dateFormat.format(scan.timestamp)),
                        trailing: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            ScoreDisplay(score: scan.batchScore, size: 18),
                            if (scan.nirAvailable)
                              const Padding(
                                padding: EdgeInsets.only(top: 2),
                                child: Text(
                                  'Multimodal',
                                  style: TextStyle(fontSize: 10, color: AppColors.nir, fontWeight: FontWeight.w600),
                                ),
                              ),
                          ],
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _HistoryError extends StatelessWidget {
  const _HistoryError({required this.error, required this.onRetry});
  final Object error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: constraints.maxHeight),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Icon(Icons.history_toggle_off, size: 40, color: AppColors.inkFaint),
              const SizedBox(height: AppSpacing.md),
              Text(
                "Couldn't load scan history.",
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                '$error',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.inkFaint),
              ),
              const SizedBox(height: AppSpacing.lg),
              Align(
                alignment: Alignment.center,
                child: OutlinedButton.icon(
                  onPressed: onRetry,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Try again'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({required this.label, required this.selected, required this.onTap});
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ChoiceChip(label: Text(label), selected: selected, onSelected: (_) => onTap());
  }
}

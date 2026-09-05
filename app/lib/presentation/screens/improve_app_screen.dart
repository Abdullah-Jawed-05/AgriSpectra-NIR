import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/providers.dart';
import '../../core/theme/app_theme.dart';
import '../../database/daos/scan_dao.dart';
import '../../domain/value_objects/quality_class.dart';
import '../../export/training_data_export.dart';

/// "Make Our App Better" (§44 of the build spec — a dataset-collection
/// mode, shaped around how the app is actually used): every seed the app
/// has ever scanned already sits in the database with the model's own
/// guess attached. Capturing an image never asks the user anything — that
/// would defeat normal scanning — so instead every seed starts
/// unverified, and this screen is where anyone using the app can, later
/// and at their own pace, confirm or correct what the model guessed.
/// Confirmed labels are real ground truth; [SeedResult.prediction] never
/// was.
class ImproveAppScreen extends ConsumerStatefulWidget {
  const ImproveAppScreen({super.key});

  @override
  ConsumerState<ImproveAppScreen> createState() => _ImproveAppScreenState();
}

class _ImproveAppScreenState extends ConsumerState<ImproveAppScreen> {
  List<SeedReviewItem>? _queue;
  int _index = 0;
  int _reviewedCount = 0;
  bool _exporting = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final items = await ref.read(scanRepositoryProvider).unverifiedSeeds();
    if (!mounted) return;
    setState(() {
      _queue = items;
      _index = 0;
    });
  }

  Future<void> _verify(QualityClass label) async {
    final queue = _queue;
    if (queue == null || _index >= queue.length) return;
    final item = queue[_index];
    await ref.read(scanRepositoryProvider).verifySeed(item.seedId, label);
    if (!mounted) return;
    setState(() {
      _index++;
      _reviewedCount++;
    });
  }

  void _skip() {
    if (_queue == null || _index >= _queue!.length) return;
    setState(() => _index++);
  }

  Future<void> _export() async {
    setState(() => _exporting = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final verified = await ref.read(scanRepositoryProvider).verifiedSeeds();
      if (verified.isEmpty) {
        messenger.showSnackBar(const SnackBar(content: Text('No verified seeds yet — review some first.')));
        return;
      }
      final zip = await TrainingDataExport.buildZip(verified);
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(zip.path)],
          text: 'AgriSpectra verified training data (${verified.length} seeds)',
        ),
      );
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Export failed: $e')));
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final queue = _queue;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Make Our App Better'),
        actions: [
          IconButton(
            tooltip: 'Export verified data',
            onPressed: _exporting ? null : _export,
            icon: _exporting
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.ios_share_outlined),
          ),
        ],
      ),
      body: SafeArea(
        child: queue == null
            ? const Center(child: CircularProgressIndicator())
            : (_index >= queue.length ? _EmptyState(reviewedCount: _reviewedCount) : _reviewBody(queue[_index], queue.length)),
      ),
    );
  }

  Widget _reviewBody(SeedReviewItem item, int total) {
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Seed ${_index + 1} of $total',
                style: Theme.of(context).textTheme.labelSmall,
              ),
              Text(
                'Captured ${_relativeDate(item.scanTimestamp)}',
                style: Theme.of(context).textTheme.labelSmall,
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(AppRadius.lg),
              child: Container(
                width: double.infinity,
                color: AppColors.surfaceAlt,
                child: Image.memory(item.cropPng, fit: BoxFit.contain),
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: AppColors.accentMuted,
              borderRadius: BorderRadius.circular(AppRadius.md),
            ),
            child: Text(
              'Our app thinks: ${item.predictedLabel.label} (${item.predictedScore.round()}/100)',
              style: const TextStyle(fontWeight: FontWeight.w600, color: AppColors.accent, fontSize: 13),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Text('Is that right? Tap the correct label.', style: Theme.of(context).textTheme.bodyMedium),
          const SizedBox(height: AppSpacing.sm),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: [
              for (final label in const [
                QualityClass.good,
                QualityClass.damaged,
                QualityClass.broken,
                QualityClass.shriveled,
                QualityClass.impurities,
              ])
                _LabelButton(
                  label: label,
                  isPredicted: label == item.predictedLabel,
                  onTap: () => _verify(label),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Center(
            child: TextButton(
              onPressed: _skip,
              child: const Text('Skip for now'),
            ),
          ),
        ],
      ),
    );
  }

  String _relativeDate(DateTime dt) {
    final days = DateTime.now().difference(dt).inDays;
    if (days <= 0) return 'today';
    if (days == 1) return 'yesterday';
    return '$days days ago';
  }
}

class _LabelButton extends StatelessWidget {
  const _LabelButton({required this.label, required this.isPredicted, required this.onTap});
  final QualityClass label;
  final bool isPredicted;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton(
      onPressed: onTap,
      style: OutlinedButton.styleFrom(
        side: BorderSide(color: isPredicted ? AppColors.accent : AppColors.divider, width: isPredicted ? 1.5 : 1),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      ),
      child: Text(label.label),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.reviewedCount});
  final int reviewedCount;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.check_circle_outline, size: 48, color: AppColors.good),
            const SizedBox(height: AppSpacing.md),
            Text(
              reviewedCount > 0 ? "You're all caught up!" : 'Nothing to review right now.',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              reviewedCount > 0
                  ? 'Reviewed $reviewedCount seed${reviewedCount == 1 ? '' : 's'} this session — thanks for helping train the model.'
                  : 'Scan a batch of seeds, then come back here to help verify the results.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ],
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../application/device_manager.dart';
import '../../core/providers.dart';
import '../../core/theme/app_theme.dart';
import '../../domain/entities/nir_device_info.dart';
import '../widgets/agrispectra_mark.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final nirStatus = ref.watch(deviceManagerProvider);
    final unverifiedCount = ref.watch(unverifiedSeedCountProvider);

    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      const AgriSpectraMark(size: 32),
                      const SizedBox(width: AppSpacing.sm),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('AgriSpectra', style: Theme.of(context).textTheme.headlineLarge),
                          const SizedBox(height: 2),
                          Text(
                            'Seed quality screening',
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                        ],
                      ),
                    ],
                  ),
                  IconButton(
                    onPressed: () => context.push('/settings'),
                    icon: const Icon(Icons.settings_outlined),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.xl),
              _StatusCard(nirStatus: nirStatus),
              const SizedBox(height: AppSpacing.lg),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () => context.push('/scan/crop'),
                  icon: const Icon(Icons.center_focus_strong),
                  label: const Padding(
                    padding: EdgeInsets.symmetric(vertical: 4),
                    child: Text('NEW SCAN'),
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.xxl),
              Text('MENU', style: Theme.of(context).textTheme.labelSmall),
              const SizedBox(height: AppSpacing.sm),
              _MenuTile(
                icon: Icons.history,
                title: 'Scan History',
                subtitle: 'Review past batches',
                onTap: () => context.push('/history'),
              ),
              _MenuTile(
                icon: Icons.auto_awesome_outlined,
                title: 'Make Our App Better',
                subtitle: unverifiedCount.when(
                  data: (count) => count > 0 ? '$count seed${count == 1 ? '' : 's'} waiting for you to check' : 'All caught up',
                  loading: () => 'Checking…',
                  error: (_, _) => 'Verify past scan results',
                ),
                highlighted: true,
                onTap: () => context.push('/improve'),
              ),
              _MenuTile(
                icon: Icons.sensors,
                title: 'NIR Device',
                subtitle: nirStatus.status == NirConnectionStatus.connected
                    ? 'Connected — ${nirStatus.displayName}'
                    : 'Not connected',
                onTap: () => context.push('/nir'),
              ),
              _MenuTile(
                icon: Icons.help_outline,
                title: 'Help / Methodology',
                subtitle: 'What AgriSpectra does and doesn\'t measure',
                onTap: () => _showMethodologySheet(context),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showMethodologySheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (context) => Padding(
        padding: const EdgeInsets.fromLTRB(AppSpacing.lg, 0, AppSpacing.lg, AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Methodology', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: AppSpacing.md),
            Text(
              'AgriSpectra provides preliminary, non-destructive visual seed-quality '
              'screening from smartphone camera images, optionally enhanced with '
              'discrete near-infrared spectral readings. It reports observable '
              'characteristics and model-derived quality estimates — it does not '
              'measure embryo viability or predict germination, and it is not a '
              'replacement for certified laboratory testing.',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ],
        ),
      ),
    );
  }
}

class _StatusCard extends StatelessWidget {
  const _StatusCard({required this.nirStatus});
  final NirDeviceInfo nirStatus;

  @override
  Widget build(BuildContext context) {
    final connected = nirStatus.status == NirConnectionStatus.connected;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.camera_alt_outlined, size: 18, color: AppColors.accent),
                const SizedBox(width: AppSpacing.sm),
                Text('Camera Scanner', style: Theme.of(context).textTheme.titleMedium),
                const Spacer(),
                _StatusPill(label: 'READY', color: AppColors.good),
              ],
            ),
            const Divider(height: AppSpacing.xl),
            Row(
              children: [
                Icon(
                  connected ? Icons.sensors : Icons.sensors_off_outlined,
                  size: 18,
                  color: connected ? AppColors.nir : AppColors.inkFaint,
                ),
                const SizedBox(width: AppSpacing.sm),
                Text('NIR Spectroscope', style: Theme.of(context).textTheme.titleMedium),
                const Spacer(),
                _StatusPill(
                  label: connected ? 'CONNECTED' : 'NOT CONNECTED',
                  color: connected ? AppColors.nir : AppColors.inkFaint,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.label, required this.color});
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppRadius.sm),
      ),
      child: Text(
        label,
        style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: color, letterSpacing: 0.4),
      ),
    );
  }
}

class _MenuTile extends StatelessWidget {
  const _MenuTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.highlighted = false,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  /// Set for the one action that grows the dataset (§44) — a subtle
  /// accent border, not a different shape or color scheme, so it reads as
  /// "worth a look" without competing with the primary NEW SCAN button.
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Card(
        shape: highlighted
            ? RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppRadius.lg),
                side: const BorderSide(color: AppColors.accent, width: 1.5),
              )
            : null,
        child: ListTile(
          onTap: onTap,
          leading: Icon(icon, color: highlighted ? AppColors.accent : AppColors.inkMuted),
          title: Text(title, style: Theme.of(context).textTheme.titleMedium),
          subtitle: Text(
            subtitle,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: highlighted ? AppColors.accent : null,
                  fontWeight: highlighted ? FontWeight.w600 : null,
                ),
          ),
          trailing: const Icon(Icons.chevron_right, size: 20),
        ),
      ),
    );
  }
}

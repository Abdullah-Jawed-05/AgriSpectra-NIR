import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';

/// A centred, **scrollable** error panel with an optional retry. Async
/// screens should use this for their `error:` branch rather than a bare
/// `Center(child: Text('$e'))` — a long error (a provider stack trace, a
/// DB message) otherwise overflows with no way to scroll or recover
/// (§58 "failures must be handled, not crash / dead-end the app").
class ErrorState extends StatelessWidget {
  const ErrorState({
    super.key,
    required this.title,
    this.detail,
    this.icon = Icons.error_outline,
    this.onRetry,
  });

  final String title;
  final Object? detail;
  final IconData icon;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: constraints.maxHeight),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 40, color: AppColors.inkFaint),
              const SizedBox(height: AppSpacing.md),
              Text(title, textAlign: TextAlign.center, style: Theme.of(context).textTheme.titleMedium),
              if (detail != null) ...[
                const SizedBox(height: AppSpacing.sm),
                Text(
                  '$detail',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.inkFaint),
                ),
              ],
              if (onRetry != null) ...[
                const SizedBox(height: AppSpacing.lg),
                OutlinedButton.icon(
                  onPressed: onRetry,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Try again'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

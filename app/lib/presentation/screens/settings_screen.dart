import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/constants/app_constants.dart';
import '../../core/theme/app_theme.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        children: [
          _Section(title: 'About', children: [
            _InfoTile(label: 'App version', value: AppVersions.appVersion),
            _InfoTile(label: 'Vision model', value: AppVersions.visionModelVersion),
            _InfoTile(label: 'NIR model', value: AppVersions.nirModelVersion),
            _InfoTile(label: 'Fusion model', value: AppVersions.fusionModelVersion),
            _InfoTile(label: 'NIR protocol', value: 'v${AppVersions.nirProtocolVersion}'),
          ]),
          const SizedBox(height: AppSpacing.lg),
          _Section(title: 'Device', children: [
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('NIR device'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => context.push('/nir'),
            ),
          ]),
          const SizedBox(height: AppSpacing.lg),
          _Section(title: 'Data', children: [
            const _InfoTile(label: 'Storage', value: 'Local only (on-device)'),
            const _InfoTile(label: 'Cloud upload', value: 'Not implemented'),
          ]),
          const SizedBox(height: AppSpacing.lg),
          _Section(title: 'Privacy', children: [
            Text(
              'Scan images and results are stored locally on this device only. '
              'AgriSpectra does not upload images or results to any server.',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ]),
        ],
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.children});
  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title.toUpperCase(), style: Theme.of(context).textTheme.labelSmall),
        const SizedBox(height: AppSpacing.sm),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: children),
          ),
        ),
      ],
    );
  }
}

class _InfoTile extends StatelessWidget {
  const _InfoTile({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
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

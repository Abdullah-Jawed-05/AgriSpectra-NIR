import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/device_manager.dart';
import '../../core/theme/app_theme.dart';
import '../../domain/entities/nir_device_info.dart';
import '../../nir/simulated_nir_device.dart';

class NirDeviceScreen extends ConsumerStatefulWidget {
  const NirDeviceScreen({super.key});

  @override
  ConsumerState<NirDeviceScreen> createState() => _NirDeviceScreenState();
}

class _NirDeviceScreenState extends ConsumerState<NirDeviceScreen> {
  bool _busy = false;
  bool _calibrating = false;
  DateTime? _lastCalibratedAt;

  @override
  Widget build(BuildContext context) {
    final status = ref.watch(deviceManagerProvider);
    final manager = ref.read(deviceManagerProvider.notifier);
    final connected = status.status == NirConnectionStatus.connected;

    return Scaffold(
      appBar: AppBar(title: const Text('NIR Spectroscope')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.lg),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            connected ? Icons.sensors : Icons.sensors_off_outlined,
                            color: connected ? AppColors.nir : AppColors.inkFaint,
                          ),
                          const SizedBox(width: AppSpacing.sm),
                          Text(status.displayName, style: Theme.of(context).textTheme.titleMedium),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      Text(
                        connected ? 'Connected' : 'Not Connected',
                        style: TextStyle(
                          color: connected ? AppColors.good : AppColors.inkFaint,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      if (status.isSimulated) ...[
                        const SizedBox(height: AppSpacing.sm),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: AppColors.nirMuted,
                            borderRadius: BorderRadius.circular(AppRadius.sm),
                          ),
                          child: const Text(
                            'SIMULATED DEVICE — not real hardware',
                            style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: AppColors.nir),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              if (!connected) ...[
                Text('Compatible devices', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: AppSpacing.sm),
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.science_outlined),
                    title: const Text('AgriSpectra-NIR (Simulated)'),
                    subtitle: const Text('Synthetic spectral data for development and demos'),
                    trailing: _busy
                        ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.chevron_right),
                    onTap: _busy
                        ? null
                        : () async {
                            setState(() => _busy = true);
                            await manager.useSimulatedDevice();
                            setState(() => _busy = false);
                          },
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.bluetooth_searching),
                    title: const Text('Search for real device'),
                    subtitle: const Text('No physical AgriSpectra NIR hardware exists yet (see docs/ARCHITECTURE.md)'),
                    enabled: false,
                  ),
                ),
              ] else ...[
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Calibration', style: Theme.of(context).textTheme.titleMedium),
                    if (_lastCalibratedAt != null)
                      Text(
                        'Last: ${_lastCalibratedAt!.hour.toString().padLeft(2, '0')}:${_lastCalibratedAt!.minute.toString().padLeft(2, '0')}',
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                  ],
                ),
                const SizedBox(height: AppSpacing.sm),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(AppSpacing.lg),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Step 1. Place reference target.\n'
                          'Step 2. Close chamber.\n'
                          'Step 3. Run dark measurement.\n'
                          'Step 4. Run white reference.\n'
                          'Step 5. Calibration complete.',
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                        const SizedBox(height: AppSpacing.md),
                        SizedBox(
                          width: double.infinity,
                          child: OutlinedButton.icon(
                            onPressed: _calibrating
                                ? null
                                : () async {
                                    setState(() => _calibrating = true);
                                    final sim = manager.simulatedDeviceOrNull;
                                    if (sim != null) await sim.runCalibration();
                                    setState(() {
                                      _calibrating = false;
                                      _lastCalibratedAt = DateTime.now();
                                    });
                                  },
                            icon: _calibrating
                                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                                : const Icon(Icons.tune),
                            label: Text(_calibrating ? 'Calibrating…' : 'Run Calibration'),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.lg),
                if (manager.simulatedDeviceOrNull != null) _SimulatorProfilePicker(manager: manager),
                const SizedBox(height: AppSpacing.lg),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton(
                    onPressed: () async {
                      await manager.useNoDevice();
                    },
                    child: const Text('Disconnect'),
                  ),
                ),
              ],
              const SizedBox(height: AppSpacing.xxl),
              Text('Future functionality', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: AppSpacing.sm),
              Text(
                '• Real-time spectral measurements from physical AS7265x hardware\n'
                '• Full BLE calibration and diagnostics (see nir_protocol/protocol.md)\n'
                '• Temperature / humidity compensation\n'
                '• Battery status',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SimulatorProfilePicker extends StatefulWidget {
  const _SimulatorProfilePicker({required this.manager});
  final DeviceManager manager;

  @override
  State<_SimulatorProfilePicker> createState() => _SimulatorProfilePickerState();
}

class _SimulatorProfilePickerState extends State<_SimulatorProfilePicker> {
  SimulatedSeedProfile _profile = SimulatedSeedProfile.goodSeed;

  String _label(SimulatedSeedProfile p) => switch (p) {
        SimulatedSeedProfile.goodSeed => 'Good seed',
        SimulatedSeedProfile.agedSeed => 'Aged seed',
        SimulatedSeedProfile.moistureStressed => 'Moisture-stressed',
        SimulatedSeedProfile.damagedSeed => 'Damaged seed',
        SimulatedSeedProfile.unknown => 'Unknown',
      };

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Simulator profile', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(
              'Controls what synthetic spectral shape the simulator produces for the next scan.',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: AppSpacing.md),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: SimulatedSeedProfile.values
                  .map((p) => ChoiceChip(
                        label: Text(_label(p)),
                        selected: _profile == p,
                        onSelected: (_) {
                          setState(() => _profile = p);
                          widget.manager.simulatedDeviceOrNull?.profile = p;
                        },
                      ))
                  .toList(),
            ),
          ],
        ),
      ),
    );
  }
}

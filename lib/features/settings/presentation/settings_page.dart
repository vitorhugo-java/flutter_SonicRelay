import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_spacing.dart';
import '../../../core/widgets/sonic_button.dart';
import '../../../core/widgets/sonic_card.dart';
import '../../auth/presentation/login_view_model.dart';
import '../../devices/presentation/devices_view_model.dart';
import '../../devices/presentation/widgets/device_card.dart';
import 'widgets/server_url_field.dart';

class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final devices = ref.watch(devicesViewModelProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 620),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Viewer preferences',
                    style: Theme.of(context).textTheme.headlineMedium,
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    'Integration settings will become available in a future release.',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  SonicCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const _SettingsRow(
                          icon: Icons.cloud_outlined,
                          title: 'Server',
                          subtitle: 'SonicRelay API endpoint',
                        ),
                        const SizedBox(height: AppSpacing.md),
                        const ServerUrlField(),
                        const Divider(height: AppSpacing.xl),
                        const _SettingsRow(
                          icon: Icons.dark_mode_outlined,
                          title: 'Appearance',
                          subtitle: 'Dark theme',
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xl),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Your devices',
                          style: Theme.of(context).textTheme.headlineSmall,
                        ),
                      ),
                      IconButton(
                        tooltip: 'Refresh devices',
                        onPressed: devices.isLoading
                            ? null
                            : () => ref
                                  .read(devicesViewModelProvider.notifier)
                                  .refresh(),
                        icon: const Icon(Icons.refresh_rounded),
                      ),
                    ],
                  ),
                  if (devices.isLoading) ...[
                    const SizedBox(height: AppSpacing.sm),
                    const LinearProgressIndicator(),
                  ],
                  if (devices.errorMessage case final message?) ...[
                    const SizedBox(height: AppSpacing.sm),
                    Text(
                      message,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ],
                  if (!devices.isLoading &&
                      devices.errorMessage == null &&
                      devices.devices.isEmpty) ...[
                    const SizedBox(height: AppSpacing.sm),
                    Text(
                      'No registered devices found.',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ],
                  for (final device in devices.devices) ...[
                    const SizedBox(height: AppSpacing.sm),
                    DeviceCard(
                      device: device,
                      isCurrent: device.id == devices.currentDeviceId,
                    ),
                  ],
                  const SizedBox(height: AppSpacing.xl),
                  SonicButton(
                    label: 'Log out',
                    icon: Icons.logout_rounded,
                    isSecondary: true,
                    onPressed: () =>
                        ref.read(authViewModelProvider.notifier).logout(),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  const Text(
                    'SonicRelay mobile viewer · UI preview',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: AppColors.textSecondary),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SettingsRow extends StatelessWidget {
  const _SettingsRow({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, color: AppColors.accent),
        const SizedBox(width: AppSpacing.md),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: Theme.of(context).textTheme.titleMedium),
              Text(subtitle, style: Theme.of(context).textTheme.bodyMedium),
            ],
          ),
        ),
      ],
    );
  }
}

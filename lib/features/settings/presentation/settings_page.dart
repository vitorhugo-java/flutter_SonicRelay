import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import '../../../app/di/app_providers.dart';
import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_spacing.dart';
import '../../../core/widgets/sonic_button.dart';
import '../../../core/widgets/sonic_card.dart';
import '../../auth/presentation/login_view_model.dart';
import '../../devices/presentation/devices_view_model.dart';
import '../../devices/presentation/widgets/device_card.dart';
import 'widgets/keep_playing_toggle.dart';
import 'widgets/relay_mode_toggle.dart';
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
                          icon: Icons.hub_outlined,
                          title: 'Connection',
                          subtitle: 'ICE transport',
                        ),
                        const SizedBox(height: AppSpacing.sm),
                        const RelayModeToggle(),
                        const Divider(height: AppSpacing.xl),
                        const _SettingsRow(
                          icon: Icons.headset_outlined,
                          title: 'Playback',
                          subtitle: 'Background audio',
                        ),
                        const SizedBox(height: AppSpacing.sm),
                        const KeepPlayingToggle(),
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
                  Text(
                    'Diagnostics',
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  const _DiagnosticsSection(),
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
                  const _DeleteAccountButton(),
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

class _DeleteAccountButton extends ConsumerStatefulWidget {
  const _DeleteAccountButton();

  @override
  ConsumerState<_DeleteAccountButton> createState() =>
      _DeleteAccountButtonState();
}

class _DeleteAccountButtonState extends ConsumerState<_DeleteAccountButton> {
  bool _isDeleting = false;

  Future<void> _confirmAndDelete() async {
    final theme = Theme.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete account?'),
        content: const Text(
          'This permanently disables your SonicRelay account. Your devices and '
          'active sessions are revoked and you will be signed out. This cannot '
          'be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: theme.colorScheme.error),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _isDeleting = true);
    final error = await ref.read(authViewModelProvider.notifier).deleteAccount();
    if (!mounted) return;
    setState(() => _isDeleting = false);
    if (error != null) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(error)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final errorColor = Theme.of(context).colorScheme.error;
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        onPressed: _isDeleting ? null : _confirmAndDelete,
        style: OutlinedButton.styleFrom(
          foregroundColor: errorColor,
          side: BorderSide(color: errorColor.withValues(alpha: 0.6)),
          minimumSize: const Size.fromHeight(54),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
        icon: _isDeleting
            ? const SizedBox.square(
                dimension: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.delete_forever_rounded, size: 20),
        label: Text(_isDeleting ? 'Deleting…' : 'Delete account'),
      ),
    );
  }
}

class _DiagnosticsSection extends ConsumerStatefulWidget {
  const _DiagnosticsSection();

  @override
  ConsumerState<_DiagnosticsSection> createState() => _DiagnosticsSectionState();
}

class _DiagnosticsSectionState extends ConsumerState<_DiagnosticsSection> {
  bool _isBusy = false;
  String? _message;

  Future<void> _export() async {
    setState(() {
      _isBusy = true;
      _message = null;
    });
    try {
      final path = await ref.read(diagnosticLogProvider).export();
      if (!mounted) return;
      await SharePlus.instance.share(ShareParams(files: [XFile(path)]));
      setState(() => _message = 'Exported diagnostics log.');
    } catch (_) {
      setState(() => _message = 'Export failed: could not write the log file.');
    } finally {
      if (mounted) setState(() => _isBusy = false);
    }
  }

  Future<void> _confirmAndClear() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Clear diagnostics log?'),
        content: const Text(
          'This permanently deletes the on-device diagnostics log. This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            style: TextButton.styleFrom(
              foregroundColor: Theme.of(dialogContext).colorScheme.error,
            ),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Clear'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() {
      _isBusy = true;
      _message = null;
    });
    try {
      await ref.read(diagnosticLogProvider).clear();
      setState(() => _message = 'Cleared the diagnostics log.');
    } catch (_) {
      setState(() => _message = 'Clear failed: could not delete the log file(s).');
    } finally {
      if (mounted) setState(() => _isBusy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SonicCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _SettingsRow(
            icon: Icons.bug_report_outlined,
            title: 'Diagnostics log',
            subtitle: 'Redacted connection/session history for support requests',
          ),
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              Expanded(
                child: SonicButton(
                  label: 'Export logs',
                  icon: Icons.ios_share_rounded,
                  onPressed: _isBusy ? null : _export,
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: SonicButton(
                  label: 'Clear logs',
                  icon: Icons.delete_outline_rounded,
                  isSecondary: true,
                  onPressed: _isBusy ? null : _confirmAndClear,
                ),
              ),
            ],
          ),
          if (_message case final message?) ...[
            const SizedBox(height: AppSpacing.sm),
            Text(message, style: Theme.of(context).textTheme.bodyMedium),
          ],
        ],
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

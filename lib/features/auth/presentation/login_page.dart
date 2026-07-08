import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_spacing.dart';
import '../../../core/widgets/sonic_button.dart';
import '../../../core/widgets/sonic_card.dart';
import '../../../core/widgets/sonic_text_field.dart';
import '../../settings/presentation/widgets/server_url_field.dart';
import 'login_view_model.dart';

class LoginPage extends ConsumerStatefulWidget {
  const LoginPage({super.key});

  @override
  ConsumerState<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends ConsumerState<LoginPage> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  String? _emailError;
  String? _passwordError;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final email = _emailController.text.trim();
    final password = _passwordController.text;
    final validEmail = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email);
    setState(() {
      _emailError = validEmail ? null : 'Enter a valid email address.';
      _passwordError = password.isEmpty ? 'Password is required.' : null;
    });
    if (!validEmail || password.isEmpty) return;
    await ref
        .read(authViewModelProvider.notifier)
        .login(email: email, password: password);
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authViewModelProvider);
    return Scaffold(
      body: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: RadialGradient(
            center: Alignment.topRight,
            radius: 1.1,
            colors: [Color(0x3328C7A5), AppColors.background],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 440),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const _BrandMark(),
                    const SizedBox(height: AppSpacing.xl),
                    Text(
                      'Hear every detail.',
                      style: Theme.of(context).textTheme.displaySmall,
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    Text(
                      'Sign in to monitor your SonicRelay sessions from anywhere.',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    const SizedBox(height: AppSpacing.xl),
                    SonicCard(
                      child: Column(
                        children: [
                          SonicTextField(
                            label: 'Email',
                            controller: _emailController,
                            keyboardType: TextInputType.emailAddress,
                            prefixIcon: Icons.alternate_email_rounded,
                            errorText: _emailError,
                          ),
                          const SizedBox(height: AppSpacing.md),
                          SonicTextField(
                            label: 'Password',
                            controller: _passwordController,
                            obscureText: true,
                            prefixIcon: Icons.lock_outline_rounded,
                            errorText: _passwordError,
                          ),
                          if (auth.errorMessage != null) ...[
                            const SizedBox(height: AppSpacing.md),
                            Text(
                              auth.errorMessage!,
                              style: TextStyle(
                                color: Theme.of(context).colorScheme.error,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ],
                          const SizedBox(height: AppSpacing.lg),
                          SonicButton(
                            label: 'Sign in',
                            icon: Icons.arrow_forward_rounded,
                            isLoading: auth.status == AuthStatus.authenticating,
                            onPressed: _submit,
                          ),
                          const SizedBox(height: AppSpacing.sm),
                          TextButton(
                            onPressed: null,
                            child: const Text(
                              'Create an account (coming soon)',
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: AppSpacing.md),
                    SonicCard(
                      padding: EdgeInsets.zero,
                      child: Theme(
                        data: Theme.of(
                          context,
                        ).copyWith(dividerColor: Colors.transparent),
                        child: ExpansionTile(
                          leading: const Icon(
                            Icons.dns_outlined,
                            color: AppColors.accent,
                          ),
                          title: const Text('Server settings'),
                          subtitle: const Text('Configure the SonicRelay server'),
                          childrenPadding: const EdgeInsets.fromLTRB(
                            AppSpacing.xl,
                            0,
                            AppSpacing.xl,
                            AppSpacing.xl,
                          ),
                          children: const [ServerUrlField()],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _BrandMark extends StatelessWidget {
  const _BrandMark();
  @override
  Widget build(BuildContext context) => Row(
    children: [
      Container(
        width: 42,
        height: 42,
        decoration: BoxDecoration(
          color: AppColors.accentMuted,
          borderRadius: BorderRadius.circular(13),
        ),
        child: const Icon(Icons.graphic_eq_rounded, color: AppColors.accent),
      ),
      const SizedBox(width: AppSpacing.sm),
      Text('SonicRelay', style: Theme.of(context).textTheme.titleLarge),
    ],
  );
}

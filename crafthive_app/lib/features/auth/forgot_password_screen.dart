import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/validators.dart';
import '../../data/models.dart';
import '../../data/providers.dart';
import '../../shared/widgets/common.dart';
import '../../shared/widgets/craft_icon.dart';

/// Supporting screen – Forgot password.
/// Supabase emails a reset link. Tapping it on this phone opens the app on
/// "Choose a new password" (reset_password_screen.dart).
class ForgotPasswordScreen extends ConsumerStatefulWidget {
  const ForgotPasswordScreen({super.key});
  @override
  ConsumerState<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends ConsumerState<ForgotPasswordScreen> {
  final _form = GlobalKey<FormState>();
  final _email = TextEditingController();
  bool _sent = false;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    if (_busy) return;
    FocusScope.of(context).unfocus();
    setState(() => _error = null);
    if (!_form.currentState!.validate()) return;
    setState(() => _busy = true);
    try {
      await ref.read(authProvider.notifier).sendPasswordResetLink(_email.text);
      if (mounted) setState(() => _sent = true);
    } on AppFailure catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const ScreenHeader(title: 'Forgot password', fallback: '/login'),
      body: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(Insets.screen, 12, Insets.screen, 24),
          child: ResponsiveCenter(
            maxWidth: 480,
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 250),
              child: _sent
                  ? Column(key: const ValueKey('sent'), children: [
                      const SizedBox(height: 24),
                      Container(
                        width: 76,
                        height: 76,
                        decoration: const BoxDecoration(color: AppColors.fernTint, shape: BoxShape.circle),
                        alignment: Alignment.center,
                        child: const CraftIcon(CraftIcons.mail, size: 36, color: AppColors.fern),
                      ),
                      const SizedBox(height: 16),
                      Text('Check your email', style: AppText.headline.copyWith(fontSize: 21)),
                      const SizedBox(height: 8),
                      Text(
                        'If an account uses ${_email.text.trim()}, we sent it a reset link. Open the email on this phone and tap '
                        'Reset password. CraftHive will open so you can choose a new password.',
                        style: AppText.body.copyWith(color: AppColors.grayBrown),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 24),
                      AppButton(label: 'Back to log in', onPressed: () => context.go('/login')),
                      const SizedBox(height: 8),
                      TextButton(onPressed: () => setState(() => _sent = false), child: const Text('Use a different email')),
                    ])
                  : Form(
                      key: _form,
                      child: Column(key: const ValueKey('form'), crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                        Text('Enter the email you signed up with and we will send you a link to reset your password.',
                            style: AppText.body.copyWith(color: AppColors.grayBrown)),
                        const SizedBox(height: 18),
                        LabeledField(
                          label: 'Email',
                          controller: _email,
                          hint: 'you@email.com',
                          icon: CraftIcons.mail,
                          keyboardType: TextInputType.emailAddress,
                          textInputAction: TextInputAction.done,
                          autofillHints: const [AutofillHints.email],
                          validator: Validators.email,
                          onSubmitted: (_) => _send(),
                        ),
                        if (_error != null) ...[const SizedBox(height: 12), InfoNote(_error!, tone: Tone.error, icon: CraftIcons.info)],
                        const SizedBox(height: 20),
                        AppButton(label: 'Send reset link', icon: CraftIcons.send, onPressed: _send, loading: _busy),
                      ]),
                    ),
            ),
          ),
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../shared/widgets/common.dart';
import '../../shared/widgets/craft_icon.dart';

/// Supporting screen – Forgot password (Firebase sends the reset email in Milestone 3).
class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key});
  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final _form = GlobalKey<FormState>();
  final _email = TextEditingController();
  bool _sent = false;
  bool _busy = false;

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _busy = true);
    await Future<void>.delayed(const Duration(milliseconds: 600));
    if (mounted) setState(() {
      _busy = false;
      _sent = true;
    });
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
                      Text('We sent a reset link to ${_email.text.trim()}. Follow it to choose a new password.',
                          style: AppText.body.copyWith(color: AppColors.grayBrown), textAlign: TextAlign.center),
                      const SizedBox(height: 24),
                      AppButton(label: 'Back to log in', onPressed: () => context.go('/login')),
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
                          validator: (v) => RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(v?.trim() ?? '') ? null : 'Enter a valid email address.',
                        ),
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

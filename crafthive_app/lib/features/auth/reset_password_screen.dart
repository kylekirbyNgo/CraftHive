import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/validators.dart';
import '../../data/models.dart';
import '../../data/providers.dart';
import '../../shared/widgets/common.dart';
import '../../shared/widgets/craft_icon.dart';

/// Opened by the link in the password-reset email. The link has already signed
/// the user in; they choose a new password here, then continue to Home.
class ResetPasswordScreen extends ConsumerStatefulWidget {
  const ResetPasswordScreen({super.key});
  @override
  ConsumerState<ResetPasswordScreen> createState() => _ResetPasswordScreenState();
}

class _ResetPasswordScreenState extends ConsumerState<ResetPasswordScreen> {
  final _form = GlobalKey<FormState>();
  final _pw = TextEditingController();
  final _pw2 = TextEditingController();
  bool _hide = true;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _pw.dispose();
    _pw2.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_busy) return;
    FocusScope.of(context).unfocus();
    setState(() => _error = null);
    if (!_form.currentState!.validate()) return;
    setState(() => _busy = true);
    try {
      await ref.read(authProvider.notifier).updatePassword(_pw.text);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Password changed. You are now logged in.')));
      ref.read(passwordRecoveryProvider.notifier).state = false; // the router opens Home
    } on AppFailure catch (e) {
      if (mounted) {
        setState(() {
          _error = e.message;
          _busy = false;
        });
      }
    }
  }

  Future<void> _cancel() async {
    ref.read(passwordRecoveryProvider.notifier).state = false;
    await ref.read(authProvider.notifier).signOut();
  }

  @override
  Widget build(BuildContext context) {
    final email = ref.watch(authProvider)?.email ?? '';
    return Scaffold(
      appBar: AppBar(title: Text('Choose a new password', style: AppText.screenTitle), automaticallyImplyLeading: false),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(Insets.screen, 12, Insets.screen, 24),
          child: ResponsiveCenter(
            maxWidth: 480,
            child: Form(
              key: _form,
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Text(email.isEmpty ? 'Enter a new password for your account.' : 'Enter a new password for $email.',
                    style: AppText.body.copyWith(color: AppColors.grayBrown)),
                const SizedBox(height: 18),
                LabeledField(
                  label: 'New password',
                  controller: _pw,
                  hint: 'At least 8 characters',
                  icon: CraftIcons.lock,
                  obscure: _hide,
                  helper: 'At least 8 characters, with letters and a number.',
                  autofillHints: const [AutofillHints.newPassword],
                  validator: Validators.newPassword,
                  suffix: IconButton(
                    tooltip: _hide ? 'Show password' : 'Hide password',
                    onPressed: () => setState(() => _hide = !_hide),
                    icon: CraftIcon(_hide ? CraftIcons.eye : CraftIcons.eyeOff, size: 20, color: AppColors.grayBrown),
                  ),
                ),
                const SizedBox(height: 12),
                LabeledField(
                  label: 'Confirm new password',
                  controller: _pw2,
                  hint: 'Type it again',
                  icon: CraftIcons.lock,
                  obscure: _hide,
                  textInputAction: TextInputAction.done,
                  validator: (v) => v == _pw.text ? null : 'The passwords do not match.',
                  onSubmitted: (_) => _save(),
                ),
                if (_error != null) ...[const SizedBox(height: 12), InfoNote(_error!, tone: Tone.error, icon: CraftIcons.info)],
                const SizedBox(height: 20),
                AppButton(label: 'Save new password', icon: CraftIcons.check, onPressed: _save, loading: _busy),
                const SizedBox(height: 8),
                TextButton(onPressed: _busy ? null : _cancel, child: const Text('Cancel and log out')),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

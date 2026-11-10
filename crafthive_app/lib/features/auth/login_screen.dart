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

/// Screen 1 – Log in (username or email + password).
class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});
  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _form = GlobalKey<FormState>();
  final _id = TextEditingController();
  final _pw = TextEditingController();
  bool _hide = true;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _id.dispose();
    _pw.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy) return;
    FocusScope.of(context).unfocus();
    setState(() => _error = null);
    if (!_form.currentState!.validate()) return;
    setState(() => _busy = true);
    try {
      await ref.read(authProvider.notifier).logIn(_id.text.trim(), _pw.text);
      // Signed in: the router opens Home once the profile has loaded.
    } on AppFailure catch (e) {
      if (mounted) setState(() {
        _error = e.message;
        _busy = false;
      });
    } catch (_) {
      if (mounted) setState(() {
        _error = 'Something went wrong. Please try again.';
        _busy = false;
      });
    }
  }

  void _clearError() {
    if (_error != null) setState(() => _error = null);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, c) => SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 28),
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: c.maxHeight),
              child: ResponsiveCenter(
                maxWidth: 440,
                child: Form(
                  key: _form,
                  // Re-check a field as soon as it changes, so a fixed field's
                  // error disappears right away (bug B-02).
                  autovalidateMode: AutovalidateMode.onUserInteraction,
                  child: AutofillGroup(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const SizedBox(height: 48),
                        Center(
                          child: Semantics(
                            label: 'CraftHive logo',
                            image: true,
                            child: ClipOval(child: Image.asset('assets/images/logo.png', width: 104, height: 104, fit: BoxFit.cover)),
                          ),
                        ),
                        const SizedBox(height: 14),
                        Text('CraftHive', style: AppText.display, textAlign: TextAlign.center),
                        const SizedBox(height: 6),
                        Text('Your all-in-one market for handmade and custom-made goods',
                            style: AppText.body.copyWith(color: AppColors.grayBrown), textAlign: TextAlign.center),
                        const SizedBox(height: 28),
                        Text('Welcome back', style: AppText.screenTitle.copyWith(fontSize: 20)),
                        const SizedBox(height: 14),
                        LabeledField(
                          label: 'Username or email',
                          controller: _id,
                          keyboardType: TextInputType.emailAddress,
                          hint: 'ana.makes',
                          icon: CraftIcons.user,
                          autofillHints: const [AutofillHints.username, AutofillHints.email],
                          validator: Validators.loginId,
                          onChanged: (_) => _clearError(),
                        ),
                        const SizedBox(height: 16),
                        LabeledField(
                          label: 'Password',
                          controller: _pw,
                          hint: 'Your password',
                          icon: CraftIcons.lock,
                          obscure: _hide,
                          textInputAction: TextInputAction.done,
                          autofillHints: const [AutofillHints.password],
                          validator: Validators.loginPassword,
                          onChanged: (_) => _clearError(),
                          onSubmitted: (_) => _submit(),
                          suffix: IconButton(
                            tooltip: _hide ? 'Show password' : 'Hide password',
                            onPressed: () => setState(() => _hide = !_hide),
                            icon: CraftIcon(_hide ? CraftIcons.eye : CraftIcons.eyeOff, size: 20, color: AppColors.grayBrown),
                          ),
                        ),
                        Align(
                          alignment: Alignment.centerRight,
                          child: TextButton(onPressed: () => context.push('/forgot-password'), child: const Text('Forgot password?')),
                        ),
                        if (_error != null) ...[
                          InfoNote(_error!, tone: Tone.error, icon: CraftIcons.info),
                          const SizedBox(height: 12),
                        ],
                        AppButton(label: 'Log in', onPressed: _submit, loading: _busy),
                        const SizedBox(height: 26),
                        Row(children: [
                          const Expanded(child: Divider()),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            child: Text('New to CraftHive?', style: AppText.caption.copyWith(fontSize: 13)),
                          ),
                          const Expanded(child: Divider()),
                        ]),
                        const SizedBox(height: 14),
                        AppButton(label: 'Create an account', kind: ButtonKind.outline, onPressed: () => context.push('/signup')),
                        const SizedBox(height: 28),
                        Text("By continuing, you agree to CraftHive's Terms of Service and Privacy Policy.",
                            style: AppText.caption.copyWith(fontSize: 11.5, height: 1.5), textAlign: TextAlign.center),
                        const SizedBox(height: 24),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../data/providers.dart';
import '../../shared/widgets/common.dart';
import '../../shared/widgets/craft_icon.dart';

/// Screen 2 – Sign up: email, phone (+63), country, sex, username and password.
class SignupScreen extends ConsumerStatefulWidget {
  const SignupScreen({super.key});
  @override
  ConsumerState<SignupScreen> createState() => _SignupScreenState();
}

class _SignupScreenState extends ConsumerState<SignupScreen> {
  final _form = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _phone = TextEditingController();
  final _user = TextEditingController();
  final _pw = TextEditingController();
  String _country = 'Philippines';
  String _sex = 'Female';
  bool _agree = false;
  bool _hide = true;
  bool _busy = false;
  bool _showAgreeError = false;

  static const _countries = ['Philippines', 'Singapore', 'Malaysia', 'Indonesia', 'Thailand', 'Vietnam', 'Other'];
  static const _codes = {'Philippines': '+63', 'Singapore': '+65', 'Malaysia': '+60', 'Indonesia': '+62', 'Thailand': '+66', 'Vietnam': '+84', 'Other': '+'};

  @override
  void dispose() {
    for (final c in [_email, _phone, _user, _pw]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    final ok = _form.currentState!.validate();
    setState(() => _showAgreeError = !_agree);
    if (!ok || !_agree) return;
    setState(() => _busy = true);
    await ref.read(authProvider.notifier).signUp(
          email: _email.text.trim(),
          phone: '${_codes[_country]} ${_phone.text.trim()}',
          country: _country,
          sex: _sex,
          username: _user.text.trim(),
        );
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const ScreenHeader(title: 'Create your account', subtitle: 'One account lets you buy and sell.', fallback: '/login'),
      body: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(Insets.screen, 8, Insets.screen, 24),
          child: ResponsiveCenter(
            maxWidth: 480,
            child: Form(
              key: _form,
              autovalidateMode: AutovalidateMode.onUserInteraction,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  LabeledField(
                    label: 'Email',
                    controller: _email,
                    hint: 'you@email.com',
                    icon: CraftIcons.mail,
                    keyboardType: TextInputType.emailAddress,
                    autofillHints: const [AutofillHints.email],
                    validator: (v) => RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(v?.trim() ?? '') ? null : 'Enter a valid email address.',
                  ),
                  const SizedBox(height: 12),
                  Text('Phone number', style: AppText.label),
                  const SizedBox(height: 6),
                  Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Container(
                      height: Insets.fieldHeight + 2,
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      decoration: BoxDecoration(color: AppColors.white, borderRadius: Radii.field, border: Border.all(color: AppColors.linen, width: 1.5)),
                      alignment: Alignment.center,
                      child: Text(_codes[_country]!, style: AppText.bodyStrong.copyWith(fontSize: 15)),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextFormField(
                        controller: _phone,
                        keyboardType: TextInputType.phone,
                        autofillHints: const [AutofillHints.telephoneNumberNational],
                        inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9 ]')), LengthLimitingTextInputFormatter(13)],
                        style: AppText.body.copyWith(fontSize: 15),
                        textInputAction: TextInputAction.next,
                        decoration: const InputDecoration(
                          hintText: '917 123 4567',
                          prefixIcon: Padding(padding: EdgeInsets.only(left: 14, right: 10), child: CraftIcon(CraftIcons.phone, size: 18, color: AppColors.grayBrown)),
                          prefixIconConstraints: BoxConstraints(minWidth: 0, minHeight: 0),
                        ),
                        validator: (v) => (v ?? '').replaceAll(' ', '').length == 10 ? null : 'Enter the 10-digit mobile number.',
                      ),
                    ),
                  ]),
                  const SizedBox(height: 12),
                  Text('Country', style: AppText.label),
                  const SizedBox(height: 6),
                  DropdownButtonFormField<String>(
                    value: _country,
                    icon: const CraftIcon(CraftIcons.chevronDown, size: 18, color: AppColors.grayBrown),
                    style: AppText.body.copyWith(fontSize: 15),
                    borderRadius: Radii.field,
                    dropdownColor: AppColors.white,
                    decoration: const InputDecoration(
                      prefixIcon: Padding(padding: EdgeInsets.only(left: 14, right: 10), child: CraftIcon(CraftIcons.globe, size: 18, color: AppColors.grayBrown)),
                      prefixIconConstraints: BoxConstraints(minWidth: 0, minHeight: 0),
                    ),
                    items: [for (final c in _countries) DropdownMenuItem(value: c, child: Text(c))],
                    onChanged: (v) => setState(() => _country = v!),
                  ),
                  const SizedBox(height: 12),
                  Semantics(header: true, child: Text('Sex', style: AppText.label)),
                  const SizedBox(height: 6),
                  Row(children: [
                    for (final s in ['Female', 'Male', 'Prefer not to say']) ...[
                      Expanded(child: _SexOption(label: s, selected: _sex == s, onTap: () => setState(() => _sex = s))),
                      if (s != 'Prefer not to say') const SizedBox(width: 8),
                    ],
                  ]),
                  const SizedBox(height: 12),
                  LabeledField(
                    label: 'Username',
                    controller: _user,
                    hint: 'ana.makes',
                    icon: CraftIcons.user,
                    helper: '4 to 20 letters, numbers, dots or underscores. Shown on your store.',
                    autofillHints: const [AutofillHints.newUsername],
                    validator: (v) => RegExp(r'^[a-z0-9._]{4,20}$').hasMatch(v?.trim() ?? '') ? null : 'Use 4–20 lowercase letters, numbers, dots or underscores.',
                  ),
                  const SizedBox(height: 12),
                  LabeledField(
                    label: 'Password',
                    controller: _pw,
                    hint: 'At least 8 characters',
                    icon: CraftIcons.lock,
                    obscure: _hide,
                    helper: 'At least 8 characters, including a number.',
                    textInputAction: TextInputAction.done,
                    autofillHints: const [AutofillHints.newPassword],
                    suffix: IconButton(
                      tooltip: _hide ? 'Show password' : 'Hide password',
                      onPressed: () => setState(() => _hide = !_hide),
                      icon: CraftIcon(_hide ? CraftIcons.eye : CraftIcons.eyeOff, size: 20, color: AppColors.grayBrown),
                    ),
                    validator: (v) => (v ?? '').length >= 8 && RegExp(r'\d').hasMatch(v ?? '') ? null : 'Use at least 8 characters, including a number.',
                  ),
                  const SizedBox(height: 10),
                  InkWell(
                    borderRadius: Radii.field,
                    onTap: () => setState(() {
                      _agree = !_agree;
                      if (_agree) _showAgreeError = false;
                    }),
                    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Checkbox(value: _agree, onChanged: (v) => setState(() {
                        _agree = v ?? false;
                        if (_agree) _showAgreeError = false;
                      })),
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.only(top: 12),
                          child: Text('I agree to the Terms of Service and Privacy Policy.', style: AppText.body.copyWith(fontSize: 12.5, height: 1.45)),
                        ),
                      ),
                    ]),
                  ),
                  if (_showAgreeError)
                    Padding(
                      padding: const EdgeInsets.only(left: 12, bottom: 4),
                      child: Text('Please accept the terms to continue.', style: AppText.caption.copyWith(color: AppColors.brick)),
                    ),
                  const SizedBox(height: 8),
                  AppButton(label: 'Sign up', onPressed: _submit, loading: _busy),
                  const SizedBox(height: 14),
                  Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                    Text('Already have an account?', style: AppText.body.copyWith(color: AppColors.grayBrown)),
                    TextButton(onPressed: () => context.canPop() ? context.pop() : context.go('/login'), child: const Text('Log in')),
                  ]),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SexOption extends StatelessWidget {
  const _SexOption({required this.label, required this.selected, required this.onTap});
  final String label;
  final bool selected;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Semantics(
        inMutuallyExclusiveGroup: true,
        checked: selected,
        button: true,
        label: label,
        excludeSemantics: true,
        child: Material(
          color: selected ? AppColors.paleSage : AppColors.white,
          shape: RoundedRectangleBorder(borderRadius: Radii.field, side: BorderSide(color: selected ? AppColors.moss : AppColors.linen, width: 1.5)),
          child: InkWell(
            borderRadius: Radii.field,
            onTap: onTap,
            child: SizedBox(
              height: 44,
              child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                Icon(selected ? Icons.radio_button_checked : Icons.radio_button_off, size: 16, color: selected ? AppColors.moss : AppColors.grayBrown),
                const SizedBox(width: 5),
                Flexible(child: Text(label, style: AppText.label.copyWith(fontSize: 12.5), maxLines: 1, overflow: TextOverflow.ellipsis)),
              ]),
            ),
          ),
        ),
      );
}

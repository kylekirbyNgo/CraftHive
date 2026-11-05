import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../data/providers.dart';
import '../../shared/widgets/common.dart';
import '../../shared/widgets/craft_icon.dart';

/// Supporting screen – Edit profile (same form style as Sign up).
class EditProfileScreen extends ConsumerStatefulWidget {
  const EditProfileScreen({super.key});
  @override
  ConsumerState<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends ConsumerState<EditProfileScreen> {
  final _form = GlobalKey<FormState>();
  late final _user = ref.read(authProvider)!;
  late final _name = TextEditingController(text: _user.displayName);
  late final _bio = TextEditingController(text: _user.bio);
  late final _city = TextEditingController(text: _user.location);
  late final _phone = TextEditingController(text: _user.phone);
  late final _email = TextEditingController(text: _user.email);
  bool _busy = false;

  @override
  void dispose() {
    for (final c in [_name, _bio, _city, _phone, _email]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _busy = true);
    await Future<void>.delayed(const Duration(milliseconds: 500));
    ref.read(authProvider.notifier).updateProfile(
          _user.copyWith(displayName: _name.text.trim(), bio: _bio.text.trim(), location: _city.text.trim(), phone: _phone.text.trim(), email: _email.text.trim()),
        );
    if (!mounted) return;
    showMessage(context, 'Profile saved.');
    context.pop();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const ScreenHeader(title: 'Edit profile', fallback: '/store'),
      body: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(Insets.screen, 4, Insets.screen, 28),
          child: ResponsiveCenter(
            child: Form(
              key: _form,
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Center(
                  child: Stack(clipBehavior: Clip.none, children: [
                    Avatar(initials: _user.initials, size: 88),
                    Positioned(
                      right: -6,
                      bottom: -6,
                      child: RoundIconButton(icon: CraftIcons.camera, tooltip: 'Change profile picture', background: AppColors.white, size: 36, onPressed: () => showComingSoon(context, 'Photo upload')),
                    ),
                  ]),
                ),
                const SizedBox(height: 8),
                Text('@${_user.username}', style: AppText.caption.copyWith(fontSize: 13), textAlign: TextAlign.center),
                const SizedBox(height: 16),
                LabeledField(label: 'Name', controller: _name, icon: CraftIcons.user, validator: (v) => (v ?? '').trim().isEmpty ? 'Enter your name.' : null),
                const SizedBox(height: 12),
                LabeledField(label: 'Store description', controller: _bio, maxLines: 4, maxLength: 500, hint: 'What do you make? How long do orders take?'),
                LabeledField(label: 'City', controller: _city, icon: CraftIcons.pin),
                const SizedBox(height: 12),
                LabeledField(label: 'Phone number', controller: _phone, icon: CraftIcons.phone, keyboardType: TextInputType.phone),
                const SizedBox(height: 12),
                LabeledField(
                  label: 'Email',
                  controller: _email,
                  icon: CraftIcons.mail,
                  keyboardType: TextInputType.emailAddress,
                  validator: (v) => RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(v?.trim() ?? '') ? null : 'Enter a valid email address.',
                ),
                const SizedBox(height: 16),
                const InfoNote('Your phone number and address are shown only to the other person in an order.'),
                const SizedBox(height: 18),
                AppButton(label: 'Save changes', icon: CraftIcons.check, onPressed: _save, loading: _busy),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

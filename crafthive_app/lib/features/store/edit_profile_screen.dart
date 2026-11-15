import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/validators.dart';
import '../../data/models.dart';
import '../../data/providers.dart';
import '../../shared/widgets/action_helpers.dart';
import '../../shared/widgets/common.dart';
import '../../shared/widgets/craft_icon.dart';

/// Supporting screen – Edit profile (same form style as Sign up).
/// Name and phone are saved to USERS; store description and city to STORE (when
/// the user has a store); the photo goes to the avatars bucket (users.avatar_path).
/// A newly picked photo is only a preview until "Save changes" is pressed.
/// A new email address is confirmed through a link Supabase sends to it.
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
  late final _city = TextEditingController(text: _user.hasStore ? _user.location : '');
  late final _phone = TextEditingController(text: Validators.localPhone(_user.country, _user.phoneDigits));
  late final _email = TextEditingController(text: _user.email);
  bool _busy = false;

  /// Picked but not saved yet; uploaded by "Save changes".
  PickedImage? _newPhoto;

  String get _dialCode => Validators.dialCodes[_user.country] ?? '+';

  @override
  void dispose() {
    for (final c in [_name, _bio, _city, _phone, _email]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _changePhoto() async {
    final photo = await pickOnePhoto(context, maxSide: 600);
    if (photo == null || !mounted) return;
    setState(() => _newPhoto = photo);
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    final newEmail = _email.text.trim().toLowerCase();
    final emailChanged = newEmail != _user.email.toLowerCase();
    setState(() => _busy = true);
    final auth = ref.read(authProvider.notifier);
    final photo = _newPhoto;
    final saved = await runWithMessage(
      context,
      () => auth.saveProfile(
        ProfileUpdate(
          fullName: _name.text.trim(),
          phoneDigits: Validators.storedPhone(_dialCode, _phone.text),
          storeDescription: _user.hasStore ? _bio.text : null,
          city: _user.hasStore ? _city.text : null,
        ),
        photo: photo,
        newEmail: emailChanged ? newEmail : null,
      ),
    );
    if (!mounted) return;
    setState(() => _busy = false);
    if (!saved) return;
    // New description, city or photo on my store card.
    ref.invalidate(catalogDataProvider);
    showMessage(
      context,
      emailChanged ? 'Profile saved. Open the link we sent to $newEmail to change your email.' : 'Profile saved.',
    );
    context.pop();
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authProvider) ?? _user;
    final photo = _newPhoto;
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
                    if (photo == null)
                      Avatar(initials: user.initials, size: 88, imageUrl: user.avatarUrl)
                    else
                      // Preview of the new photo; nothing is uploaded until Save changes.
                      ClipOval(child: Image.memory(photo.bytes, width: 88, height: 88, fit: BoxFit.cover, semanticLabel: 'New profile picture, not saved yet')),
                    Positioned(
                      right: -6,
                      bottom: -6,
                      child: RoundIconButton(
                        icon: CraftIcons.camera,
                        tooltip: 'Change profile picture',
                        background: AppColors.white,
                        size: 36,
                        onPressed: _busy ? null : _changePhoto,
                      ),
                    ),
                  ]),
                ),
                if (photo != null)
                  Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                    Flexible(child: Text('New photo. Press Save changes to keep it.', style: AppText.caption, textAlign: TextAlign.center)),
                    TextButton(onPressed: _busy ? null : () => setState(() => _newPhoto = null), child: const Text('Undo')),
                  ])
                else
                  const SizedBox(height: 8),
                Text('@${user.username}', style: AppText.caption.copyWith(fontSize: 13), textAlign: TextAlign.center),
                const SizedBox(height: 16),
                LabeledField(label: 'Name', controller: _name, icon: CraftIcons.user, validator: Validators.fullName),
                const SizedBox(height: 12),
                if (_user.hasStore) ...[
                  LabeledField(label: 'Store description', controller: _bio, maxLines: 4, maxLength: 500, hint: 'What do you make? How long do orders take?'),
                  LabeledField(label: 'City', controller: _city, icon: CraftIcons.pin, validator: Validators.city),
                  const SizedBox(height: 12),
                ] else ...[
                  const InfoNote('Open your store to add a store description and city.', icon: CraftIcons.store, tone: Tone.seller),
                  const SizedBox(height: 12),
                ],
                LabeledField(
                  label: 'Phone number',
                  controller: _phone,
                  icon: CraftIcons.phone,
                  prefixText: '$_dialCode ',
                  keyboardType: TextInputType.phone,
                  validator: (v) => Validators.phone(v, country: _user.country),
                ),
                const SizedBox(height: 12),
                LabeledField(
                  label: 'Email',
                  controller: _email,
                  icon: CraftIcons.mail,
                  keyboardType: TextInputType.emailAddress,
                  validator: Validators.email,
                ),
                const SizedBox(height: 16),
                const InfoNote('Your phone number and address are shown only to the other person in an order. '
                    'A new email address changes after you open the confirmation link we send to it.'),
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

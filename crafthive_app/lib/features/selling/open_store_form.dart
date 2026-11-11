import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../data/providers.dart';
import '../../shared/widgets/common.dart';
import '../../shared/widgets/craft_icon.dart';

/// Shown on Sell before the first listing: every product belongs to a STORE,
/// so the user opens one first (this also makes them a SELLER, unverified).
class OpenStoreForm extends ConsumerStatefulWidget {
  const OpenStoreForm({super.key, required this.onOpened});

  /// Called with the new store_id.
  final ValueChanged<String> onOpened;

  @override
  ConsumerState<OpenStoreForm> createState() => _OpenStoreFormState();
}

class _OpenStoreFormState extends ConsumerState<OpenStoreForm> {
  final _form = GlobalKey<FormState>();
  late final _user = ref.read(authProvider)!;
  late final _name = TextEditingController();
  late final _desc = TextEditingController(text: _user.bio);
  final _address = TextEditingController();
  late final _city = TextEditingController(text: _user.location == _user.country ? '' : _user.location);
  final _postal = TextEditingController();
  final _capacity = TextEditingController(text: '10');
  bool _busy = false;

  @override
  void dispose() {
    for (final c in [_name, _desc, _address, _city, _postal, _capacity]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    if (!_form.currentState!.validate()) return;
    setState(() => _busy = true);
    try {
      final repo = ref.read(listingRepositoryProvider);
      // Already opened (e.g. on another phone)? Use that store instead of failing.
      final storeId = await repo.findMyStoreId(_user.id) ??
          await repo.openStore(
            _user.id,
            StoreInput(
              storeName: _name.text.trim(),
              description: _desc.text.trim(),
              address: _address.text.trim(),
              city: _city.text.trim(),
              postalCode: _postal.text.trim(),
              weeklyCapacity: int.parse(_capacity.text.trim()),
            ),
          );
      // My store's profile card reads the description and city from the store.
      ref.read(authProvider.notifier).updateProfile(_user.copyWith(bio: _desc.text.trim(), location: _city.text.trim()));
      if (!mounted) return;
      showMessage(context, 'Your store is open. Now add your first item.');
      widget.onOpened(storeId);
    } on AppFailure catch (e) {
      if (mounted) showMessage(context, e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final digits = [FilteringTextInputFormatter.digitsOnly];
    return Form(
      key: _form,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(color: AppColors.clayTint, borderRadius: BorderRadius.circular(14)),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const CraftIcon(CraftIcons.store, size: 22, color: AppColors.clayText),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Before you post your first item, tell buyers about your store. You only do this once.',
                style: AppText.body.copyWith(fontSize: 13.5),
              ),
            ),
          ]),
        ),
        const SizedBox(height: 16),
        LabeledField(
          label: 'Store name',
          controller: _name,
          hint: 'Ana Makes Crochet',
          maxLength: 100,
          validator: (v) => (v ?? '').trim().length < 2 ? 'Enter a store name.' : null,
        ),
        LabeledField(
          label: 'Store description (optional)',
          controller: _desc,
          hint: 'What do you make? How long do orders take?',
          maxLines: 3,
          maxLength: 500,
        ),
        LabeledField(
          label: 'Address',
          controller: _address,
          icon: CraftIcons.pin,
          hint: '12 Mango Avenue',
          validator: (v) {
            final t = (v ?? '').trim();
            if (t.isEmpty) return 'Enter your street address.';
            if (t.length > 255) return 'Keep it under 255 characters.';
            return null;
          },
        ),
        const SizedBox(height: 12),
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
            flex: 3,
            child: LabeledField(
              label: 'City',
              controller: _city,
              hint: 'Cebu City',
              validator: (v) {
                final t = (v ?? '').trim();
                if (t.isEmpty) return 'Enter your city.';
                if (t.length > 50) return 'Too long.';
                return null;
              },
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            flex: 2,
            child: LabeledField(
              label: 'Postal code',
              controller: _postal,
              hint: '6000',
              keyboardType: TextInputType.number,
              inputFormatters: [...digits, LengthLimitingTextInputFormatter(4)],
              validator: (v) => RegExp(r'^[0-9]{4}$').hasMatch((v ?? '').trim()) ? null : 'Enter 4 digits.',
            ),
          ),
        ]),
        const SizedBox(height: 12),
        LabeledField(
          label: 'Orders you can take per week',
          controller: _capacity,
          keyboardType: TextInputType.number,
          inputFormatters: digits,
          helper: 'Buyers are told when you are fully booked.',
          validator: (v) {
            final n = int.tryParse((v ?? '').trim());
            if (n == null || n < 1 || n > 500) return 'Enter 1 to 500.';
            return null;
          },
        ),
        const SizedBox(height: 14),
        const InfoNote('Your address is shown only to the other person in an order.'),
        const SizedBox(height: 18),
        AppButton(label: 'Open my store', icon: CraftIcons.check, onPressed: _submit, loading: _busy),
      ]),
    );
  }
}

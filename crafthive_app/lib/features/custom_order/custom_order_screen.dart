import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/format.dart';
import '../../data/providers.dart';
import '../../shared/widgets/action_helpers.dart';
import '../../shared/widgets/common.dart';
import '../../shared/widgets/craft_icon.dart';
import '../../shared/widgets/product_widgets.dart';

/// Screen 6 – Custom order request: what to customize, seller options,
/// quantity, budget, needed-by date and a reference photo.
class CustomOrderScreen extends ConsumerStatefulWidget {
  const CustomOrderScreen({super.key, required this.productId});
  final String productId;
  @override
  ConsumerState<CustomOrderScreen> createState() => _CustomOrderScreenState();
}

class _CustomOrderScreenState extends ConsumerState<CustomOrderScreen> {
  final _form = GlobalKey<FormState>();
  final _desc = TextEditingController();
  final _budget = TextEditingController();
  final Set<String> _options = {};
  int _qty = 1;
  DateTime? _neededBy;
  PickedImage? _photo;
  bool _busy = false;
  bool _dateError = false;

  @override
  void dispose() {
    _desc.dispose();
    _budget.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final d = await showDatePicker(
      context: context,
      initialDate: _neededBy ?? now.add(const Duration(days: 14)),
      firstDate: now.add(const Duration(days: 1)),
      lastDate: now.add(const Duration(days: 365)),
      helpText: 'Needed by',
    );
    if (d != null) setState(() {
      _neededBy = d;
      _dateError = false;
    });
  }

  Future<void> _addPhoto() async {
    final photo = await pickOnePhoto(context);
    if (photo != null && mounted) setState(() => _photo = photo);
  }

  Future<void> _send() async {
    FocusScope.of(context).unfocus();
    final ok = _form.currentState!.validate();
    setState(() => _dateError = _neededBy == null);
    if (!ok || _neededBy == null) return;
    setState(() => _busy = true);
    final budget = double.tryParse(_budget.text.replaceAll(RegExp(r'[^0-9.]'), ''));
    try {
      final code = await ref.read(customOrderActionsProvider).submit(CustomRequestInput(
            productId: widget.productId,
            description: _desc.text.trim(),
            options: _options.toList(),
            quantity: _qty,
            neededBy: _neededBy!,
            budget: budget,
            photo: _photo,
          ));
      if (!mounted) return;
      context.pushReplacement('/request-sent/$code');
    } on AppFailure catch (e) {
      if (mounted) showMessage(context, e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = ref.watch(productProvider(widget.productId));
    if (p == null) return const Scaffold(appBar: ScreenHeader(title: 'Custom order'), body: SizedBox());
    final seller = ref.watch(sellerProvider(p.sellerId));

    return Scaffold(
      appBar: const ScreenHeader(title: 'Custom order'),
      body: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(Insets.screen, 4, Insets.screen, 28),
          child: ResponsiveCenter(
            child: Form(
              key: _form,
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                ProductSummaryRow(product: p, title: p.title, subtitle: '${seller?.name ?? 'Maker'} · base price ${Fmt.peso(p.price)}'),
                const SizedBox(height: 16),
                LabeledField(
                  label: 'What do you want customized?',
                  controller: _desc,
                  hint: 'Example: Engrave "Lola Nena" on the handle. Make a set of 3 in small, medium and large.',
                  maxLines: 4,
                  maxLength: 500,
                  validator: (v) => (v ?? '').trim().length < 10 ? 'Describe your request in at least 10 characters.' : null,
                ),
                const SizedBox(height: 8),
                Semantics(header: true, child: Text('Options offered by this seller', style: AppText.label)),
                const SizedBox(height: 8),
                Wrap(spacing: 8, runSpacing: 8, children: [
                  for (final o in p.customOptions)
                    AppChip(
                      label: o,
                      icon: _options.contains(o) ? CraftIcons.check : null,
                      selected: _options.contains(o),
                      onTap: () => setState(() => _options.contains(o) ? _options.remove(o) : _options.add(o)),
                    ),
                ]),
                const SizedBox(height: 16),
                Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('Quantity', style: AppText.label),
                      const SizedBox(height: 6),
                      QuantityStepper(value: _qty, onChanged: (v) => setState(() => _qty = v)),
                    ]),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: LabeledField(
                      label: 'Budget (optional)',
                      controller: _budget,
                      hint: '1,200',
                      prefixText: '₱ ',
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      validator: (v) {
                        if ((v ?? '').trim().isEmpty) return null;
                        final n = double.tryParse(v!.replaceAll(',', ''));
                        return n == null || n <= 0 ? 'Enter an amount.' : null;
                      },
                    ),
                  ),
                ]),
                const SizedBox(height: 14),
                Text('Needed by', style: AppText.label),
                const SizedBox(height: 6),
                _DateField(value: _neededBy, onTap: _pickDate, error: _dateError),
                const SizedBox(height: 14),
                Text('Reference photo (optional)', style: AppText.label),
                const SizedBox(height: 6),
                if (_photo != null)
                  Container(
                    height: 64,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    decoration: BoxDecoration(color: AppColors.white, borderRadius: Radii.field, border: Border.all(color: AppColors.linen, width: 1.5)),
                    child: Row(children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Image.memory(_photo!.bytes, width: 44, height: 44, fit: BoxFit.cover),
                      ),
                      const SizedBox(width: 10),
                      Expanded(child: Text(_photo!.fileName, style: AppText.label, maxLines: 1, overflow: TextOverflow.ellipsis)),
                      IconButton(tooltip: 'Remove photo', onPressed: () => setState(() => _photo = null), icon: const CraftIcon(CraftIcons.close, size: 18, color: AppColors.grayBrown)),
                    ]),
                  )
                else
                  DashedAddBox(label: 'Add a photo', onTap: _addPhoto),
                const SizedBox(height: 16),
                const InfoNote('The seller reviews your request and replies with a price. You pay only after you accept the quote.'),
                const SizedBox(height: 18),
                AppButton(label: 'Send request', icon: CraftIcons.send, onPressed: _send, loading: _busy),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

class _DateField extends StatelessWidget {
  const _DateField({required this.value, required this.onTap, required this.error});
  final DateTime? value;
  final VoidCallback onTap;
  final bool error;
  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Semantics(
          button: true,
          label: value == null ? 'Choose the date you need it by' : 'Needed by ${Fmt.date(value!)}. Change date',
          excludeSemantics: true,
          child: Material(
            color: AppColors.white,
            shape: RoundedRectangleBorder(borderRadius: Radii.field, side: BorderSide(color: error ? AppColors.brick : AppColors.linen, width: 1.5)),
            child: InkWell(
              borderRadius: Radii.field,
              onTap: onTap,
              child: SizedBox(
                height: Insets.fieldHeight,
                child: Row(children: [
                  const SizedBox(width: 14),
                  const CraftIcon(CraftIcons.calendar, size: 18, color: AppColors.grayBrown),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(value == null ? 'Choose a date' : Fmt.date(value!),
                        style: AppText.body.copyWith(fontSize: 15, color: value == null ? AppColors.grayBrown : AppColors.darkCocoa)),
                  ),
                  const CraftIcon(CraftIcons.chevronDown, size: 18, color: AppColors.grayBrown),
                  const SizedBox(width: 14),
                ]),
              ),
            ),
          ),
        ),
        if (error)
          Padding(
            padding: const EdgeInsets.only(top: 6, left: 12),
            child: Text('Choose the date you need it by.', style: AppText.caption.copyWith(color: AppColors.brick)),
          ),
      ]);
}


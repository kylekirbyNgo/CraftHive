import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../data/models.dart';
import '../../data/providers.dart';
import '../../data/sample_ids.dart';
import '../../shared/widgets/common.dart';
import '../../shared/widgets/craft_icon.dart';

/// Screen 11 – New listing (Sell) and Edit listing: up to 5 photos, title,
/// category, price, stock, made-to-order days, description, and custom order options.
class NewListingScreen extends ConsumerStatefulWidget {
  const NewListingScreen({super.key, this.editId});
  final String? editId;
  @override
  ConsumerState<NewListingScreen> createState() => _NewListingScreenState();
}

class _NewListingScreenState extends ConsumerState<NewListingScreen> {
  final _form = GlobalKey<FormState>();
  final _title = TextEditingController();
  final _price = TextEditingController();
  final _stock = TextEditingController(text: '1');
  final _lead = TextEditingController(text: '0');
  final _desc = TextEditingController();
  String? _category;
  int _photos = 0;
  bool _custom = false;
  final List<String> _options = ['Color', 'Size'];
  final Set<String> _on = {};
  bool _busy = false;
  bool _photoError = false;
  Product? _editing;

  bool get _isEdit => widget.editId != null;

  @override
  void initState() {
    super.initState();
    if (_isEdit) {
      final p = ref.read(productProvider(widget.editId!));
      if (p != null) {
        _editing = p;
        _title.text = p.title;
        _price.text = p.price.toStringAsFixed(0);
        _stock.text = '${p.stock}';
        _lead.text = '${p.leadDays}';
        _desc.text = p.description;
        _category = p.categoryId;
        _photos = p.photoCount;
        _custom = p.acceptsCustom;
        _options
          ..clear()
          ..addAll(p.customOptions.isEmpty ? ['Color', 'Size'] : p.customOptions);
        _on.addAll(p.customOptions);
      }
    }
  }

  @override
  void dispose() {
    for (final c in [_title, _price, _stock, _lead, _desc]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _addOption() async {
    final ctrl = TextEditingController();
    final v = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.warmCream,
        title: Text('Add an option', style: AppText.screenTitle),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(hintText: 'e.g. Name tag, Scent, Engraving'),
          onSubmitted: (t) => Navigator.pop(ctx, t),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(ctx, ctrl.text), child: const Text('Add')),
        ],
      ),
    );
    final t = v?.trim() ?? '';
    if (t.isNotEmpty && !_options.contains(t)) {
      setState(() {
        _options.add(t);
        _on.add(t);
      });
    }
  }

  Future<void> _publish() async {
    FocusScope.of(context).unfocus();
    final ok = _form.currentState!.validate();
    setState(() => _photoError = _photos == 0);
    if (!ok || _photos == 0) return;
    setState(() => _busy = true);
    await Future<void>.delayed(const Duration(milliseconds: 700));
    final p = Product(
      id: _editing?.id ?? 'my-${DateTime.now().millisecondsSinceEpoch}',
      title: _title.text.trim(),
      sellerId: 'me',
      categoryId: _category!,
      price: double.parse(_price.text.replaceAll(',', '')),
      stock: int.tryParse(_stock.text) ?? 0,
      leadDays: int.tryParse(_lead.text) ?? 0,
      description: _desc.text.trim(),
      acceptsCustom: _custom,
      customOptions: _custom ? _options.where(_on.contains).toList() : const [],
      photoCount: _photos,
      rating: _editing?.rating ?? 0,
      sold: _editing?.sold ?? 0,
    );
    final catalog = ref.read(catalogProvider.notifier);
    if (_isEdit) {
      catalog.replace(p);
    } else {
      catalog.add(p);
    }
    if (!mounted) return;
    showMessage(context, _isEdit ? 'Listing updated.' : 'Listing published. Buyers can find it now.');
    context.pushReplacement('/store');
  }

  @override
  Widget build(BuildContext context) {
    final categories = ref.watch(categoriesProvider);
    return Scaffold(
      appBar: ScreenHeader(
        title: _isEdit ? 'Edit listing' : 'New listing',
        trailing: _isEdit
            ? null
            : OutlinedButton(
                onPressed: () => showMessage(context, 'Draft saved on this phone.'),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(0, 40),
                  foregroundColor: AppColors.darkCocoa,
                  backgroundColor: AppColors.white,
                  side: const BorderSide(color: AppColors.linen, width: 1.5),
                  shape: const StadiumBorder(),
                  textStyle: AppText.label.copyWith(fontWeight: FontWeight.w700),
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                ),
                child: const Text('Save draft'),
              ),
      ),
      body: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(Insets.screen, 4, Insets.screen, 28),
          child: ResponsiveCenter(
            child: Form(
              key: _form,
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Text('Photos ($_photos of 5)', style: AppText.label),
                const SizedBox(height: 6),
                SizedBox(
                  height: 84,
                  child: ListView(scrollDirection: Axis.horizontal, children: [
                    if (_photos < 5)
                      DashedAddBox(label: 'Add photo', width: 84, height: 84, vertical: true, onTap: () => setState(() {
                        _photos++;
                        _photoError = false;
                      })),
                    for (var i = 0; i < _photos; i++) ...[
                      const SizedBox(width: 10),
                      _PhotoThumb(index: i, categoryId: _category, onRemove: () => setState(() => _photos--)),
                    ],
                  ]),
                ),
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    _photoError ? 'Add at least one photo.' : 'The first photo is the cover. Photos are compressed before upload.',
                    style: AppText.caption.copyWith(color: _photoError ? AppColors.brick : AppColors.grayBrown),
                  ),
                ),
                const SizedBox(height: 14),
                LabeledField(
                  label: 'Title',
                  controller: _title,
                  hint: 'Crochet Tote Bag, Sage',
                  maxLength: 120,
                  validator: (v) => (v ?? '').trim().length < 3 ? 'Enter a title of at least 3 characters.' : null,
                ),
                Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('Category', style: AppText.label),
                      const SizedBox(height: 6),
                      DropdownButtonFormField<String>(
                        value: _category,
                        isExpanded: true,
                        hint: Text('Choose', style: AppText.body.copyWith(color: AppColors.grayBrown)),
                        icon: const CraftIcon(CraftIcons.chevronDown, size: 18, color: AppColors.grayBrown),
                        style: AppText.body.copyWith(fontSize: 15),
                        borderRadius: Radii.field,
                        dropdownColor: AppColors.white,
                        items: [for (final c in categories) DropdownMenuItem(value: c.id, child: Text(c.name, overflow: TextOverflow.ellipsis))],
                        onChanged: (v) => setState(() => _category = v),
                        validator: (v) => v == null ? 'Pick a category.' : null,
                      ),
                    ]),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: LabeledField(
                      label: 'Price',
                      controller: _price,
                      hint: '680',
                      prefixText: '₱ ',
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      validator: (v) {
                        final n = double.tryParse((v ?? '').replaceAll(',', ''));
                        if (n == null || n <= 0) return 'Enter a price.';
                        if (n > 100000) return 'Max ₱100,000.';
                        return null;
                      },
                    ),
                  ),
                ]),
                const SizedBox(height: 12),
                Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Expanded(
                    child: LabeledField(
                      label: 'Stock',
                      controller: _stock,
                      keyboardType: TextInputType.number,
                      helper: 'Pieces ready now',
                      validator: (v) => int.tryParse(v ?? '') == null ? 'Enter 0 or more.' : null,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: LabeledField(
                      label: 'Made-to-order days',
                      controller: _lead,
                      keyboardType: TextInputType.number,
                      helper: '0 if ready-made only',
                      validator: (v) {
                        final n = int.tryParse(v ?? '');
                        if (n == null || n < 0 || n > 90) return 'Enter 0 to 90.';
                        if (n == 0 && (int.tryParse(_stock.text) ?? 0) == 0) return 'Add stock or days.';
                        return null;
                      },
                    ),
                  ),
                ]),
                const SizedBox(height: 12),
                LabeledField(
                  label: 'Description',
                  controller: _desc,
                  hint: 'Materials, size, colors, and how long it takes to make.',
                  maxLines: 4,
                  maxLength: 2000,
                  validator: (v) => (v ?? '').trim().length < 10 ? 'Describe the item in a few words.' : null,
                ),
                Container(
                  padding: const EdgeInsets.fromLTRB(14, 6, 10, 12),
                  decoration: BoxDecoration(color: AppColors.clayTint, borderRadius: BorderRadius.circular(14)),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text('Accept custom orders', style: AppText.bodyStrong),
                      subtitle: Text('Buyers can request changes and you reply with a quote.', style: AppText.caption),
                      value: _custom,
                      onChanged: (v) => setState(() => _custom = v),
                    ),
                    AnimatedSize(
                      duration: const Duration(milliseconds: 200),
                      child: !_custom
                          ? const SizedBox(width: double.infinity)
                          : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Text('Options buyers can ask for', style: AppText.label),
                              const SizedBox(height: 8),
                              Wrap(spacing: 8, runSpacing: 8, children: [
                                for (final o in _options)
                                  AppChip(
                                    label: o,
                                    color: AppColors.clay,
                                    icon: _on.contains(o) ? CraftIcons.check : null,
                                    selected: _on.contains(o),
                                    onTap: () => setState(() => _on.contains(o) ? _on.remove(o) : _on.add(o)),
                                  ),
                                AppChip(label: 'Add option', icon: CraftIcons.plus, color: AppColors.clay, onTap: _addOption),
                              ]),
                            ]),
                    ),
                  ]),
                ),
                const SizedBox(height: 20),
                AppButton(label: _isEdit ? 'Save changes' : 'Publish listing', icon: CraftIcons.check, onPressed: _publish, loading: _busy),
                if (_isEdit) ...[
                  const SizedBox(height: 10),
                  AppButton(
                    label: 'Archive listing',
                    kind: ButtonKind.danger,
                    onPressed: () async {
                      final yes = await showDialog<bool>(
                        context: context,
                        builder: (ctx) => AlertDialog(
                          backgroundColor: AppColors.warmCream,
                          title: Text('Archive this listing?', style: AppText.screenTitle),
                          content: Text('It disappears from search. Past orders keep their records.', style: AppText.body),
                          actions: [
                            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
                            TextButton(onPressed: () => Navigator.pop(ctx, true), style: TextButton.styleFrom(foregroundColor: AppColors.brick), child: const Text('Archive')),
                          ],
                        ),
                      );
                      if (yes == true && _editing != null && context.mounted) {
                        ref.read(catalogProvider.notifier).replace(_editing!.copyWith(status: ListingStatus.archived));
                        showMessage(context, 'Listing archived.');
                        context.pop();
                      }
                    },
                  ),
                ],
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

class _PhotoThumb extends ConsumerWidget {
  const _PhotoThumb({required this.index, required this.categoryId, required this.onRemove});
  final int index;
  final String? categoryId;
  final VoidCallback onRemove;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cat = ref.watch(categoryProvider(categoryId ?? SampleIds.catCrochet));
    return Stack(children: [
      Container(
        width: 84,
        height: 84,
        decoration: BoxDecoration(color: Color.lerp(cat.tint, AppColors.white, index * 0.1), borderRadius: BorderRadius.circular(14)),
        alignment: Alignment.center,
        child: CraftIcon(cat.icon, size: 34, color: cat.ink, strokeWidth: 1.5, semanticLabel: 'Photo ${index + 1}'),
      ),
      if (index == 0)
        Positioned(
          left: 6,
          bottom: 6,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(color: AppColors.darkCocoa.withValues(alpha: 0.75), borderRadius: Radii.pill),
            child: Text('Cover', style: AppText.small.copyWith(color: AppColors.white, fontSize: 10)),
          ),
        ),
      Positioned(
        top: 4,
        right: 4,
        child: Semantics(
          button: true,
          label: 'Remove photo ${index + 1}',
          excludeSemantics: true,
          child: InkResponse(
            onTap: onRemove,
            radius: 18,
            child: Container(
              width: 24,
              height: 24,
              decoration: const BoxDecoration(color: AppColors.darkCocoa, shape: BoxShape.circle),
              alignment: Alignment.center,
              child: const CraftIcon(CraftIcons.close, size: 13, color: AppColors.white, strokeWidth: 2.6),
            ),
          ),
        ),
      ),
    ]);
  }
}


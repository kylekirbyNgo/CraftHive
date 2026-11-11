import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../data/models.dart';
import '../../data/providers.dart';
import '../../shared/widgets/common.dart';
import '../../shared/widgets/craft_icon.dart';
import 'open_store_form.dart';

/// Screen 11 – New listing (Sell) and Edit listing: up to 5 photos, title,
/// category, price, stock, made-to-order days, description, and custom order options.
/// Saves to PostgreSQL (PRODUCT, PRODUCT_IMAGE, PRODUCT_CUSTOM_OPTION) and the
/// product-images Storage bucket. Users without a store open one here first.
class NewListingScreen extends ConsumerStatefulWidget {
  const NewListingScreen({super.key, this.editId});
  final String? editId;
  @override
  ConsumerState<NewListingScreen> createState() => _NewListingScreenState();
}

enum _Saving { none, publish, draft, archive }

const _maxPhotos = 5;
const _maxPhotoBytes = 5 * 1024 * 1024; // product-images bucket limit

class _NewListingScreenState extends ConsumerState<NewListingScreen> {
  final _form = GlobalKey<FormState>();
  final _title = TextEditingController();
  final _price = TextEditingController();
  final _stock = TextEditingController(text: '1');
  final _lead = TextEditingController(text: '3');
  final _desc = TextEditingController();
  String? _category;
  final List<ListingPhoto> _photos = [];
  bool _custom = false;
  final List<String> _options = ['Color', 'Size'];
  final Set<String> _on = {};
  _Saving _saving = _Saving.none;
  bool _photoError = false;
  Product? _editing;

  /// Saving a draft skips the photo and description checks.
  bool _draftCheck = false;

  /// Store opened on this screen, used until the catalog reload confirms it.
  String? _openedStoreId;

  bool get _isEdit => widget.editId != null;
  bool get _editingDraft => _editing?.status == ListingStatus.hidden;
  bool get _busy => _saving != _Saving.none;

  @override
  void initState() {
    super.initState();
    if (_isEdit) {
      final p = ref.read(productProvider(widget.editId!));
      if (p != null) {
        _editing = p;
        _title.text = p.title;
        _price.text = p.price == p.price.roundToDouble() ? p.price.toStringAsFixed(0) : p.price.toStringAsFixed(2);
        _stock.text = '${p.stock}';
        _lead.text = '${p.leadDays}';
        _desc.text = p.description;
        _category = p.categoryId;
        for (var i = 0; i < p.imagePaths.length && i < p.imageUrls.length; i++) {
          _photos.add(ListingPhoto.stored(path: p.imagePaths[i], url: p.imageUrls[i]));
        }
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

  // -------------------------------------------------------------------------
  // Photos
  // -------------------------------------------------------------------------
  Future<void> _addPhotos() async {
    final left = _maxPhotos - _photos.length;
    if (left <= 0) return;
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(
            leading: const CraftIcon(CraftIcons.image, size: 22, color: AppColors.darkCocoa),
            title: Text('Choose from gallery', style: AppText.bodyStrong),
            subtitle: Text('Up to $left more', style: AppText.caption),
            onTap: () => Navigator.pop(ctx, ImageSource.gallery),
          ),
          ListTile(
            leading: const CraftIcon(CraftIcons.camera, size: 22, color: AppColors.darkCocoa),
            title: Text('Take a photo', style: AppText.bodyStrong),
            onTap: () => Navigator.pop(ctx, ImageSource.camera),
          ),
          const SizedBox(height: 8),
        ]),
      ),
    );
    if (source == null) return;

    // The picker resizes and compresses, so uploads stay small.
    final picker = ImagePicker();
    List<XFile> files;
    try {
      if (source == ImageSource.camera || left == 1) {
        final f = await picker.pickImage(source: source, maxWidth: 1600, maxHeight: 1600, imageQuality: 82);
        files = f == null ? const [] : [f];
      } else {
        files = await picker.pickMultiImage(maxWidth: 1600, maxHeight: 1600, imageQuality: 82, limit: left);
      }
    } catch (e) {
      debugPrint('CraftHive listing: photo picker failed: $e');
      if (mounted) showMessage(context, "We couldn't open your photos. Allow CraftHive to use the camera and photos, then try again.");
      return;
    }

    final added = <ListingPhoto>[];
    var tooBig = 0;
    for (final f in files.take(left)) {
      final bytes = await f.readAsBytes();
      if (bytes.lengthInBytes > _maxPhotoBytes) {
        tooBig++;
        continue;
      }
      added.add(ListingPhoto.picked(bytes: bytes, fileName: f.name));
    }
    if (!mounted) return;
    setState(() {
      _photos.addAll(added);
      if (_photos.isNotEmpty) _photoError = false;
    });
    if (tooBig > 0) showMessage(context, tooBig == 1 ? 'One photo is over 5 MB and was skipped.' : '$tooBig photos are over 5 MB and were skipped.');
    if (files.length > left) showMessage(context, 'Only $_maxPhotos photos per listing. The first ones you picked were added.');
  }

  void _makeCover(int i) {
    if (i == 0) return;
    setState(() => _photos.insert(0, _photos.removeAt(i)));
  }

  // -------------------------------------------------------------------------
  // Custom options
  // -------------------------------------------------------------------------
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
          maxLength: 50,
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
    ctrl.dispose();
    final t = v?.trim() ?? '';
    if (t.isNotEmpty && !_options.any((o) => o.toLowerCase() == t.toLowerCase())) {
      setState(() {
        _options.add(t);
        _on.add(t);
      });
    }
  }

  // -------------------------------------------------------------------------
  // Saving
  // -------------------------------------------------------------------------
  String? get _storeId => ref.read(myStoreIdProvider) ?? _openedStoreId;

  /// Reloads Home, Search and My store from the database so the change shows everywhere.
  Future<void> _reloadCatalog() async {
    try {
      ref.invalidate(catalogDataProvider);
      await ref.read(catalogDataProvider.future);
    } catch (_) {
      // Saved anyway; pulling down on Home loads it later.
    }
  }

  Future<void> _save({required bool draft}) async {
    FocusScope.of(context).unfocus();
    _draftCheck = draft;
    final ok = _form.currentState!.validate();
    final needsPhoto = !draft && _photos.isEmpty;
    setState(() => _photoError = needsPhoto);
    if (!ok || needsPhoto) return;
    final storeId = _storeId;
    if (storeId == null) {
      showMessage(context, "We couldn't find your store. Go back and try again.");
      return;
    }

    setState(() => _saving = draft ? _Saving.draft : _Saving.publish);
    final options = _custom ? _options.where(_on.contains).toList() : const <String>[];
    final input = ListingInput(
      title: _title.text.trim(),
      categoryId: _category!,
      price: double.parse(_price.text.replaceAll(',', '').trim()),
      stock: int.parse(_stock.text.trim()),
      leadDays: int.parse(_lead.text.trim()),
      description: _desc.text.trim(),
      acceptsCustom: _custom,
      customOptions: options,
      photos: List.of(_photos),
      isDraft: draft,
    );
    final wasActive = _editing != null && !_editingDraft;
    try {
      final repo = ref.read(listingRepositoryProvider);
      final editing = _editing;
      if (editing == null) {
        await repo.createListing(storeId: storeId, input: input);
      } else {
        await repo.updateListing(
          storeId: storeId,
          productId: editing.id,
          input: input,
          previousPaths: editing.imagePaths,
          previousOptions: editing.customOptions,
        );
      }
      await _reloadCatalog();
      if (!mounted) return;
      showMessage(
        context,
        draft
            ? 'Draft saved. Only you can see it, in My store.'
            : wasActive
                ? 'Listing updated.'
                : 'Listing published. Buyers can find it now.',
      );
      if (_isEdit && context.canPop()) {
        context.pop();
      } else {
        context.pushReplacement('/store');
      }
    } on AppFailure catch (e) {
      if (mounted) showMessage(context, "Couldn't save the listing. ${e.message}");
    } finally {
      if (mounted) setState(() => _saving = _Saving.none);
    }
  }

  Future<void> _archive() async {
    final editing = _editing;
    if (editing == null) return;
    final yes = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.warmCream,
        title: Text('Archive this listing?', style: AppText.screenTitle),
        content: Text('It disappears from Home, search and your store. Past orders keep their records.', style: AppText.body),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), style: TextButton.styleFrom(foregroundColor: AppColors.brick), child: const Text('Archive')),
        ],
      ),
    );
    if (yes != true || !mounted) return;
    setState(() => _saving = _Saving.archive);
    try {
      await ref.read(listingRepositoryProvider).archiveListing(editing.id);
      await _reloadCatalog();
      if (!mounted) return;
      showMessage(context, 'Listing archived.');
      context.canPop() ? context.pop() : context.go('/store');
    } on AppFailure catch (e) {
      if (mounted) showMessage(context, "Couldn't archive the listing. ${e.message}");
    } finally {
      if (mounted) setState(() => _saving = _Saving.none);
    }
  }

  // -------------------------------------------------------------------------
  // UI
  // -------------------------------------------------------------------------
  @override
  Widget build(BuildContext context) {
    final catalog = ref.watch(catalogDataProvider);
    final storeId = ref.watch(myStoreIdProvider) ?? _openedStoreId;

    // No store yet: open one before the first listing.
    if (!_isEdit && storeId == null) {
      final Widget body;
      if (catalog.isLoading && !catalog.hasValue) {
        body = const Padding(
          padding: EdgeInsets.only(top: 80),
          child: Center(child: CircularProgressIndicator(color: AppColors.moss)),
        );
      } else if (catalog.hasError && !catalog.hasValue) {
        body = EmptyState(
          icon: CraftIcons.info,
          title: "We couldn't load your store",
          message: catalog.error is AppFailure ? (catalog.error! as AppFailure).message : 'Please check your connection and try again.',
          actionLabel: 'Try again',
          onAction: () => ref.invalidate(catalogDataProvider),
        );
      } else {
        body = OpenStoreForm(onOpened: (id) {
          setState(() => _openedStoreId = id);
          _reloadCatalog();
        });
      }
      return Scaffold(
        appBar: const ScreenHeader(title: 'Open your store'),
        body: SafeArea(
          top: false,
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(Insets.screen, 4, Insets.screen, 28),
            child: ResponsiveCenter(child: body),
          ),
        ),
      );
    }

    final categories = ref.watch(categoriesProvider);
    final showDraftButton = !_isEdit || _editingDraft;
    return Scaffold(
      appBar: ScreenHeader(
        title: _isEdit ? 'Edit listing' : 'New listing',
        fallback: _isEdit ? '/store' : '/home',
        trailing: !showDraftButton
            ? null
            : OutlinedButton(
                onPressed: _busy ? null : () => _save(draft: true),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(0, 40),
                  foregroundColor: AppColors.darkCocoa,
                  backgroundColor: AppColors.white,
                  side: const BorderSide(color: AppColors.linen, width: 1.5),
                  shape: const StadiumBorder(),
                  textStyle: AppText.label.copyWith(fontWeight: FontWeight.w700),
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                ),
                child: _saving == _Saving.draft
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.darkCocoa))
                    : const Text('Save draft'),
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
                Text('Photos (${_photos.length} of $_maxPhotos)', style: AppText.label),
                const SizedBox(height: 6),
                SizedBox(
                  height: 84,
                  child: ListView(scrollDirection: Axis.horizontal, children: [
                    if (_photos.length < _maxPhotos) DashedAddBox(label: 'Add photo', width: 84, height: 84, vertical: true, onTap: _busy ? () {} : _addPhotos),
                    for (var i = 0; i < _photos.length; i++) ...[
                      const SizedBox(width: 10),
                      _PhotoThumb(
                        photo: _photos[i],
                        index: i,
                        onRemove: _busy ? null : () => setState(() => _photos.removeAt(i)),
                        onMakeCover: _busy ? null : () => _makeCover(i),
                      ),
                    ],
                  ]),
                ),
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    _photoError ? 'Add at least one photo.' : 'The first photo is the cover. Tap a photo to make it the cover.',
                    style: AppText.caption.copyWith(color: _photoError ? AppColors.brick : AppColors.grayBrown),
                  ),
                ),
                const SizedBox(height: 14),
                LabeledField(
                  label: 'Title',
                  controller: _title,
                  hint: 'Crochet Tote Bag, Sage',
                  maxLength: 100,
                  validator: (v) => (v ?? '').trim().length < 3 ? 'Enter a title of at least 3 characters.' : null,
                ),
                Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('Category', style: AppText.label),
                      const SizedBox(height: 6),
                      DropdownButtonFormField<String>(
                        initialValue: categories.any((c) => c.id == _category) ? _category : null,
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
                        final n = double.tryParse((v ?? '').replaceAll(',', '').trim());
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
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      helper: 'Pieces ready now (0 = made to order)',
                      validator: (v) {
                        final n = int.tryParse((v ?? '').trim());
                        if (n == null || n < 0) return 'Enter 0 or more.';
                        if (n > 100000) return 'Too many.';
                        return null;
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: LabeledField(
                      label: 'Days to make',
                      controller: _lead,
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      helper: 'How long a new piece takes',
                      validator: (v) {
                        final n = int.tryParse((v ?? '').trim());
                        if (n == null || n < 1 || n > 90) return 'Enter 1 to 90.';
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
                  validator: (v) => !_draftCheck && (v ?? '').trim().length < 10 ? 'Describe the item in a few words.' : null,
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
                AppButton(
                  label: _isEdit && !_editingDraft ? 'Save changes' : 'Publish listing',
                  icon: CraftIcons.check,
                  onPressed: _busy ? null : () => _save(draft: false),
                  loading: _saving == _Saving.publish,
                ),
                if (_isEdit && _editing != null) ...[
                  const SizedBox(height: 10),
                  AppButton(
                    label: 'Archive listing',
                    kind: ButtonKind.danger,
                    onPressed: _busy ? null : _archive,
                    loading: _saving == _Saving.archive,
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

class _PhotoThumb extends StatelessWidget {
  const _PhotoThumb({required this.photo, required this.index, required this.onRemove, required this.onMakeCover});
  final ListingPhoto photo;
  final int index;
  final VoidCallback? onRemove;
  final VoidCallback? onMakeCover;

  @override
  Widget build(BuildContext context) {
    final broken = Container(
      color: AppColors.lightSand,
      alignment: Alignment.center,
      child: const CraftIcon(CraftIcons.image, size: 28, color: AppColors.grayBrown),
    );
    final image = photo.isNew
        ? Image.memory(photo.bytes!, width: 84, height: 84, fit: BoxFit.cover, errorBuilder: (_, __, ___) => broken)
        : Image.network(photo.url!, width: 84, height: 84, fit: BoxFit.cover, errorBuilder: (_, __, ___) => broken);
    return Stack(children: [
      Semantics(
        button: index > 0,
        label: index == 0 ? 'Photo 1, cover' : 'Photo ${index + 1}. Tap to make it the cover',
        excludeSemantics: true,
        child: GestureDetector(
          onTap: onMakeCover,
          child: ClipRRect(borderRadius: BorderRadius.circular(14), child: SizedBox(width: 84, height: 84, child: image)),
        ),
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

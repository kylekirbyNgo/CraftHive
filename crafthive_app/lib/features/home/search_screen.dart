import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/format.dart';
import '../../core/utils/geo.dart';
import '../../data/providers.dart';
import '../../shared/widgets/common.dart';
import '../../shared/widgets/craft_icon.dart';
import '../../shared/widgets/product_widgets.dart';

/// Supporting screen – Search / Category results with typo-tolerant matching,
/// a filter sheet (price, custom orders, in stock, distance, deliver-by date)
/// and sorting.
class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key, this.initialQuery = '', this.categoryId});
  final String initialQuery;
  final String? categoryId;
  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  late final TextEditingController _q = TextEditingController(text: widget.initialQuery);
  late SearchFilters _f = SearchFilters(
    query: widget.initialQuery,
    categoryId: widget.categoryId,
    // Start from the city on the user's profile when it is one we know.
    nearCity: Geo.resolveCity(ref.read(authProvider)?.location ?? ''),
  );

  // Read once here because "ref" cannot be used any more in dispose().
  late final RecentSearchController _recent;
  String _saved = '';

  @override
  void initState() {
    super.initState();
    _recent = ref.read(recentSearchProvider.notifier);
  }

  @override
  void dispose() {
    // Most people read the results without pressing Enter, so the search is
    // also saved when they leave this screen.
    final term = _q.text.trim();
    if (term.length >= 2 && term.toLowerCase() != _saved) {
      final filters = _f;
      final recent = _recent;
      // After the screen is gone: changing a provider while widgets are being removed is not allowed.
      Future.microtask(() => recent.add(term, filters: filters));
    }
    _q.dispose();
    super.dispose();
  }

  void _save(String v) {
    final term = v.trim();
    if (term.isEmpty) return;
    _saved = term.toLowerCase();
    _recent.add(term, filters: _f);
  }

  void _submit(String v) {
    _save(v);
    setState(() => _f = _f.copyWith(query: v));
  }

  void _searchAgain(String term) {
    _q.text = term;
    _submit(term);
  }

  Future<void> _openFilters() async {
    final result = await showModalBottomSheet<SearchFilters>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _FilterSheet(initial: _f),
    );
    if (result != null) setState(() => _f = result);
  }

  Future<void> _openSort() async {
    final labels = {
      SortBy.relevance: 'Best match',
      SortBy.priceLow: 'Price: low to high',
      SortBy.priceHigh: 'Price: high to low',
      SortBy.rating: 'Top rated',
      if (_f.nearCity != null) SortBy.nearest: 'Nearest to ${_f.nearCity}',
    };
    final picked = await showModalBottomSheet<SortBy>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(Insets.screen, 0, Insets.screen, 8),
            child: Align(alignment: Alignment.centerLeft, child: Text('Sort by', style: AppText.screenTitle)),
          ),
          for (final e in labels.entries)
            ListTile(
              title: Text(e.value, style: AppText.body.copyWith(fontWeight: e.key == _f.sort ? FontWeight.w700 : FontWeight.w400)),
              trailing: e.key == _f.sort ? const CraftIcon(CraftIcons.check, size: 20, color: AppColors.moss, strokeWidth: 2.4) : null,
              onTap: () => Navigator.pop(ctx, e.key),
            ),
          const SizedBox(height: 8),
        ]),
      ),
    );
    if (picked != null) setState(() => _f = _f.copyWith(sort: picked));
  }

  @override
  Widget build(BuildContext context) {
    final categories = ref.watch(categoriesProvider);
    final results = searchProducts(ref.watch(catalogProvider), ref.watch(sellersProvider), _f, categories: categories);
    final title = _f.categoryId != null ? ref.watch(categoryProvider(_f.categoryId!)).name : 'Search';
    final recent = _q.text.trim().isEmpty ? ref.watch(recentSearchProvider) : const <String>[];

    return Scaffold(
      appBar: ScreenHeader(title: title),
      body: SafeArea(
        top: false,
        child: ResponsiveCenter(
          maxWidth: 900,
          child: CustomScrollView(slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(Insets.screen, 4, Insets.screen, 10),
                child: Row(children: [
                  Expanded(
                    child: TextField(
                      controller: _q,
                      autofocus: widget.initialQuery.isEmpty && widget.categoryId == null,
                      textInputAction: TextInputAction.search,
                      onSubmitted: _submit,
                      onChanged: (v) => setState(() => _f = _f.copyWith(query: v)),
                      style: AppText.body.copyWith(fontSize: 14.5),
                      decoration: InputDecoration(
                        hintText: 'Search crafts, shops or makers',
                        prefixIcon: const Padding(padding: EdgeInsets.only(left: 14, right: 10), child: CraftIcon(CraftIcons.search, size: 19, color: AppColors.grayBrown)),
                        prefixIconConstraints: const BoxConstraints(minWidth: 0, minHeight: 0),
                        suffixIcon: _q.text.isEmpty
                            ? null
                            : IconButton(
                                tooltip: 'Clear search',
                                onPressed: () => setState(() {
                                  _q.clear();
                                  _f = _f.copyWith(query: '');
                                }),
                                icon: const CraftIcon(CraftIcons.close, size: 18, color: AppColors.grayBrown),
                              ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Badge(
                    isLabelVisible: _f.activeCount > 0,
                    label: Text('${_f.activeCount}'),
                    backgroundColor: AppColors.brick,
                    child: RoundIconButton(icon: CraftIcons.filter, tooltip: 'Filters', background: AppColors.moss, color: AppColors.white, size: 44, onPressed: _openFilters),
                  ),
                ]),
              ),
            ),
            SliverToBoxAdapter(
              child: SizedBox(
                height: 40,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: Insets.screen),
                  children: [
                    AppChip(label: 'All', selected: _f.categoryId == null, onTap: () => setState(() => _f = _f.copyWith(clearCategory: true))),
                    for (final c in categories) ...[
                      const SizedBox(width: 8),
                      AppChip(label: c.name, selected: _f.categoryId == c.id, onTap: () => setState(() => _f = _f.copyWith(categoryId: c.id))),
                    ],
                  ],
                ),
              ),
            ),
            if (recent.isNotEmpty)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    SectionHeader('Recent searches', action: 'Clear all', onAction: _recent.clear),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: Insets.screen),
                      child: Wrap(spacing: 8, runSpacing: 8, children: [
                        for (final t in recent) _RecentSearchChip(text: t, onTap: () => _searchAgain(t), onRemove: () => _recent.remove(t)),
                      ]),
                    ),
                  ]),
                ),
              ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(Insets.screen, 12, 8, 6),
                child: Row(children: [
                  Expanded(child: Text(Fmt.count(results.length, 'item'), style: AppText.label.copyWith(color: AppColors.grayBrown))),
                  TextButton.icon(
                    onPressed: _openSort,
                    icon: const CraftIcon(CraftIcons.sort, size: 16, color: AppColors.moss),
                    label: const Text('Sort'),
                  ),
                ]),
              ),
            ),
            if (results.isEmpty)
              SliverToBoxAdapter(
                child: EmptyState(
                  icon: CraftIcons.search,
                  title: 'No items found',
                  message: 'Try another word, pick a different category, or clear the filters.',
                  actionLabel: 'Clear filters',
                  onAction: () => setState(() {
                    _q.clear();
                    _f = SearchFilters(nearCity: _f.nearCity);
                  }),
                ),
              )
            else
              SliverToBoxAdapter(child: ProductGrid(products: results)),
            const SliverToBoxAdapter(child: SizedBox(height: 32)),
          ]),
        ),
      ),
    );
  }
}

/// A recent search: tap to search again, ✕ to remove it.
class _RecentSearchChip extends StatelessWidget {
  const _RecentSearchChip({required this.text, required this.onTap, required this.onRemove});
  final String text;
  final VoidCallback onTap;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) => Material(
        color: AppColors.white,
        shape: const StadiumBorder(side: BorderSide(color: AppColors.linen)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          InkWell(
            customBorder: const StadiumBorder(),
            onTap: onTap,
            child: Semantics(
              button: true,
              label: 'Search again for $text',
              excludeSemantics: true,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 9, 4, 9),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  const CraftIcon(CraftIcons.clock, size: 15, color: AppColors.grayBrown),
                  const SizedBox(width: 6),
                  Text(text, style: AppText.body.copyWith(fontSize: 13)),
                ]),
              ),
            ),
          ),
          IconButton(
            tooltip: 'Remove $text',
            onPressed: onRemove,
            visualDensity: VisualDensity.compact,
            constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
            icon: const CraftIcon(CraftIcons.close, size: 14, color: AppColors.grayBrown),
          ),
        ]),
      );
}

class _FilterSheet extends StatefulWidget {
  const _FilterSheet({required this.initial});
  final SearchFilters initial;
  @override
  State<_FilterSheet> createState() => _FilterSheetState();
}

class _FilterSheetState extends State<_FilterSheet> {
  late SearchFilters f = widget.initial;

  static const _distances = <double?>[null, 10, 25, 50, 100, 300];

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final d = await showDatePicker(
      context: context,
      initialDate: f.neededBy ?? now.add(const Duration(days: 7)),
      firstDate: now,
      lastDate: now.add(const Duration(days: 365)),
      helpText: 'Needed by',
    );
    if (d != null) setState(() => f = f.copyWith(neededBy: d));
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(Insets.screen, 0, Insets.screen, 16),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Expanded(child: Text('Filters', style: AppText.screenTitle)),
            TextButton(onPressed: () => setState(() => f = f.reset()), child: const Text('Reset')),
          ]),
          const SizedBox(height: 10),
          Text('Maximum price: ${f.maxPrice >= anyPrice ? 'any' : Fmt.peso(f.maxPrice)}', style: AppText.label),
          Slider(
            value: f.maxPrice,
            min: 100,
            max: anyPrice,
            divisions: 19,
            label: f.maxPrice >= anyPrice ? 'Any' : Fmt.peso(f.maxPrice),
            onChanged: (v) => setState(() => f = f.copyWith(maxPrice: v)),
          ),
          const Divider(),
          const SizedBox(height: 6),
          Text('Your city', style: AppText.label),
          const SizedBox(height: 6),
          DropdownButtonFormField<String?>(
            initialValue: f.nearCity,
            isExpanded: true,
            menuMaxHeight: 360,
            decoration: const InputDecoration(
              prefixIcon: Padding(padding: EdgeInsets.only(left: 14, right: 10), child: CraftIcon(CraftIcons.pin, size: 18, color: AppColors.grayBrown)),
              prefixIconConstraints: BoxConstraints(minWidth: 0, minHeight: 0),
            ),
            items: [
              const DropdownMenuItem<String?>(value: null, child: Text('Not set')),
              for (final c in Geo.cities.keys) DropdownMenuItem<String?>(value: c, child: Text(c)),
            ],
            onChanged: (v) => setState(() => f = v == null ? f.copyWith(clearNearCity: true, clearDistance: true) : f.copyWith(nearCity: v)),
          ),
          const SizedBox(height: 12),
          Text('Distance from you', style: AppText.label),
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final d in _distances)
              AppChip(
                label: d == null ? 'Any' : 'Within ${d.round()} km',
                selected: f.maxDistanceKm == d,
                onTap: f.nearCity == null && d != null
                    ? null
                    : () => setState(() => f = d == null ? f.copyWith(clearDistance: true) : f.copyWith(maxDistanceKm: d)),
              ),
          ]),
          if (f.nearCity == null) ...[
            const SizedBox(height: 6),
            Text('Pick your city to filter by distance.', style: AppText.caption),
          ],
          const SizedBox(height: 12),
          const Divider(),
          const SizedBox(height: 6),
          Text('Delivered by', style: AppText.label),
          const SizedBox(height: 6),
          Row(children: [
            Expanded(
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(Insets.fieldHeight), alignment: Alignment.centerLeft),
                icon: const CraftIcon(CraftIcons.calendar, size: 18, color: AppColors.grayBrown),
                label: Text(f.neededBy == null ? 'Any date' : Fmt.date(f.neededBy!), style: AppText.body.copyWith(fontSize: 15)),
                onPressed: _pickDate,
              ),
            ),
            if (f.neededBy != null)
              IconButton(
                tooltip: 'Clear date',
                onPressed: () => setState(() => f = f.copyWith(clearNeededBy: true)),
                icon: const CraftIcon(CraftIcons.close, size: 18, color: AppColors.grayBrown),
              ),
          ]),
          const SizedBox(height: 6),
          Text(
            f.nearCity == null
                ? 'Estimated from stock (or days to make) plus courier time. Set your city for a closer estimate.'
                : 'Estimated from stock (or days to make) plus courier time from the store to ${f.nearCity}.',
            style: AppText.caption,
          ),
          const SizedBox(height: 6),
          const Divider(),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text('Accepts custom orders', style: AppText.bodyStrong),
            subtitle: Text('Makers who take requests', style: AppText.caption),
            value: f.customOnly,
            onChanged: (v) => setState(() => f = f.copyWith(customOnly: v)),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text('In stock now', style: AppText.bodyStrong),
            subtitle: Text('Ready-made items you can order today', style: AppText.caption),
            value: f.inStockOnly,
            onChanged: (v) => setState(() => f = f.copyWith(inStockOnly: v)),
          ),
          const SizedBox(height: 14),
          AppButton(label: 'Show results', onPressed: () => Navigator.pop(context, f)),
        ]),
      ),
    );
  }
}

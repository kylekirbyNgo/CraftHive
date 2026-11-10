import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/format.dart';
import '../../data/providers.dart';
import '../../shared/widgets/common.dart';
import '../../shared/widgets/craft_icon.dart';
import '../../shared/widgets/product_widgets.dart';

/// Supporting screen – Search / Category results with a filter sheet
/// (price, custom orders, in stock) and sorting.
class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key, this.initialQuery = '', this.categoryId});
  final String initialQuery;
  final String? categoryId;
  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  late final TextEditingController _q = TextEditingController(text: widget.initialQuery);
  late SearchFilters _f = SearchFilters(query: widget.initialQuery, categoryId: widget.categoryId);

  @override
  void dispose() {
    _q.dispose();
    super.dispose();
  }

  void _submit(String v) {
    ref.read(recentSearchProvider.notifier).add(v);
    setState(() => _f = _f.copyWith(query: v));
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
    final labels = {SortBy.relevance: 'Best match', SortBy.priceLow: 'Price: low to high', SortBy.priceHigh: 'Price: high to low', SortBy.rating: 'Top rated'};
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
    final results = searchProducts(ref.watch(catalogProvider), ref.watch(sellersProvider), _f);
    final title = _f.categoryId != null ? ref.watch(categoryProvider(_f.categoryId!)).name : 'Search';

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
                    _f = const SearchFilters();
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

class _FilterSheet extends StatefulWidget {
  const _FilterSheet({required this.initial});
  final SearchFilters initial;
  @override
  State<_FilterSheet> createState() => _FilterSheetState();
}

class _FilterSheetState extends State<_FilterSheet> {
  late SearchFilters f = widget.initial;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(Insets.screen, 0, Insets.screen, 16),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Expanded(child: Text('Filters', style: AppText.screenTitle)),
            TextButton(onPressed: () => setState(() => f = SearchFilters(query: f.query, categoryId: f.categoryId, sort: f.sort)), child: const Text('Reset')),
          ]),
          const SizedBox(height: 10),
          Text('Maximum price: ${f.maxPrice >= 2000 ? 'any' : Fmt.peso(f.maxPrice)}', style: AppText.label),
          Slider(
            value: f.maxPrice,
            min: 100,
            max: 2000,
            divisions: 19,
            label: Fmt.peso(f.maxPrice),
            onChanged: (v) => setState(() => f = f.copyWith(maxPrice: v)),
          ),
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

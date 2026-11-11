import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/format.dart';
import '../../data/models.dart';
import '../../data/providers.dart';
import '../../shared/widgets/common.dart';
import '../../shared/widgets/craft_icon.dart';
import '../../shared/widgets/product_widgets.dart';

enum _ListingFilter { all, inStock, madeToOrder, custom, lowStock, soldOut }

/// Screen 4 – My store (profile): Sign out, profile card with verified badge,
/// description and stats, Edit profile, and My listings with a Filter button and quick chips.
class MyStoreScreen extends ConsumerStatefulWidget {
  const MyStoreScreen({super.key});
  @override
  ConsumerState<MyStoreScreen> createState() => _MyStoreScreenState();
}

class _MyStoreScreenState extends ConsumerState<MyStoreScreen> {
  _ListingFilter _filter = _ListingFilter.all;
  String? _category;

  static const _labels = {
    _ListingFilter.all: 'All',
    _ListingFilter.inStock: 'In stock',
    _ListingFilter.madeToOrder: 'Made to order',
    _ListingFilter.custom: 'Custom',
    _ListingFilter.lowStock: 'Low stock',
    _ListingFilter.soldOut: 'Sold out',
  };

  bool _match(Product p) {
    if (_category != null && p.categoryId != _category) return false;
    return switch (_filter) {
      _ListingFilter.all => true,
      _ListingFilter.inStock => p.stock > 0,
      _ListingFilter.madeToOrder => p.leadDays > 0,
      _ListingFilter.custom => p.acceptsCustom,
      _ListingFilter.lowStock => p.isLowStock,
      _ListingFilter.soldOut => p.isSoldOut,
    };
  }

  Future<void> _signOut() async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.warmCream,
        title: Text('Sign out?', style: AppText.screenTitle),
        content: Text('You will need to log in again to buy, sell or chat.', style: AppText.body),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), style: TextButton.styleFrom(foregroundColor: AppColors.brick), child: const Text('Sign out')),
        ],
      ),
    );
    if (yes == true) ref.read(authProvider.notifier).signOut(); // router returns to Log in
  }

  Future<void> _openFilter(List<Category> cats) async {
    final res = await showModalBottomSheet<(_ListingFilter, String?)>(
      context: context,
      builder: (ctx) {
        var f = _filter;
        String? c = _category;
        return StatefulBuilder(
          builder: (ctx, setS) => SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(Insets.screen, 0, Insets.screen, 16),
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Text('Filter my listings', style: AppText.screenTitle),
                const SizedBox(height: 14),
                Text('Status', style: AppText.label),
                const SizedBox(height: 8),
                Wrap(spacing: 8, runSpacing: 8, children: [
                  for (final e in _labels.entries) AppChip(label: e.value, selected: f == e.key, color: AppColors.clay, onTap: () => setS(() => f = e.key)),
                ]),
                const SizedBox(height: 16),
                Text('Category', style: AppText.label),
                const SizedBox(height: 8),
                Wrap(spacing: 8, runSpacing: 8, children: [
                  AppChip(label: 'Any', selected: c == null, color: AppColors.clay, onTap: () => setS(() => c = null)),
                  for (final cat in cats) AppChip(label: cat.name, selected: c == cat.id, color: AppColors.clay, onTap: () => setS(() => c = cat.id)),
                ]),
                const SizedBox(height: 20),
                AppButton(label: 'Apply', onPressed: () => Navigator.pop(ctx, (f, c))),
              ]),
            ),
          ),
        );
      },
    );
    if (res != null) setState(() {
      _filter = res.$1;
      _category = res.$2;
    });
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authProvider);
    if (user == null) return const Scaffold();
    final me = ref.watch(sellerProvider('me'))!;
    final listings = ref.watch(myListingsProvider);
    final shown = listings.where(_match).toList();
    final myCats = {for (final p in listings) p.categoryId}.map((id) => ref.watch(categoryProvider(id))).toList();

    return Scaffold(
      appBar: ScreenHeader(
        title: 'My store',
        trailing: OutlinedButton.icon(
          onPressed: _signOut,
          icon: const CraftIcon(CraftIcons.logout, size: 16, color: AppColors.brick),
          label: const Text('Sign out'),
          style: OutlinedButton.styleFrom(
            minimumSize: const Size(0, 40),
            foregroundColor: AppColors.brick,
            side: const BorderSide(color: AppColors.brick, width: 1.5),
            shape: const StadiumBorder(),
            padding: const EdgeInsets.symmetric(horizontal: 12),
            textStyle: AppText.label.copyWith(fontWeight: FontWeight.w700),
          ),
        ),
      ),
      body: SafeArea(
        top: false,
        child: ResponsiveCenter(
          child: CustomScrollView(slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(Insets.screen, 4, Insets.screen, 0),
                child: StoreCard(
                  initials: user.initials,
                  name: user.username,
                  verified: user.isVerified,
                  location: user.location.isEmpty ? user.country : user.location,
                  bio: user.bio.isEmpty ? 'Tell buyers what you make. Tap Edit profile to add a description.' : user.bio,
                  stats: [('${listings.length}', 'Listings'), (me.rating.toStringAsFixed(1), 'Rating'), ('${me.sold}', 'Sold')],
                  actions: [AppButton(label: 'Edit profile', icon: CraftIcons.edit, kind: ButtonKind.clayOutline, height: 42, onPressed: () => context.push('/store/edit'))],
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(Insets.screen, 18, Insets.screen, 10),
                child: Row(children: [
                  Expanded(child: Semantics(header: true, child: Text('My listings (${listings.length})', style: AppText.section))),
                  FilledButton.icon(
                    onPressed: () => _openFilter(myCats),
                    icon: const CraftIcon(CraftIcons.filter, size: 15, color: AppColors.white),
                    label: Text(_filter == _ListingFilter.all && _category == null ? 'Filter' : 'Filter (on)'),
                    style: FilledButton.styleFrom(minimumSize: const Size(0, 38), shape: const StadiumBorder(), padding: const EdgeInsets.symmetric(horizontal: 14), textStyle: AppText.label.copyWith(fontWeight: FontWeight.w700)),
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
                    for (final f in [_ListingFilter.all, _ListingFilter.custom, _ListingFilter.lowStock, _ListingFilter.soldOut, _ListingFilter.madeToOrder]) ...[
                      AppChip(label: _labels[f]!, selected: _filter == f, color: AppColors.clay, onTap: () => setState(() => _filter = f)),
                      const SizedBox(width: 8),
                    ],
                  ],
                ),
              ),
            ),
            const SliverToBoxAdapter(child: SizedBox(height: 12)),
            if (shown.isEmpty)
              SliverToBoxAdapter(
                child: EmptyState(
                  icon: CraftIcons.store,
                  title: listings.isEmpty ? 'No listings yet' : 'No listings match',
                  message: listings.isEmpty ? 'Tap Sell to post your first item.' : 'Try another filter.',
                  actionLabel: listings.isEmpty ? 'Post an item' : 'Show all',
                  onAction: () {
                    if (listings.isEmpty) {
                      context.push('/sell');
                    } else {
                      setState(() {
                        _filter = _ListingFilter.all;
                        _category = null;
                      });
                    }
                  },
                ),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(Insets.screen, 0, Insets.screen, 32),
                sliver: SliverList.separated(
                  itemCount: shown.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (_, i) => _ListingRow(product: shown[i]),
                ),
              ),
          ]),
        ),
      ),
    );
  }
}

/// Profile card shared by My store and other makers' stores.
class StoreCard extends StatelessWidget {
  const StoreCard({super.key, required this.initials, required this.name, required this.verified, required this.location, required this.bio, required this.stats, required this.actions, this.color = AppColors.clay});
  final String initials;
  final String name;
  final bool verified;
  final String location;
  final String bio;
  final List<(String, String)> stats;
  final List<Widget> actions;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: AppColors.lightSand, borderRadius: BorderRadius.circular(18), border: Border.all(color: AppColors.linen)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Avatar(initials: initials, size: 72, color: color),
            const SizedBox(width: 14),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(name, style: AppText.screenTitle.copyWith(fontWeight: FontWeight.w800), maxLines: 1, overflow: TextOverflow.ellipsis),
                const SizedBox(height: 2),
                Row(children: [
                  CraftIcon(verified ? CraftIcons.verified : CraftIcons.pin, size: 15, color: verified ? AppColors.fern : AppColors.grayBrown),
                  const SizedBox(width: 4),
                  Flexible(
                    child: Text(verified ? 'Verified maker · $location' : location,
                        style: AppText.caption.copyWith(fontSize: 12.5, color: verified ? AppColors.fern : AppColors.grayBrown, fontWeight: FontWeight.w700),
                        overflow: TextOverflow.ellipsis),
                  ),
                ]),
              ]),
            ),
          ]),
          const SizedBox(height: 12),
          Text(bio, style: AppText.body.copyWith(fontSize: 13)),
          const SizedBox(height: 12),
          Row(children: [
            for (var i = 0; i < stats.length; i++) ...[
              if (i > 0) const SizedBox(width: 8),
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  decoration: BoxDecoration(color: AppColors.white, borderRadius: Radii.field),
                  child: Semantics(
                    label: '${stats[i].$1} ${stats[i].$2}',
                    excludeSemantics: true,
                    child: Column(children: [
                      Text(stats[i].$1, style: AppText.section.copyWith(fontSize: 17, fontWeight: FontWeight.w800)),
                      Text(stats[i].$2, style: AppText.small.copyWith(color: AppColors.grayBrown, fontWeight: FontWeight.w500)),
                    ]),
                  ),
                ),
              ),
            ],
          ]),
          const SizedBox(height: 12),
          Row(children: [
            for (var i = 0; i < actions.length; i++) ...[
              if (i > 0) const SizedBox(width: 10),
              Expanded(child: actions[i]),
            ],
          ]),
        ]),
      );
}

class _ListingRow extends StatelessWidget {
  const _ListingRow({required this.product});
  final Product product;
  @override
  Widget build(BuildContext context) {
    final p = product;
    final (status, tone) = p.status == ListingStatus.hidden
        ? ('Draft', Tone.neutral)
        : p.isSoldOut
            ? ('Sold out', Tone.error)
            : p.isLowStock
                ? ('Low stock', Tone.warning)
                : ('Active', Tone.success);
    final meta = p.stock > 0
        ? (p.isLowStock ? '${p.stock} left' : '${p.stock} in stock${p.acceptsCustom ? ' · custom ${p.customOptions.isEmpty ? 'orders' : p.customOptions.first.toLowerCase()}' : ''}')
        : (p.leadDays > 0 ? 'Made to order · ${p.leadDays} days' : '0 in stock');
    return Material(
      color: AppColors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: const BorderSide(color: AppColors.linen)),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => context.push('/product/${p.id}'),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Row(children: [
            ProductPhoto(product: p, width: 62, height: 62, radius: 10),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(p.title, style: AppText.bodyStrong, maxLines: 1, overflow: TextOverflow.ellipsis),
                const SizedBox(height: 3),
                Text(meta, style: AppText.caption, maxLines: 1, overflow: TextOverflow.ellipsis),
                const SizedBox(height: 4),
                Row(children: [Text(Fmt.peso(p.price), style: AppText.price), const SizedBox(width: 8), StatusPill(status, tone: tone)]),
              ]),
            ),
            RoundIconButton(icon: CraftIcons.edit, tooltip: 'Edit ${p.title}', background: AppColors.white, size: 38, onPressed: () => context.push('/listing/${p.id}/edit')),
          ]),
        ),
      ),
    );
  }
}

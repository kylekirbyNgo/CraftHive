import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../data/models.dart';
import '../../data/providers.dart';
import '../../shared/widgets/common.dart';
import '../../shared/widgets/craft_icon.dart';
import '../../shared/widgets/product_widgets.dart';

/// Screen 3 – Home: profile picture top right, search, Featured (horizontal),
/// Categories, Recent searches (horizontal), More to explore, and the bottom bar.
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  String _greeting() {
    final h = DateTime.now().hour;
    if (h < 12) return 'Good morning';
    if (h < 18) return 'Good afternoon';
    return 'Good evening';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authProvider);
    final products = ref.watch(catalogProvider).where((p) => p.status == ListingStatus.active && p.sellerId != 'me').toList();
    final featured = products.where((p) => p.isFeatured).toList();
    final explore = products.where((p) => !p.isFeatured).toList();
    final categories = ref.watch(categoriesProvider);
    final recent = ref.watch(recentSearchProvider);
    final unreadNotices = ref.watch(unreadNoticesProvider);

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: RefreshIndicator(
          color: AppColors.moss,
          onRefresh: () => Future<void>.delayed(const Duration(milliseconds: 700)),
          child: CustomScrollView(
            slivers: [
              SliverToBoxAdapter(
                child: ResponsiveCenter(
                  maxWidth: 900,
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    // Header
                    Padding(
                      padding: const EdgeInsets.fromLTRB(Insets.screen, 14, 14, 6),
                      child: Row(children: [
                        ClipOval(child: Image.asset('assets/images/logo.png', width: 40, height: 40, semanticLabel: 'CraftHive')),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text('CraftHive', style: AppText.section.copyWith(fontSize: 18, fontWeight: FontWeight.w800)),
                            Text('${_greeting()}, ${user?.firstName ?? 'there'}', style: AppText.caption),
                          ]),
                        ),
                        RoundIconButton(
                          icon: CraftIcons.bell,
                          tooltip: 'Notifications',
                          background: AppColors.white,
                          badge: unreadNotices,
                          onPressed: () => context.push('/notifications'),
                        ),
                        const SizedBox(width: 4),
                        Semantics(
                          button: true,
                          label: 'My profile and store',
                          excludeSemantics: true,
                          child: InkResponse(
                            onTap: () => context.push('/store'),
                            radius: 26,
                            child: Padding(
                              padding: const EdgeInsets.all(2),
                              child: Avatar(initials: user?.initials ?? 'AR', size: 42, ring: true),
                            ),
                          ),
                        ),
                      ]),
                    ),
                    // Search
                    Padding(
                      padding: const EdgeInsets.fromLTRB(Insets.screen, 8, Insets.screen, 14),
                      child: _SearchField(onTap: () => context.push('/search')),
                    ),
                    // Featured
                    SectionHeader('Featured', action: 'See all', onAction: () => context.push('/search')),
                    SizedBox(
                      height: 238,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.fromLTRB(Insets.screen, 4, Insets.screen, 4),
                        itemCount: featured.length,
                        separatorBuilder: (_, __) => const SizedBox(width: 12),
                        itemBuilder: (_, i) => FeaturedProductCard(product: featured[i]),
                      ),
                    ),
                    const SizedBox(height: 10),
                    // Categories
                    SectionHeader('Categories', action: 'All', onAction: () => _showAllCategories(context, categories)),
                    SizedBox(
                      height: 100,
                      child: ListView(
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.symmetric(horizontal: 14),
                        children: [
                          for (final c in categories.take(6)) _CategoryTile(category: c, onTap: () => context.push('/search?category=${c.id}')),
                          _MoreTile(onTap: () => _showAllCategories(context, categories)),
                        ],
                      ),
                    ),
                    // Recent searches
                    if (recent.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      SectionHeader('Recent searches', action: 'Clear', onAction: () => ref.read(recentSearchProvider.notifier).clear()),
                      SizedBox(
                        height: 40,
                        child: ListView.separated(
                          scrollDirection: Axis.horizontal,
                          padding: const EdgeInsets.symmetric(horizontal: Insets.screen),
                          itemCount: recent.length,
                          separatorBuilder: (_, __) => const SizedBox(width: 8),
                          itemBuilder: (_, i) => _RecentChip(text: recent[i], onTap: () => context.push('/search?q=${Uri.encodeQueryComponent(recent[i])}')),
                        ),
                      ),
                    ],
                    const SizedBox(height: 14),
                    const SectionHeader('More to explore'),
                    const SizedBox(height: 8),
                    ProductGrid(products: explore),
                    const SizedBox(height: 110), // room above the bottom bar
                  ]),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showAllCategories(BuildContext context, List<Category> categories) {
    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(Insets.screen, 0, Insets.screen, 20),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('All categories', style: AppText.screenTitle),
            const SizedBox(height: 14),
            Wrap(
              spacing: 6,
              runSpacing: 12,
              children: [
                for (final c in categories)
                  _CategoryTile(category: c, onTap: () {
                    Navigator.pop(ctx);
                    context.push('/search?category=${c.id}');
                  }),
              ],
            ),
          ]),
        ),
      ),
    );
  }
}

class _SearchField extends StatelessWidget {
  const _SearchField({required this.onTap});
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        label: 'Search crafts, shops or makers',
        excludeSemantics: true,
        child: Material(
          color: AppColors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: const BorderSide(color: AppColors.linen, width: 1.5)),
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: onTap,
            child: SizedBox(
              height: 48,
              child: Row(children: [
                const SizedBox(width: 14),
                const CraftIcon(CraftIcons.search, size: 19, color: AppColors.grayBrown),
                const SizedBox(width: 10),
                Expanded(child: Text('Search crafts, shops or makers', style: AppText.body.copyWith(color: AppColors.grayBrown, fontSize: 14.5))),
                const CraftIcon(CraftIcons.filter, size: 17, color: AppColors.grayBrown),
                const SizedBox(width: 14),
              ]),
            ),
          ),
        ),
      );
}

class _CategoryTile extends StatelessWidget {
  const _CategoryTile({required this.category, required this.onTap});
  final Category category;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        label: '${category.name} category',
        excludeSemantics: true,
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: onTap,
          child: SizedBox(
            width: 74,
            child: Column(children: [
              const SizedBox(height: 4),
              Container(
                width: 58,
                height: 58,
                decoration: BoxDecoration(color: category.tint, borderRadius: BorderRadius.circular(18)),
                alignment: Alignment.center,
                child: CraftIcon(category.icon, size: 26, color: category.ink, strokeWidth: 1.7),
              ),
              const SizedBox(height: 6),
              Text(category.name, style: AppText.small.copyWith(fontSize: 11.5, height: 1.25), textAlign: TextAlign.center, maxLines: 2),
            ]),
          ),
        ),
      );
}

class _MoreTile extends StatelessWidget {
  const _MoreTile({required this.onTap});
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        label: 'More categories',
        excludeSemantics: true,
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: onTap,
          child: SizedBox(
            width: 74,
            child: Column(children: [
              const SizedBox(height: 4),
              Container(
                width: 58,
                height: 58,
                decoration: BoxDecoration(color: AppColors.white, borderRadius: BorderRadius.circular(18), border: Border.all(color: AppColors.linen, width: 1.5)),
                alignment: Alignment.center,
                child: const CraftIcon(CraftIcons.grid, size: 24, color: AppColors.grayBrown, strokeWidth: 1.7),
              ),
              const SizedBox(height: 6),
              Text('More', style: AppText.small.copyWith(fontSize: 11.5)),
            ]),
          ),
        ),
      );
}

class _RecentChip extends StatelessWidget {
  const _RecentChip({required this.text, required this.onTap});
  final String text;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        label: 'Search again for $text',
        excludeSemantics: true,
        child: Material(
          color: AppColors.white,
          shape: const StadiumBorder(side: BorderSide(color: AppColors.linen)),
          child: InkWell(
            customBorder: const StadiumBorder(),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                const CraftIcon(CraftIcons.clock, size: 15, color: AppColors.grayBrown),
                const SizedBox(width: 6),
                Text(text, style: AppText.body.copyWith(fontSize: 13)),
              ]),
            ),
          ),
        ),
      );
}

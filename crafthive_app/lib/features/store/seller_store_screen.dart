import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_theme.dart';
import '../../data/models.dart';
import '../../data/providers.dart';
import '../../shared/widgets/common.dart';
import '../../shared/widgets/craft_icon.dart';
import '../../shared/widgets/product_widgets.dart';
import 'my_store_screen.dart';

/// Supporting screen – Another maker's store: same layout as My store,
/// with Message and Follow instead of Edit profile.
class SellerStoreScreen extends ConsumerStatefulWidget {
  const SellerStoreScreen({super.key, required this.sellerId});
  final String sellerId;
  @override
  ConsumerState<SellerStoreScreen> createState() => _SellerStoreScreenState();
}

class _SellerStoreScreenState extends ConsumerState<SellerStoreScreen> {
  bool _following = false;

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(sellerProvider(widget.sellerId));
    if (s == null) return const Scaffold(appBar: ScreenHeader(title: 'Store'), body: SizedBox());
    final items = ref.watch(catalogProvider).where((p) => p.sellerId == s.id && p.status == ListingStatus.active).toList();

    return Scaffold(
      appBar: ScreenHeader(
        title: s.name,
        trailing: RoundIconButton(icon: CraftIcons.share, tooltip: 'Share store', onPressed: () => showComingSoon(context, 'Sharing')),
      ),
      body: SafeArea(
        top: false,
        child: ResponsiveCenter(
          maxWidth: 900,
          child: CustomScrollView(slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(Insets.screen, 4, Insets.screen, 0),
                child: StoreCard(
                  initials: s.initials,
                  name: s.name,
                  verified: s.isVerified,
                  location: s.location,
                  bio: s.bio,
                  color: s.color,
                  stats: [('${items.length}', 'Listings'), (s.rating.toStringAsFixed(1), 'Rating'), ('${s.sold}', 'Sold')],
                  actions: [
                    AppButton(
                      label: 'Message',
                      icon: CraftIcons.chat,
                      height: 42,
                      onPressed: items.isEmpty
                          ? null
                          : () {
                              final id = ref.read(chatsProvider.notifier).openForProduct(items.first, s, note: 'from their store page');
                              context.push('/chat/$id');
                            },
                    ),
                    AppButton(
                      label: _following ? 'Following' : 'Follow',
                      icon: _following ? CraftIcons.check : CraftIcons.plus,
                      kind: _following ? ButtonKind.soft : ButtonKind.clayOutline,
                      height: 42,
                      onPressed: () => setState(() => _following = !_following),
                    ),
                  ],
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(Insets.screen, 18, Insets.screen, 10),
                child: Semantics(header: true, child: Text('Listings (${items.length})', style: AppText.section)),
              ),
            ),
            SliverToBoxAdapter(child: ProductGrid(products: items)),
            const SliverToBoxAdapter(child: SizedBox(height: 32)),
          ]),
        ),
      ),
    );
  }
}

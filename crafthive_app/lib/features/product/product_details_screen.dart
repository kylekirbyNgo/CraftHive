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

/// Screen 5 – Product details: photo gallery, price, rating, stock, seller card,
/// description, custom options, and the Custom order / Buy now buttons.
class ProductDetailsScreen extends ConsumerStatefulWidget {
  const ProductDetailsScreen({super.key, required this.productId});
  final String productId;
  @override
  ConsumerState<ProductDetailsScreen> createState() => _ProductDetailsScreenState();
}

class _ProductDetailsScreenState extends ConsumerState<ProductDetailsScreen> {
  int _page = 0;

  @override
  Widget build(BuildContext context) {
    final p = ref.watch(productProvider(widget.productId));
    if (p == null) {
      return Scaffold(
        appBar: const ScreenHeader(title: 'Item'),
        body: EmptyState(icon: CraftIcons.tag, title: 'This item is no longer available', message: 'The seller may have archived it.', actionLabel: 'Back to home', onAction: () => context.go('/home')),
      );
    }
    final seller = ref.watch(sellerProvider(p.sellerId))!;
    final cat = ref.watch(categoryProvider(p.categoryId));
    final saved = ref.watch(savedProvider).contains(p.id);
    final isMine = p.sellerId == 'me';

    final stockText = p.stock > 0
        ? '${p.stock} in stock'
        : p.leadDays > 0
            ? 'Made to order · ${p.leadDays} days'
            : 'Sold out';
    final stockColor = p.stock > 3 ? AppColors.fern : (p.stock > 0 || p.leadDays > 0 ? AppColors.amberText : AppColors.brick);

    return Scaffold(
      body: LayoutBuilder(builder: (context, c) {
        final galleryHeight = (c.maxWidth * 0.85).clamp(260.0, 420.0);
        return CustomScrollView(slivers: [
          SliverToBoxAdapter(
            child: SizedBox(
              height: galleryHeight,
              child: Stack(children: [
                PageView.builder(
                  itemCount: p.photoCount,
                  onPageChanged: (i) => setState(() => _page = i),
                  itemBuilder: (_, i) => ProductPhoto(product: p, height: galleryHeight, radius: 0, iconScale: 0.36, variant: i),
                ),
                Positioned(
                  top: MediaQuery.paddingOf(context).top + 8,
                  left: 14,
                  right: 14,
                  child: Row(children: [
                    const BackRoundButton(background: AppColors.white),
                    const Spacer(),
                    RoundIconButton(
                      icon: CraftIcons.heart,
                      tooltip: saved ? 'Remove from saved' : 'Save item',
                      background: saved ? AppColors.brickTint : AppColors.white,
                      color: saved ? AppColors.brick : AppColors.darkCocoa,
                      onPressed: () {
                        final now = ref.read(savedProvider.notifier).toggle(p.id);
                        showMessage(context, now ? 'Saved. Find it in the Saved tab.' : 'Removed from Saved.');
                      },
                    ),
                    RoundIconButton(icon: CraftIcons.share, tooltip: 'Share item', background: AppColors.white, onPressed: () => showComingSoon(context, 'Sharing')),
                  ]),
                ),
                Positioned(
                  bottom: 14,
                  left: 0,
                  right: 0,
                  child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                    for (var i = 0; i < p.photoCount; i++)
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        margin: const EdgeInsets.symmetric(horizontal: 3),
                        width: i == _page ? 18 : 7,
                        height: 7,
                        decoration: BoxDecoration(color: i == _page ? AppColors.darkCocoa : AppColors.white, borderRadius: Radii.pill),
                      ),
                  ]),
                ),
                Positioned(
                  bottom: 10,
                  right: 16,
                  child: Container(
                    height: 24,
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    decoration: BoxDecoration(color: AppColors.darkCocoa.withValues(alpha: 0.72), borderRadius: Radii.pill),
                    alignment: Alignment.center,
                    child: Text('${_page + 1} / ${p.photoCount}', style: AppText.small.copyWith(color: AppColors.white, fontWeight: FontWeight.w700, fontSize: 12)),
                  ),
                ),
              ]),
            ),
          ),
          SliverToBoxAdapter(
            child: ResponsiveCenter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(Insets.screen, 16, Insets.screen, 24),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Wrap(spacing: 8, runSpacing: 6, children: [
                    _Tag(cat.name, AppColors.moss, AppColors.paleSage),
                    if (p.acceptsCustom) const _Tag('Custom orders open', AppColors.clayText, AppColors.clayTint),
                  ]),
                  const SizedBox(height: 12),
                  Text(p.title, style: AppText.headline),
                  const SizedBox(height: 10),
                  Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
                    Text(Fmt.peso(p.price), style: AppText.priceLarge),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Wrap(alignment: WrapAlignment.end, crossAxisAlignment: WrapCrossAlignment.center, spacing: 4, children: [
                        const CraftIcon(CraftIcons.star, size: 15, color: AppColors.softHoney),
                        Text(p.rating.toStringAsFixed(1), style: AppText.label.copyWith(fontWeight: FontWeight.w800)),
                        Text('· ${p.sold} sold ·', style: AppText.caption.copyWith(fontSize: 13)),
                        Text(stockText, style: AppText.label.copyWith(color: stockColor, fontWeight: FontWeight.w700)),
                      ]),
                    ),
                  ]),
                  const SizedBox(height: 14),
                  SellerStrip(
                    seller: seller,
                    trailingLabel: isMine ? 'My store' : 'View store',
                    onTap: () => context.push(isMine ? '/store' : '/seller/${seller.id}'),
                  ),
                  const SizedBox(height: 16),
                  Semantics(header: true, child: Text('Description', style: AppText.section.copyWith(fontSize: 15))),
                  const SizedBox(height: 6),
                  Text(p.description, style: AppText.body.copyWith(fontSize: 13.5, height: 1.55)),
                  if (p.acceptsCustom) ...[
                    const SizedBox(height: 14),
                    InfoNote(
                      p.customNote ?? 'This maker accepts custom orders.',
                      icon: CraftIcons.edit,
                      tone: Tone.seller,
                    ),
                    const SizedBox(height: 12),
                    Text('Options you can ask for', style: AppText.label),
                    const SizedBox(height: 8),
                    Wrap(spacing: 8, runSpacing: 8, children: [for (final o in p.customOptions) AppChip(label: o, height: 32)]),
                  ],
                  const SizedBox(height: 18),
                  _Facts(product: p, seller: seller),
                ]),
              ),
            ),
          ),
        ]);
      }),
      bottomNavigationBar: _BottomActions(product: p, seller: seller, isMine: isMine),
    );
  }
}

class _Tag extends StatelessWidget {
  const _Tag(this.text, this.ink, this.tint);
  final String text;
  final Color ink;
  final Color tint;
  @override
  Widget build(BuildContext context) => Container(
        height: 24,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(color: tint, borderRadius: Radii.pill, border: Border.all(color: ink)),
        alignment: Alignment.center,
        child: Text(text, style: AppText.small.copyWith(color: ink, fontWeight: FontWeight.w700)),
      );
}

class _Facts extends StatelessWidget {
  const _Facts({required this.product, required this.seller});
  final Product product;
  final Seller seller;
  @override
  Widget build(BuildContext context) {
    Widget row(String icon, String label, String value) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 7),
          child: Row(children: [
            CraftIcon(icon, size: 18, color: AppColors.grayBrown),
            const SizedBox(width: 10),
            Expanded(child: Text(label, style: AppText.body.copyWith(color: AppColors.grayBrown, fontSize: 13.5))),
            Text(value, style: AppText.label),
          ]),
        );
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      decoration: BoxDecoration(color: AppColors.white, borderRadius: Radii.card, border: Border.all(color: AppColors.linen)),
      child: Column(children: [
        row(CraftIcons.pin, 'Ships from', seller.location),
        const Divider(),
        row(CraftIcons.truck, 'Delivery or meet-up', 'Arrange in chat'),
        const Divider(),
        row(CraftIcons.wallet, 'Payment', 'GCash, bank, cash'),
      ]),
    );
  }
}

class _BottomActions extends ConsumerWidget {
  const _BottomActions({required this.product, required this.seller, required this.isMine});
  final Product product;
  final Seller seller;
  final bool isMine;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final canBuy = product.stock > 0 || product.leadDays > 0;
    return Container(
      decoration: const BoxDecoration(color: AppColors.white, border: Border(top: BorderSide(color: AppColors.linen))),
      padding: EdgeInsets.fromLTRB(Insets.screen, 12, Insets.screen, 12 + MediaQuery.paddingOf(context).bottom),
      child: ResponsiveCenter(
        child: isMine
            ? AppButton(label: 'Edit listing', icon: CraftIcons.edit, kind: ButtonKind.clayOutline, onPressed: () => context.push('/listing/${product.id}/edit'))
            : Row(children: [
                if (product.acceptsCustom) ...[
                  Expanded(
                    child: AppButton(label: 'Custom order', icon: CraftIcons.edit, kind: ButtonKind.clayOutline, onPressed: () => context.push('/product/${product.id}/custom')),
                  ),
                  const SizedBox(width: 10),
                ],
                Expanded(
                  child: AppButton(
                    label: canBuy ? 'Buy now' : 'Sold out',
                    icon: CraftIcons.chat,
                    onPressed: canBuy
                        ? () {
                            final id = ref.read(chatsProvider.notifier).openForProduct(product, seller);
                            context.push('/chat/$id');
                          }
                        : null,
                  ),
                ),
              ]),
      ),
    );
  }
}

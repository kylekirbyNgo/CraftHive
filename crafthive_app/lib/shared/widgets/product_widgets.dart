import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/format.dart';
import '../../data/models.dart';
import '../../data/providers.dart';
import 'common.dart';
import 'craft_icon.dart';

/// Product photo from Supabase Storage. Listings without photos (and photos that
/// fail to load) show the category's tint with its craft icon instead.
class ProductPhoto extends ConsumerWidget {
  const ProductPhoto({super.key, required this.product, this.width, this.height = 112, this.radius = 12, this.iconScale = 0.38, this.variant = 0});
  final Product product;
  final double? width;
  final double height;
  final double radius;
  final double iconScale;
  final int variant; // slightly different shade for gallery pages

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cat = ref.watch(categoryProvider(product.categoryId));
    final tint = variant == 0 ? cat.tint : Color.lerp(cat.tint, AppColors.white, 0.12 * variant)!;
    return LayoutBuilder(builder: (context, c) {
      final w = width ?? (c.maxWidth.isFinite ? c.maxWidth : height);
      final iconSize = (w < height ? w : height) * iconScale;
      final placeholder = Container(
        width: width,
        height: height,
        decoration: BoxDecoration(color: tint, borderRadius: BorderRadius.circular(radius)),
        alignment: Alignment.center,
        child: CraftIcon(cat.icon, size: iconSize, color: cat.ink, strokeWidth: 1.5, semanticLabel: 'Photo of ${product.title}'),
      );
      if (product.imageUrls.isEmpty) return placeholder;
      final url = product.imageUrls[variant < product.imageUrls.length ? variant : product.imageUrls.length - 1];
      return ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: Image.network(
          url,
          width: width,
          height: height,
          fit: BoxFit.cover,
          semanticLabel: 'Photo of ${product.title}',
          loadingBuilder: (_, child, progress) => progress == null ? child : Container(width: width, height: height, color: tint),
          errorBuilder: (_, __, ___) => placeholder,
        ),
      );
    });
  }
}

class _Rating extends StatelessWidget {
  const _Rating(this.value);
  final double value;
  @override
  Widget build(BuildContext context) => Row(mainAxisSize: MainAxisSize.min, children: [
        const CraftIcon(CraftIcons.star, size: 13, color: AppColors.softHoney),
        const SizedBox(width: 3),
        Text(value > 0 ? value.toStringAsFixed(1) : 'New', style: AppText.caption.copyWith(fontSize: 11.5)),
      ]);
}

/// Card in the horizontal "Featured" row on Home.
class FeaturedProductCard extends ConsumerWidget {
  const FeaturedProductCard({super.key, required this.product});
  final Product product;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final seller = ref.watch(sellerProvider(product.sellerId));
    return SizedBox(
      width: 156,
      child: _CardShell(
        label: '${product.title}, ${Fmt.peso(product.price)}, by ${seller?.name}',
        onTap: () => context.push('/product/${product.id}'),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          ProductPhoto(product: product, height: 112),
          const SizedBox(height: 6),
          SizedBox(height: 34, child: Text(product.title, style: AppText.bodyStrong.copyWith(fontSize: 13, height: 1.3), maxLines: 2, overflow: TextOverflow.ellipsis)),
          const SizedBox(height: 4),
          Text(seller?.name ?? '', style: AppText.caption.copyWith(fontSize: 11.5), maxLines: 1, overflow: TextOverflow.ellipsis),
          const SizedBox(height: 4),
          Row(children: [Expanded(child: Text(Fmt.peso(product.price), style: AppText.price)), _Rating(product.rating)]),
        ]),
      ),
    );
  }
}

/// Card used in 2-column product grids (Home, Search, Saved, Seller store).
class ProductGridCard extends ConsumerWidget {
  const ProductGridCard({super.key, required this.product, this.showSave = true});
  final Product product;
  final bool showSave;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final seller = ref.watch(sellerProvider(product.sellerId));
    final saved = ref.watch(savedProvider).contains(product.id);
    return _CardShell(
      label: '${product.title}, ${Fmt.peso(product.price)}, by ${seller?.name}',
      onTap: () => context.push('/product/${product.id}'),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Stack(children: [
          ProductPhoto(product: product, height: 118, iconScale: 0.37),
          if (showSave)
            Positioned(
              top: 4,
              right: 4,
              child: _SaveHeart(saved: saved, onTap: () => ref.read(savedProvider.notifier).toggle(product.id), title: product.title),
            ),
          if (product.acceptsCustom)
            Positioned(
              left: 6,
              bottom: 6,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                decoration: BoxDecoration(color: AppColors.white.withValues(alpha: 0.92), borderRadius: Radii.pill),
                child: Text('Custom', style: AppText.small.copyWith(fontSize: 10, color: AppColors.clayText, fontWeight: FontWeight.w800)),
              ),
            ),
        ]),
        const SizedBox(height: 6),
        Text(product.title, style: AppText.bodyStrong.copyWith(fontSize: 13), maxLines: 1, overflow: TextOverflow.ellipsis),
        const SizedBox(height: 2),
        Text(seller?.name ?? '', style: AppText.caption.copyWith(fontSize: 11.5), maxLines: 1, overflow: TextOverflow.ellipsis),
        const SizedBox(height: 3),
        Row(children: [Expanded(child: Text(Fmt.peso(product.price), style: AppText.price)), _Rating(product.rating)]),
      ]),
    );
  }
}

class _SaveHeart extends StatelessWidget {
  const _SaveHeart({required this.saved, required this.onTap, required this.title});
  final bool saved;
  final VoidCallback onTap;
  final String title;
  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        toggled: saved,
        label: saved ? 'Remove $title from saved' : 'Save $title',
        excludeSemantics: true,
        child: InkResponse(
          onTap: onTap,
          radius: 22,
          child: Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(color: AppColors.white.withValues(alpha: 0.92), shape: BoxShape.circle),
            alignment: Alignment.center,
            child: saved
                ? const Icon(Icons.favorite_rounded, size: 18, color: AppColors.brick)
                : const CraftIcon(CraftIcons.heart, size: 17, color: AppColors.darkCocoa),
          ),
        ),
      );
}

class _CardShell extends StatelessWidget {
  const _CardShell({required this.child, required this.onTap, required this.label});
  final Widget child;
  final VoidCallback onTap;
  final String label;
  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        label: label,
        child: Material(
          color: AppColors.white,
          shape: RoundedRectangleBorder(borderRadius: Radii.card, side: const BorderSide(color: AppColors.linen)),
          clipBehavior: Clip.antiAlias,
          child: InkWell(onTap: onTap, child: Padding(padding: const EdgeInsets.all(8), child: child)),
        ),
      );
}

/// Responsive product grid: 2 columns on phones, 3–4 on wider screens.
class ProductGrid extends StatelessWidget {
  const ProductGrid({super.key, required this.products, this.padding = const EdgeInsets.symmetric(horizontal: Insets.screen)});
  final List<Product> products;
  final EdgeInsets padding;
  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, c) {
        final cols = c.maxWidth >= 900 ? 4 : (c.maxWidth >= 600 ? 3 : 2);
        final width = (c.maxWidth - padding.horizontal - (cols - 1) * 12) / cols;
        return Padding(
          padding: padding,
          child: Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [for (final p in products) SizedBox(width: width, child: ProductGridCard(product: p))],
          ),
        );
      });
}

/// Seller row used on product details ("View store").
class SellerStrip extends StatelessWidget {
  const SellerStrip({super.key, required this.seller, required this.onTap, this.trailingLabel = 'View store'});
  final Seller seller;
  final VoidCallback onTap;
  final String trailingLabel;
  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        label: '${seller.name}. $trailingLabel',
        excludeSemantics: true,
        child: Material(
          color: AppColors.lightSand,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: const BorderSide(color: AppColors.linen)),
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Row(children: [
                Avatar(initials: seller.initials, size: 42, color: seller.color, online: seller.isOnline),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(seller.name, style: AppText.bodyStrong),
                    const SizedBox(height: 2),
                    Row(children: [
                      if (seller.isVerified) ...[const CraftIcon(CraftIcons.verified, size: 14, color: AppColors.fern), const SizedBox(width: 4)],
                      Flexible(
                        child: Text(
                          '${seller.isVerified ? 'Verified maker · ' : ''}replies in ${seller.replyTime}',
                          style: AppText.caption.copyWith(color: seller.isVerified ? AppColors.fern : AppColors.grayBrown, fontWeight: FontWeight.w600),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ]),
                  ]),
                ),
                Text(trailingLabel, style: AppText.label.copyWith(color: AppColors.moss, fontWeight: FontWeight.w700)),
              ]),
            ),
          ),
        ),
      );
}

/// Small product summary row (custom order, request sent, chat strip).
class ProductSummaryRow extends StatelessWidget {
  const ProductSummaryRow({super.key, required this.product, required this.title, required this.subtitle, this.onTap, this.photo = 56, this.trailing});
  final Product product;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;
  final double photo;
  final Widget? trailing;
  @override
  Widget build(BuildContext context) => Material(
        color: AppColors.lightSand,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: const BorderSide(color: AppColors.linen)),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Row(children: [
              ProductPhoto(product: product, width: photo, height: photo, radius: 10),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(title, style: AppText.bodyStrong.copyWith(fontSize: 13.5), maxLines: 1, overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 2),
                  Text(subtitle, style: AppText.caption, maxLines: 1, overflow: TextOverflow.ellipsis),
                ]),
              ),
              if (trailing != null) trailing!,
            ]),
          ),
        ),
      );
}

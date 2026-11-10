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

/// Supporting screen – Orders, split into Buying and Selling like Messages.
class OrdersScreen extends ConsumerStatefulWidget {
  const OrdersScreen({super.key});
  @override
  ConsumerState<OrdersScreen> createState() => _OrdersScreenState();
}

class _OrdersScreenState extends ConsumerState<OrdersScreen> {
  ChatSide _side = ChatSide.buying;
  bool _activeOnly = false;

  @override
  Widget build(BuildContext context) {
    final orders = ref
        .watch(ordersProvider)
        .where((o) => o.side == _side)
        .where((o) => !_activeOnly || (o.status != OrderStatus.delivered && o.status != OrderStatus.cancelled))
        .toList();

    return Scaffold(
      appBar: const ScreenHeader(title: 'Orders', showBack: false),
      body: ResponsiveCenter(
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(Insets.screen, 2, Insets.screen, 10),
            child: Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(color: AppColors.lightSand, borderRadius: BorderRadius.circular(16), border: Border.all(color: AppColors.linen)),
              child: Row(children: [
                _SegTab(label: 'Buying', sub: 'What I ordered', on: _side == ChatSide.buying, color: AppColors.moss, onTap: () => setState(() => _side = ChatSide.buying)),
                const SizedBox(width: 4),
                _SegTab(label: 'Selling', sub: 'Orders for my store', on: _side == ChatSide.selling, color: AppColors.clayText, onTap: () => setState(() => _side = ChatSide.selling)),
              ]),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(Insets.screen, 0, Insets.screen, 8),
            child: Row(children: [
              AppChip(label: 'All orders', selected: !_activeOnly, height: 34, onTap: () => setState(() => _activeOnly = false)),
              const SizedBox(width: 8),
              AppChip(label: 'In progress', selected: _activeOnly, height: 34, onTap: () => setState(() => _activeOnly = true)),
            ]),
          ),
          Expanded(
            child: orders.isEmpty
                ? ListView(children: [
                    EmptyState(
                      icon: CraftIcons.orders,
                      title: _side == ChatSide.buying ? 'No orders yet' : 'No orders for your store yet',
                      message: _side == ChatSide.buying ? 'Items you buy or request appear here so you can track them.' : 'Share your store so buyers can find you.',
                      actionLabel: _side == ChatSide.buying ? 'Start shopping' : 'Post an item',
                      onAction: () {
                        if (_side == ChatSide.buying) {
                          context.go('/home');
                        } else {
                          context.push('/sell');
                        }
                      },
                    ),
                  ])
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(Insets.screen, 4, Insets.screen, 110),
                    itemCount: orders.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemBuilder: (_, i) => _OrderCard(order: orders[i]),
                  ),
          ),
        ]),
      ),
    );
  }
}

class _SegTab extends StatelessWidget {
  const _SegTab({required this.label, required this.sub, required this.on, required this.color, required this.onTap});
  final String label;
  final String sub;
  final bool on;
  final Color color;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Expanded(
        child: Semantics(
          button: true,
          selected: on,
          label: '$label tab, $sub',
          excludeSemantics: true,
          child: Material(
            color: on ? color : Colors.transparent,
            borderRadius: Radii.field,
            child: InkWell(
              borderRadius: Radii.field,
              onTap: onTap,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 9),
                child: Column(children: [
                  Text(label, style: AppText.bodyStrong.copyWith(fontWeight: FontWeight.w800, color: on ? AppColors.white : AppColors.darkCocoa)),
                  Text(sub, style: AppText.small.copyWith(color: on ? AppColors.white : AppColors.grayBrown)),
                ]),
              ),
            ),
          ),
        ),
      );
}

class _OrderCard extends ConsumerWidget {
  const _OrderCard({required this.order});
  final Order order;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = ref.watch(productProvider(order.productId));
    final needsAction = (order.side == ChatSide.buying && order.status == OrderStatus.pending && order.paymentRef == null) ||
        (order.side == ChatSide.selling && order.status == OrderStatus.pending && order.paymentRef != null);
    return Semantics(
      button: true,
      label: 'Order ${order.number}, ${order.itemLabel}, ${order.status.label}, ${Fmt.peso(order.total)}',
      excludeSemantics: true,
      child: Material(
        color: AppColors.white,
        shape: RoundedRectangleBorder(borderRadius: Radii.card, side: BorderSide(color: needsAction ? AppColors.amber : AppColors.linen, width: needsAction ? 1.5 : 1)),
        child: InkWell(
          borderRadius: Radii.card,
          onTap: () => context.push('/order/${order.number}'),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Expanded(child: Text(order.number, style: AppText.label.copyWith(fontWeight: FontWeight.w700))),
                StatusPill(order.status.label, tone: order.status.tone, filled: true),
              ]),
              const SizedBox(height: 10),
              Row(children: [
                if (p != null) ProductPhoto(product: p, width: 56, height: 56, radius: 10),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('${order.itemLabel} × ${order.quantity}', style: AppText.bodyStrong.copyWith(fontSize: 13.5), maxLines: 1, overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 2),
                    Text('${order.side == ChatSide.buying ? 'From' : 'For'} ${order.counterpart} · ${order.placedOn}', style: AppText.caption, maxLines: 1, overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 4),
                    Row(children: [
                      Text(Fmt.peso(order.total), style: AppText.price),
                      if (order.isCustom) ...[const SizedBox(width: 8), const StatusPill('Custom', tone: Tone.seller)],
                    ]),
                  ]),
                ),
                const CraftIcon(CraftIcons.chevron, size: 18, color: AppColors.grayBrown),
              ]),
              if (needsAction) ...[
                const SizedBox(height: 10),
                Row(children: [
                  const CraftIcon(CraftIcons.info, size: 16, color: AppColors.amberText),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(order.side == ChatSide.buying ? 'Upload your payment proof' : 'Check and confirm the payment',
                        style: AppText.label.copyWith(color: AppColors.amberText, fontWeight: FontWeight.w700)),
                  ),
                ]),
              ],
            ]),
          ),
        ),
      ),
    );
  }
}

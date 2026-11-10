import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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

/// Supporting screen – Order details: status timeline, items, payment proof,
/// delivery, and the next action for the buyer or seller.
class OrderDetailsScreen extends ConsumerWidget {
  const OrderDetailsScreen({super.key, required this.number});
  final String number;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final o = ref.watch(orderProvider(number));
    if (o == null) return const Scaffold(appBar: ScreenHeader(title: 'Order', fallback: '/orders'), body: SizedBox());
    final p = ref.watch(productProvider(o.productId));
    final steps = [
      OrderStatus.pending,
      OrderStatus.confirmed,
      if (o.isCustom || o.history.any((e) => e.status == OrderStatus.inProduction)) OrderStatus.inProduction,
      OrderStatus.shipped,
      OrderStatus.delivered,
    ];
    final currentIndex = steps.indexOf(o.status);

    return Scaffold(
      appBar: ScreenHeader(title: 'Order details', subtitle: o.number, fallback: '/orders'),
      body: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(Insets.screen, 4, Insets.screen, 24),
          child: ResponsiveCenter(
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              _Card(children: [
                Row(children: [
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('Status', style: AppText.caption),
                      Text(o.status.label, style: AppText.screenTitle.copyWith(fontWeight: FontWeight.w800)),
                    ]),
                  ),
                  StatusPill(o.isCustom ? 'Custom order' : 'Ready-made', tone: o.isCustom ? Tone.seller : Tone.info, filled: true),
                ]),
                const SizedBox(height: 14),
                _ProgressBar(steps: steps, current: currentIndex),
              ]),
              const SizedBox(height: 12),
              if (p != null)
                ProductSummaryRow(
                  product: p,
                  title: '${o.itemLabel} × ${o.quantity}',
                  subtitle: '${o.side == ChatSide.buying ? 'From' : 'For'} ${o.counterpart} · placed ${o.placedOn}',
                  trailing: Text(Fmt.peso(o.total), style: AppText.price),
                  onTap: () => context.push('/product/${p.id}'),
                ),
              const SizedBox(height: 12),
              _Card(title: 'Payment', children: [
                _kv('Method', o.paymentMethod),
                _kv('Reference no.', o.paymentRef ?? 'Not uploaded yet'),
                _kv('Total', Fmt.peso(o.total), strong: true),
              ]),
              const SizedBox(height: 12),
              _Card(title: 'Delivery', children: [
                _kv('Method', o.fulfillment),
                _kv(o.side == ChatSide.buying ? 'Seller' : 'Buyer', o.counterpart),
              ]),
              const SizedBox(height: 12),
              _Card(title: 'Timeline', children: [
                for (var i = o.history.length - 1; i >= 0; i--) _HistoryRow(event: o.history[i], latest: i == o.history.length - 1),
              ]),
              const SizedBox(height: 18),
              ..._actions(context, ref, o),
              if (o.chatId != null) ...[
                const SizedBox(height: 10),
                AppButton(label: 'Open chat', icon: CraftIcons.chat, kind: ButtonKind.outline, onPressed: () => context.push('/chat/${o.chatId}')),
              ],
            ]),
          ),
        ),
      ),
    );
  }

  List<Widget> _actions(BuildContext context, WidgetRef ref, Order o) {
    final c = ref.read(ordersProvider.notifier);
    if (o.side == ChatSide.buying) {
      if (o.status == OrderStatus.pending && o.paymentRef == null) {
        return [
          const InfoNote('Pay the seller through GCash or bank transfer, then upload the screenshot. Reused reference numbers are rejected.'),
          const SizedBox(height: 12),
          AppButton(label: 'Upload payment proof', icon: CraftIcons.camera, onPressed: () => _uploadProof(context, ref, o)),
        ];
      }
      if (o.status == OrderStatus.pending) {
        return [const InfoNote('Payment proof sent. Waiting for the seller to confirm it.', tone: Tone.warning, icon: CraftIcons.clock)];
      }
      if (o.status == OrderStatus.shipped) {
        return [
          AppButton(
            label: 'I received my order',
            icon: CraftIcons.check,
            onPressed: () async {
              c.advance(o.number, OrderStatus.delivered, note: 'You confirmed receipt.');
              await _review(context);
            },
          ),
        ];
      }
      if (o.status == OrderStatus.delivered) {
        return [
          AppButton(label: 'Report a problem', kind: ButtonKind.danger, icon: CraftIcons.info, onPressed: () => showComingSoon(context, 'Disputes')),
        ];
      }
      return [];
    }
    // Selling side
    switch (o.status) {
      case OrderStatus.pending:
        if (o.paymentRef == null) return [const InfoNote('Waiting for the buyer\'s payment proof.', tone: Tone.warning, icon: CraftIcons.clock)];
        return [
          InfoNote('GCash reference ${o.paymentRef}. Check that ${Fmt.peso(o.total)} arrived before confirming.'),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(child: AppButton(label: 'Confirm payment', onPressed: () => c.advance(o.number, OrderStatus.confirmed, note: 'Payment confirmed by you.'))),
            const SizedBox(width: 10),
            Expanded(child: AppButton(label: 'Reject', kind: ButtonKind.danger, onPressed: () => showComingSoon(context, 'Rejecting a payment with a reason'))),
          ]),
        ];
      case OrderStatus.confirmed:
        return [
          AppButton(label: 'Start making it', kind: ButtonKind.clayOutline, onPressed: () => c.advance(o.number, OrderStatus.inProduction, note: 'Work started.')),
          const SizedBox(height: 10),
          AppButton(label: 'Mark as shipped', icon: CraftIcons.truck, onPressed: () => c.advance(o.number, OrderStatus.shipped)),
        ];
      case OrderStatus.inProduction:
        return [AppButton(label: 'Mark as shipped', icon: CraftIcons.truck, onPressed: () => c.advance(o.number, OrderStatus.shipped))];
      default:
        return [];
    }
  }

  Future<void> _uploadProof(BuildContext context, WidgetRef ref, Order o) async {
    final ctrl = TextEditingController();
    final refNo = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(ctx).bottom),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(Insets.screen, 0, Insets.screen, 16),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text('Upload payment proof', style: AppText.screenTitle),
              const SizedBox(height: 4),
              Text('Amount to pay: ${Fmt.peso(o.total)}', style: AppText.caption.copyWith(fontSize: 13)),
              const SizedBox(height: 14),
              DashedAddBox(label: 'Add the GCash screenshot', onTap: () => showComingSoon(ctx, 'Photo upload')),
              const SizedBox(height: 12),
              Text('Reference number', style: AppText.label),
              const SizedBox(height: 6),
              TextField(
                controller: ctrl,
                autofocus: true,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9 ]'))],
                decoration: const InputDecoration(hintText: '5012 345 678901'),
              ),
              const SizedBox(height: 16),
              AppButton(label: 'Send proof', icon: CraftIcons.send, onPressed: () => Navigator.pop(ctx, ctrl.text.trim())),
            ]),
          ),
        ),
      ),
    );
    if (refNo != null && refNo.isNotEmpty) {
      ref.read(ordersProvider.notifier).uploadProof(o.number, refNo);
      if (context.mounted) showMessage(context, 'Payment proof sent to ${o.counterpart}.');
    }
  }

  Future<void> _review(BuildContext context) async {
    var stars = 5;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(ctx).bottom),
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(Insets.screen, 0, Insets.screen, 16),
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Text('Rate this seller', style: AppText.screenTitle),
                const SizedBox(height: 12),
                Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  for (var i = 1; i <= 5; i++)
                    IconButton(
                      tooltip: '$i star${i == 1 ? '' : 's'}',
                      onPressed: () => setS(() => stars = i),
                      icon: Icon(i <= stars ? Icons.star_rounded : Icons.star_outline_rounded, size: 38, color: AppColors.softHoney),
                    ),
                ]),
                const SizedBox(height: 8),
                const TextField(maxLines: 3, decoration: InputDecoration(hintText: 'What did you like? (optional)')),
                const SizedBox(height: 16),
                AppButton(
                  label: 'Post review',
                  onPressed: () {
                    Navigator.pop(ctx);
                    showMessage(context, 'Thanks! Your $stars-star review was posted.');
                  },
                ),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

Widget _kv(String k, String v, {bool strong = false}) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(child: Text(k, style: AppText.body.copyWith(fontSize: 13.5, color: AppColors.grayBrown))),
        Flexible(child: Text(v, style: strong ? AppText.price : AppText.label, textAlign: TextAlign.right)),
      ]),
    );

class _Card extends StatelessWidget {
  const _Card({required this.children, this.title});
  final List<Widget> children;
  final String? title;
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: AppColors.white, borderRadius: Radii.card, border: Border.all(color: AppColors.linen)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          if (title != null) ...[Semantics(header: true, child: Text(title!, style: AppText.section.copyWith(fontSize: 15))), const SizedBox(height: 6)],
          ...children,
        ]),
      );
}

class _ProgressBar extends StatelessWidget {
  const _ProgressBar({required this.steps, required this.current});
  final List<OrderStatus> steps;
  final int current;
  static const _short = {
    OrderStatus.pending: 'Paid',
    OrderStatus.confirmed: 'Confirmed',
    OrderStatus.inProduction: 'Making',
    OrderStatus.shipped: 'Shipped',
    OrderStatus.delivered: 'Received',
  };
  @override
  Widget build(BuildContext context) => Semantics(
        label: 'Step ${current + 1} of ${steps.length}',
        excludeSemantics: true,
        child: Row(children: [
          for (var i = 0; i < steps.length; i++) ...[
            Expanded(
              child: Column(children: [
                Container(
                  height: 6,
                  decoration: BoxDecoration(color: i <= current ? AppColors.fern : AppColors.linen, borderRadius: Radii.pill),
                ),
                const SizedBox(height: 6),
                Text(_short[steps[i]]!, style: AppText.small.copyWith(fontSize: 10.5, color: i <= current ? AppColors.darkCocoa : AppColors.grayBrown)),
              ]),
            ),
            if (i < steps.length - 1) const SizedBox(width: 4),
          ],
        ]),
      );
}

class _HistoryRow extends StatelessWidget {
  const _HistoryRow({required this.event, required this.latest});
  final OrderEvent event;
  final bool latest;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
            width: 10,
            height: 10,
            margin: const EdgeInsets.only(top: 5),
            decoration: BoxDecoration(color: latest ? AppColors.fern : AppColors.linen, shape: BoxShape.circle),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Expanded(child: Text(event.status.label, style: AppText.bodyStrong.copyWith(fontSize: 13.5))),
                Text(event.when, style: AppText.caption.copyWith(fontSize: 11.5)),
              ]),
              if (event.note != null) Text(event.note!, style: AppText.caption),
            ]),
          ),
        ]),
      );
}

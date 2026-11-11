import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/format.dart';
import '../../data/models.dart';
import '../../data/providers.dart';
import '../../shared/widgets/action_helpers.dart';
import '../../shared/widgets/common.dart';
import '../../shared/widgets/craft_icon.dart';
import '../../shared/widgets/product_widgets.dart';

/// Order details: status timeline, item, payment proof, and the next action
/// for the buyer or seller. Every action is saved in PostgreSQL and checked
/// there (database/04_orders_and_custom_orders.sql).
class OrderDetailsScreen extends ConsumerStatefulWidget {
  const OrderDetailsScreen({super.key, required this.number});
  final String number;
  @override
  ConsumerState<OrderDetailsScreen> createState() => _OrderDetailsScreenState();
}

class _OrderDetailsScreenState extends ConsumerState<OrderDetailsScreen> {
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    // The other person may have changed it since the list loaded; the old data stays on screen while it reloads.
    Future.microtask(() {
      if (mounted) ref.invalidate(ordersDataProvider);
    });
  }

  OrderActions get _actions => ref.read(orderActionsProvider);

  Future<void> _run(Future<void> Function() action, {String? success}) async {
    setState(() => _busy = true);
    await runWithMessage(context, action, success: success);
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final o = ref.watch(orderProvider(widget.number));
    final loading = ref.watch(ordersDataProvider).isLoading;
    if (o == null) {
      return Scaffold(
        appBar: const ScreenHeader(title: 'Order', fallback: '/orders'),
        body: loading
            ? const Center(child: CircularProgressIndicator())
            : EmptyState(icon: CraftIcons.orders, title: 'Order not found', message: 'It may belong to another account.', actionLabel: 'My orders', onAction: () => context.go('/orders')),
      );
    }
    final p = ref.watch(productProvider(o.productId));
    final steps = [
      OrderStatus.pending,
      OrderStatus.confirmed,
      if (o.isCustom || o.history.any((e) => e.status == OrderStatus.inProduction)) OrderStatus.inProduction,
      OrderStatus.shipped,
      OrderStatus.delivered,
    ];
    final currentIndex = steps.indexOf(o.status);
    final paymentText = switch (o.paymentStatus) {
      null => o.paymentRef == null ? 'Not uploaded yet' : 'Sent',
      PaymentStatus.submitted => 'Sent · waiting for the seller',
      PaymentStatus.verified => 'Confirmed by the seller',
      PaymentStatus.rejected => 'Rejected · send a new proof',
    };

    return Scaffold(
      appBar: ScreenHeader(title: 'Order details', subtitle: o.number, fallback: '/orders'),
      body: RefreshIndicator(
        onRefresh: () => ref.refresh(ordersDataProvider.future),
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
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
                if (o.status != OrderStatus.cancelled) ...[
                  const SizedBox(height: 14),
                  _ProgressBar(steps: steps, current: currentIndex),
                ],
              ]),
              const SizedBox(height: 12),
              if (p != null)
                ProductSummaryRow(
                  product: p,
                  title: '${o.itemLabel} × ${o.quantity}',
                  subtitle: '${o.side == ChatSide.buying ? 'From' : 'For'} ${o.counterpart} · placed ${o.placedOn}',
                  trailing: Text(Fmt.peso(o.total), style: AppText.price),
                  onTap: () => context.push('/product/${p.id}'),
                )
              else
                _Card(children: [
                  _kv('Item', '${o.itemLabel} × ${o.quantity}'),
                  _kv(o.side == ChatSide.buying ? 'From' : 'For', o.counterpart),
                ]),
              const SizedBox(height: 12),
              _Card(title: 'Payment', children: [
                _kv('Method', o.paymentMethod),
                _kv('Reference no.', o.paymentRef ?? '—'),
                _kv('Proof', paymentText),
                _kv('Total', Fmt.peso(o.total), strong: true),
                if (o.proofPath != null) ...[const SizedBox(height: 8), PrivateImage(path: o.proofPath!, height: 180)],
              ]),
              const SizedBox(height: 12),
              _Card(title: 'Delivery', children: [
                _kv('Method', o.fulfillment),
                _kv(o.side == ChatSide.buying ? 'Seller' : 'Buyer', o.counterpart),
                if (o.dueDate != null) _kv('Due', Fmt.date(o.dueDate!)),
                if (o.requestCode != null) _kv('From request', o.requestCode!),
              ]),
              const SizedBox(height: 12),
              _Card(title: 'Timeline', children: [
                for (var i = o.history.length - 1; i >= 0; i--) _HistoryRow(event: o.history[i], latest: i == o.history.length - 1),
              ]),
              const SizedBox(height: 18),
              ..._actionsFor(o),
              if (o.requestCode != null) ...[
                const SizedBox(height: 10),
                AppButton(label: 'View request ${o.requestCode}', kind: ButtonKind.outline, onPressed: () => context.push('/request/${o.requestCode}')),
              ],
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

  List<Widget> _actionsFor(Order o) {
    final cancel = AppButton(label: 'Cancel order', kind: ButtonKind.danger, onPressed: _busy ? null : () => _cancel(o));
    if (o.side == ChatSide.buying) {
      if (o.needsProof) {
        return [
          if (o.paymentStatus == PaymentStatus.rejected)
            const InfoNote('The seller rejected your last proof. Check the reason in the timeline and send a new one.', tone: Tone.error)
          else
            InfoNote(o.reservedUntil != null
                ? 'Pay ${Fmt.peso(o.total)} by GCash or bank transfer, then upload the receipt before ${Fmt.stamp(o.reservedUntil!)}, or the reserved stock is released.'
                : 'Pay ${Fmt.peso(o.total)} by GCash or bank transfer, then upload the receipt. Reused reference numbers and screenshots are rejected.'),
          const SizedBox(height: 12),
          AppButton(label: 'Upload payment proof', icon: CraftIcons.camera, loading: _busy, onPressed: () => _uploadProof(o)),
          const SizedBox(height: 10),
          cancel,
        ];
      }
      if (o.proofWaiting) {
        return [const InfoNote('Payment proof sent. Waiting for the seller to confirm it.', tone: Tone.warning, icon: CraftIcons.clock)];
      }
      if (o.status == OrderStatus.shipped) {
        return [
          AppButton(
            label: 'I received my order',
            icon: CraftIcons.check,
            loading: _busy,
            onPressed: () async {
              setState(() => _busy = true);
              final ok = await runWithMessage(context, () => _actions.advance(o, OrderStatus.delivered));
              if (mounted) setState(() => _busy = false);
              if (ok && mounted) await _review(o);
            },
          ),
        ];
      }
      if (o.status == OrderStatus.delivered) {
        return [
          if (!o.reviewed) ...[
            AppButton(label: 'Rate this item', icon: CraftIcons.star, kind: ButtonKind.honey, onPressed: () => _review(o)),
            const SizedBox(height: 10),
          ],
          AppButton(label: 'Report a problem', kind: ButtonKind.danger, icon: CraftIcons.info, onPressed: () => showComingSoon(context, 'Disputes')),
        ];
      }
      return [];
    }
    // Selling side
    switch (o.status) {
      case OrderStatus.pending:
        if (!o.proofWaiting) {
          return [
            InfoNote(o.paymentStatus == PaymentStatus.rejected ? 'You rejected the last proof. Waiting for a new one from the buyer.' : 'Waiting for the buyer\'s payment proof.',
                tone: Tone.warning, icon: CraftIcons.clock),
            const SizedBox(height: 12),
            cancel,
          ];
        }
        return [
          InfoNote('Reference ${o.paymentRef}. Check that ${Fmt.peso(o.total)} arrived in your GCash or bank account before confirming.'),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(
              child: AppButton(
                label: 'Confirm payment',
                loading: _busy,
                onPressed: () => _run(() => _actions.reviewPayment(o, accept: true), success: 'Payment confirmed. You can start the order.'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(child: AppButton(label: 'Reject', kind: ButtonKind.danger, onPressed: _busy ? null : () => _rejectProof(o))),
          ]),
        ];
      case OrderStatus.confirmed:
        return [
          AppButton(
              label: 'Start making it',
              kind: ButtonKind.clayOutline,
              loading: _busy,
              onPressed: () => _run(() => _actions.advance(o, OrderStatus.inProduction), success: 'Marked as in production.')),
          const SizedBox(height: 10),
          AppButton(label: 'Mark as shipped', icon: CraftIcons.truck, onPressed: _busy ? null : () => _ship(o)),
        ];
      case OrderStatus.inProduction:
        return [AppButton(label: 'Mark as shipped', icon: CraftIcons.truck, loading: _busy, onPressed: () => _ship(o))];
      case OrderStatus.shipped:
        return [const InfoNote('Shipped. The order completes when the buyer confirms they received it.', icon: CraftIcons.truck)];
      default:
        return [];
    }
  }

  Future<void> _ship(Order o) async {
    final note = await askForText(context,
        title: 'Mark as shipped', subtitle: 'Add the courier and tracking number, or the meet-up details.', hint: 'Example: J&T tracking 7701 2345 8890', button: 'Mark as shipped');
    if (note == null) return;
    await _run(() => _actions.advance(o, OrderStatus.shipped, note: note), success: 'Marked as shipped.');
  }

  Future<void> _cancel(Order o) async {
    final ok = await confirmAction(context,
        title: 'Cancel order ${o.number}?',
        message: o.side == ChatSide.buying ? 'Reserved items go back on sale. You cannot undo this.' : 'The buyer will see that you cancelled. You cannot undo this.',
        confirmLabel: 'Cancel order',
        danger: true);
    if (!ok) return;
    await _run(() => _actions.advance(o, OrderStatus.cancelled), success: 'Order cancelled.');
  }

  Future<void> _rejectProof(Order o) async {
    final reason = await askForText(context,
        title: 'Reject payment proof', subtitle: 'Tell the buyer what is wrong so they can send a new one.', hint: 'Example: The amount received was ₱500, not ₱680.', button: 'Reject proof');
    if (reason == null) return;
    await _run(() => _actions.reviewPayment(o, accept: false, reason: reason), success: 'Proof rejected. The buyer was asked for a new one.');
  }

  Future<void> _uploadProof(Order o) async {
    final result = await showModalBottomSheet<(String, PickedImage)>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _ProofSheet(total: o.total),
    );
    if (result == null) return;
    await _run(() => _actions.submitPayment(o, reference: result.$1, proof: result.$2), success: 'Payment proof sent to ${o.counterpart}.');
  }

  Future<void> _review(Order o) async {
    final result = await showModalBottomSheet<(int, String)>(context: context, isScrollControlled: true, builder: (_) => const _ReviewSheet());
    if (result == null) return;
    await _run(() => _actions.postReview(o, rating: result.$1, comment: result.$2), success: 'Thanks! Your ${result.$1}-star review was posted.');
  }
}

/// Buyer's payment proof: the receipt screenshot and its reference number.
class _ProofSheet extends StatefulWidget {
  const _ProofSheet({required this.total});
  final double total;
  @override
  State<_ProofSheet> createState() => _ProofSheetState();
}

class _ProofSheetState extends State<_ProofSheet> {
  final _ref = TextEditingController();
  PickedImage? _photo;
  String? _refError;
  bool _photoError = false;

  @override
  void dispose() {
    _ref.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(Insets.screen, 0, Insets.screen, 16),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text('Upload payment proof', style: AppText.screenTitle),
              const SizedBox(height: 4),
              Text('Amount to pay: ${Fmt.peso(widget.total)}', style: AppText.caption.copyWith(fontSize: 13)),
              const SizedBox(height: 14),
              if (_photo != null)
                Stack(children: [
                  ClipRRect(borderRadius: BorderRadius.circular(12), child: Image.memory(_photo!.bytes, height: 160, width: double.infinity, fit: BoxFit.cover)),
                  Positioned(
                    top: 6,
                    right: 6,
                    child: RoundIconButton(icon: CraftIcons.close, tooltip: 'Remove screenshot', background: AppColors.white, onPressed: () => setState(() => _photo = null)),
                  ),
                ])
              else
                DashedAddBox(
                  label: 'Add the GCash or bank screenshot',
                  onTap: () async {
                    final photo = await pickOnePhoto(context);
                    if (photo != null && mounted) {
                      setState(() {
                        _photo = photo;
                        _photoError = false;
                      });
                    }
                  },
                ),
              if (_photoError)
                Padding(
                  padding: const EdgeInsets.only(top: 6, left: 4),
                  child: Text('Add the receipt screenshot.', style: AppText.caption.copyWith(color: AppColors.brick)),
                ),
              const SizedBox(height: 12),
              Text('Reference number', style: AppText.label),
              const SizedBox(height: 6),
              TextField(
                controller: _ref,
                keyboardType: TextInputType.text,
                inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[A-Za-z0-9 -]'))],
                decoration: InputDecoration(hintText: '5012 345 678901', errorText: _refError),
              ),
              const SizedBox(height: 16),
              AppButton(
                label: 'Send proof',
                icon: CraftIcons.send,
                onPressed: () {
                  final ref = _ref.text.replaceAll(' ', '');
                  setState(() {
                    _refError = ref.length < 6 ? 'Enter the reference number from your receipt.' : null;
                    _photoError = _photo == null;
                  });
                  if (_refError != null || _photoError) return;
                  Navigator.pop(context, (ref, _photo!));
                },
              ),
            ]),
          ),
        ),
      );
}

class _ReviewSheet extends StatefulWidget {
  const _ReviewSheet();
  @override
  State<_ReviewSheet> createState() => _ReviewSheetState();
}

class _ReviewSheetState extends State<_ReviewSheet> {
  final _comment = TextEditingController();
  int _stars = 5;

  @override
  void dispose() {
    _comment.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(Insets.screen, 0, Insets.screen, 16),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text('Rate this item', style: AppText.screenTitle),
              const SizedBox(height: 12),
              Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                for (var i = 1; i <= 5; i++)
                  IconButton(
                    tooltip: '$i star${i == 1 ? '' : 's'}',
                    onPressed: () => setState(() => _stars = i),
                    icon: Icon(i <= _stars ? Icons.star_rounded : Icons.star_outline_rounded, size: 38, color: AppColors.softHoney),
                  ),
              ]),
              const SizedBox(height: 8),
              TextField(controller: _comment, maxLines: 3, maxLength: 500, decoration: const InputDecoration(hintText: 'What did you like? (optional)')),
              const SizedBox(height: 8),
              AppButton(label: 'Post review', onPressed: () => Navigator.pop(context, (_stars, _comment.text.trim()))),
            ]),
          ),
        ),
      );
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

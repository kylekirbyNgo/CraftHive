import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/format.dart';
import '../../data/models.dart';
import '../../data/providers.dart';
import '../../shared/widgets/common.dart';
import '../../shared/widgets/craft_icon.dart';
import '../../shared/widgets/product_widgets.dart';

/// Buy now: choose the quantity and place the order. In-stock items are
/// reserved for 24 hours while the buyer pays; out-of-stock items are made to order.
Future<void> showCheckout(BuildContext context, Product product, Seller seller) async {
  final number = await showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    builder: (_) => _CheckoutSheet(product: product, seller: seller),
  );
  if (number != null && context.mounted) {
    context.push('/order/$number');
    showMessage(context, 'Order $number placed. Pay the seller, then upload your proof.');
  }
}

class _CheckoutSheet extends ConsumerStatefulWidget {
  const _CheckoutSheet({required this.product, required this.seller});
  final Product product;
  final Seller seller;
  @override
  ConsumerState<_CheckoutSheet> createState() => _CheckoutSheetState();
}

class _CheckoutSheetState extends ConsumerState<_CheckoutSheet> {
  int _qty = 1;
  bool _busy = false;
  String? _error;

  Future<void> _place() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final number = await ref.read(orderActionsProvider).place(widget.product, _qty);
      if (mounted) Navigator.pop(context, number);
    } on AppFailure catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.product;
    final inStock = p.stock > 0;
    final ready = DateTime.now().add(Duration(days: p.leadDays));
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(Insets.screen, 0, Insets.screen, 16),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('Checkout', style: AppText.screenTitle),
          const SizedBox(height: 12),
          ProductSummaryRow(product: p, title: p.title, subtitle: '${widget.seller.name} · ${Fmt.peso(p.price)} each'),
          const SizedBox(height: 14),
          Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Quantity', style: AppText.label),
                const SizedBox(height: 6),
                QuantityStepper(value: _qty, max: inStock ? p.stock : 99, onChanged: (v) => setState(() => _qty = v)),
              ]),
            ),
            const SizedBox(width: 16),
            Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Text('Total', style: AppText.caption),
              Text(Fmt.peso(p.price * _qty), style: AppText.priceLarge),
            ]),
          ]),
          const SizedBox(height: 12),
          InfoNote(
            inStock
                ? '${p.stock} in stock. We hold your items for 24 hours. Pay the seller by GCash or bank transfer, then upload the receipt. Expected ready by ${Fmt.date(ready)}.'
                : 'Made to order: ready in about ${p.leadDays} days (${Fmt.date(ready)}). Pay the seller, then upload the receipt.',
            icon: CraftIcons.wallet,
          ),
          if (_error != null) ...[
            const SizedBox(height: 10),
            InfoNote(_error!, tone: Tone.error),
          ],
          const SizedBox(height: 14),
          AppButton(label: 'Place order · ${Fmt.peso(p.price * _qty)}', icon: CraftIcons.check, loading: _busy, onPressed: _place),
        ]),
      ),
    );
  }
}

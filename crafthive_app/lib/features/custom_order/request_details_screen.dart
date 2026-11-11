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

/// One custom request: what the buyer asked for, every quote version, and the
/// next step. The seller sends a quote or declines; the buyer accepts (which
/// creates the order), asks for changes, or cancels.
class RequestDetailsScreen extends ConsumerStatefulWidget {
  const RequestDetailsScreen({super.key, required this.code});
  final String code;
  @override
  ConsumerState<RequestDetailsScreen> createState() => _RequestDetailsScreenState();
}

class _RequestDetailsScreenState extends ConsumerState<RequestDetailsScreen> {
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    // The other person may have changed it since the list loaded; the old data stays on screen while it reloads.
    Future.microtask(() {
      if (mounted) ref.invalidate(requestsDataProvider);
    });
  }

  CustomOrderActions get _actions => ref.read(customOrderActionsProvider);

  Future<void> _run(Future<void> Function() action, {String? success}) async {
    setState(() => _busy = true);
    await runWithMessage(context, action, success: success);
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _sendQuote(CustomRequest r, Product? p) async {
    final result = await showModalBottomSheet<_QuoteInput>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _QuoteSheet(request: r, basePrice: p?.price ?? 0),
    );
    if (result == null) return;
    await _run(() => _actions.sendQuote(r, price: result.price, readyBy: result.readyBy, message: result.message),
        success: 'Quote sent to ${r.counterpart}.');
  }

  Future<void> _decline(CustomRequest r) async {
    final reason = await askForText(context,
        title: 'Decline request', subtitle: 'The buyer will see your reason.', hint: 'Example: I am fully booked until January.', button: 'Decline request');
    if (reason == null) return;
    await _run(() => _actions.decline(r, reason), success: 'Request ${r.code} declined.');
  }

  Future<void> _accept(CustomRequest r, QuoteOffer q) async {
    final ok = await confirmAction(context,
        title: 'Accept this quote?',
        message: '${Fmt.peso(q.price)} for ${r.quantity} × ${r.productTitle}, ready by ${Fmt.date(q.readyBy)}. '
            'This becomes a binding order and books a slot in the maker\'s schedule. You pay after accepting.',
        confirmLabel: 'Accept and order');
    if (!ok || !mounted) return;
    setState(() => _busy = true);
    try {
      final number = await _actions.accept(q);
      if (!mounted) return;
      showMessage(context, 'Order $number created. Pay the seller, then upload your proof.');
      context.push('/order/$number');
    } on AppFailure catch (e) {
      if (mounted) showMessage(context, e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _askChanges(QuoteOffer q) async {
    final note = await askForText(context,
        title: 'Ask for changes', subtitle: 'Tell the maker what to change. They can send a new quote.', hint: 'Example: Can it be ready by Dec 15 for ₱1,000?', button: 'Send');
    if (note == null) return;
    await _run(() => _actions.askForChanges(q, note), success: 'Sent. The maker can now send a new quote.');
  }

  Future<void> _cancel(CustomRequest r) async {
    final ok = await confirmAction(context,
        title: 'Cancel this request?', message: 'The maker will stop working on a quote for ${r.code}.', confirmLabel: 'Cancel request', danger: true);
    if (!ok) return;
    await _run(() => _actions.cancel(r), success: 'Request ${r.code} cancelled.');
  }

  @override
  Widget build(BuildContext context) {
    final r = ref.watch(requestProvider(widget.code));
    final loading = ref.watch(requestsDataProvider).isLoading;
    if (r == null) {
      return Scaffold(
        appBar: const ScreenHeader(title: 'Custom request', fallback: '/requests'),
        body: loading
            ? const Center(child: CircularProgressIndicator())
            : EmptyState(icon: CraftIcons.edit, title: 'Request not found', message: 'It may have been removed.', actionLabel: 'All requests', onAction: () => context.go('/requests')),
      );
    }
    final p = ref.watch(productProvider(r.productId));
    final selling = r.side == ChatSide.selling;
    final open = r.openQuote;

    return Scaffold(
      appBar: ScreenHeader(title: 'Custom request', subtitle: r.code, fallback: '/requests'),
      body: RefreshIndicator(
        onRefresh: () => ref.refresh(requestsDataProvider.future),
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(Insets.screen, 4, Insets.screen, 28),
          child: ResponsiveCenter(
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              _Card(children: [
                Row(children: [
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('Status', style: AppText.caption),
                      Text(r.status.label, style: AppText.screenTitle.copyWith(fontWeight: FontWeight.w800)),
                    ]),
                  ),
                  StatusPill(selling ? 'Request for my store' : 'My request', tone: selling ? Tone.seller : Tone.info, filled: true),
                ]),
                const SizedBox(height: 6),
                Text('${selling ? 'From' : 'To'} ${r.counterpart} · sent ${Fmt.stamp(r.sentAt)}', style: AppText.caption),
              ]),
              const SizedBox(height: 12),
              if (p != null)
                ProductSummaryRow(
                  product: p,
                  title: '${r.productTitle} × ${r.quantity}',
                  subtitle: 'Base price ${Fmt.peso(p.price)} each',
                  onTap: () => context.push('/product/${p.id}'),
                ),
              const SizedBox(height: 12),
              _Card(title: 'What the buyer asked for', children: [
                Text(r.description, style: AppText.body.copyWith(fontSize: 13.5, height: 1.5)),
                if (r.options.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Wrap(spacing: 6, runSpacing: 6, children: [for (final o in r.options) StatusPill(o, tone: Tone.seller, filled: true)]),
                ],
                const SizedBox(height: 8),
                _kv('Quantity', '${r.quantity}'),
                _kv('Budget', r.budget == null ? 'Not given' : Fmt.peso(r.budget!)),
                _kv('Needed by', Fmt.date(r.neededBy)),
                if (r.imagePaths.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text('Reference photo', style: AppText.label),
                  const SizedBox(height: 6),
                  PrivateImage(path: r.imagePaths.first),
                ],
              ]),
              const SizedBox(height: 12),
              _Card(title: 'Quotes', children: [
                if (r.quotes.isEmpty)
                  Text(selling ? 'You have not sent a quote yet.' : 'The maker has not sent a quote yet.', style: AppText.caption.copyWith(fontSize: 13))
                else
                  for (final q in r.quotes.reversed) _QuoteRow(quote: q, selling: selling),
              ]),
              const SizedBox(height: 18),
              ..._actionsFor(r, p, open),
            ]),
          ),
        ),
      ),
    );
  }

  List<Widget> _actionsFor(CustomRequest r, Product? p, QuoteOffer? open) {
    if (r.status == RequestStatus.accepted && r.orderNumber != null) {
      return [AppButton(label: 'View order ${r.orderNumber}', icon: CraftIcons.orders, onPressed: () => context.push('/order/${r.orderNumber}'))];
    }
    if (!r.status.isOpen) return const [];
    if (r.side == ChatSide.selling) {
      final asked = r.latestQuote?.status == OfferStatus.changesRequested;
      return [
        if (asked) ...[
          InfoNote('The buyer asked for changes: "${r.latestQuote!.declineReason ?? 'no note'}". Send a new quote.', tone: Tone.warning),
          const SizedBox(height: 12),
        ],
        AppButton(label: r.quotes.isEmpty || asked ? 'Send a quote' : 'Send a new quote', icon: CraftIcons.send, loading: _busy, onPressed: () => _sendQuote(r, p)),
        const SizedBox(height: 10),
        AppButton(label: 'Decline request', kind: ButtonKind.danger, onPressed: _busy ? null : () => _decline(r)),
      ];
    }
    return [
      if (open != null) ...[
        const InfoNote('Accepting makes this a binding order. You pay the maker only after you accept.'),
        const SizedBox(height: 12),
        AppButton(label: 'Accept quote · ${Fmt.peso(open.price)}', icon: CraftIcons.check, loading: _busy, onPressed: () => _accept(r, open)),
        const SizedBox(height: 10),
        AppButton(label: 'Ask for changes', kind: ButtonKind.outline, onPressed: _busy ? null : () => _askChanges(open)),
        const SizedBox(height: 10),
      ] else ...[
        const InfoNote('Waiting for the maker to reply with a price.', tone: Tone.warning, icon: CraftIcons.clock),
        const SizedBox(height: 12),
      ],
      AppButton(label: 'Cancel request', kind: ButtonKind.danger, onPressed: _busy ? null : () => _cancel(r)),
    ];
  }
}

class _QuoteRow extends StatelessWidget {
  const _QuoteRow({required this.quote, required this.selling});
  final QuoteOffer quote;
  final bool selling;
  @override
  Widget build(BuildContext context) {
    final q = quote;
    final declined = q.status == OfferStatus.declined;
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 5),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: q.status == OfferStatus.sent ? AppColors.tealTint : AppColors.lightSand,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: q.status == OfferStatus.sent ? AppColors.slateTeal : AppColors.linen),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: Text(declined ? 'Version ${q.version} · declined' : 'Version ${q.version}', style: AppText.label.copyWith(fontWeight: FontWeight.w700))),
          StatusPill(q.status.label, tone: q.status.tone, filled: true),
        ]),
        const SizedBox(height: 6),
        if (!declined) ...[
          Row(children: [
            Text(Fmt.peso(q.price), style: AppText.price),
            const SizedBox(width: 10),
            Expanded(child: Text('ready by ${Fmt.date(q.readyBy)}', style: AppText.caption.copyWith(fontSize: 13))),
          ]),
          if (q.message != null) ...[const SizedBox(height: 4), Text(q.message!, style: AppText.body.copyWith(fontSize: 13))],
        ],
        if (q.declineReason != null) ...[
          const SizedBox(height: 4),
          Text(
            q.status == OfferStatus.changesRequested ? '${selling ? 'Buyer' : 'You'} asked: ${q.declineReason}' : 'Reason: ${q.declineReason}',
            style: AppText.caption.copyWith(fontSize: 12.5, color: AppColors.darkCocoa),
          ),
        ],
        const SizedBox(height: 2),
        Text('Sent ${Fmt.stamp(q.createdAt)}', style: AppText.caption.copyWith(fontSize: 11.5)),
      ]),
    );
  }
}

class _QuoteInput {
  const _QuoteInput(this.price, this.readyBy, this.message);
  final double price;
  final DateTime readyBy;
  final String? message;
}

/// Seller's quote form: total price, ready date and an optional note.
class _QuoteSheet extends StatefulWidget {
  const _QuoteSheet({required this.request, required this.basePrice});
  final CustomRequest request;
  final double basePrice;
  @override
  State<_QuoteSheet> createState() => _QuoteSheetState();
}

class _QuoteSheetState extends State<_QuoteSheet> {
  late final _price = TextEditingController(
      text: (widget.request.latestQuote?.price ?? widget.basePrice * widget.request.quantity).toStringAsFixed(0));
  final _note = TextEditingController();
  late DateTime _ready = widget.request.neededBy.isAfter(DateTime.now()) ? widget.request.neededBy : DateTime.now().add(const Duration(days: 7));
  String? _error;

  @override
  void dispose() {
    _price.dispose();
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.request;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(Insets.screen, 0, Insets.screen, 16),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text('Send a quote', style: AppText.screenTitle),
            const SizedBox(height: 4),
            Text('${r.quantity} × ${r.productTitle} · buyer needs it by ${Fmt.date(r.neededBy)}${r.budget == null ? '' : ' · budget ${Fmt.peso(r.budget!)}'}',
                style: AppText.caption.copyWith(fontSize: 13)),
            const SizedBox(height: 14),
            Text('Total price', style: AppText.label),
            const SizedBox(height: 6),
            TextField(
              controller: _price,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
              decoration: InputDecoration(prefixText: '₱ ', errorText: _error),
            ),
            const SizedBox(height: 12),
            Text('Ready by', style: AppText.label),
            const SizedBox(height: 6),
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(Insets.fieldHeight), alignment: Alignment.centerLeft),
              icon: const CraftIcon(CraftIcons.calendar, size: 18, color: AppColors.grayBrown),
              label: Text(Fmt.date(_ready), style: AppText.body.copyWith(fontSize: 15)),
              onPressed: () async {
                final now = DateTime.now();
                final d = await showDatePicker(context: context, initialDate: _ready, firstDate: now, lastDate: now.add(const Duration(days: 365)), helpText: 'Ready by');
                if (d != null) setState(() => _ready = d);
              },
            ),
            if (_ready.isAfter(r.neededBy)) ...[
              const SizedBox(height: 6),
              Text('This is after the date the buyer needs it.', style: AppText.caption.copyWith(color: AppColors.amberText)),
            ],
            const SizedBox(height: 12),
            Text('Note (optional)', style: AppText.label),
            const SizedBox(height: 6),
            TextField(controller: _note, maxLines: 2, maxLength: 300, decoration: const InputDecoration(hintText: 'Example: Includes gift wrapping.')),
            const SizedBox(height: 8),
            AppButton(
              label: 'Send quote',
              icon: CraftIcons.send,
              onPressed: () {
                final price = double.tryParse(_price.text);
                if (price == null || price <= 0) {
                  setState(() => _error = 'Enter a price above zero.');
                  return;
                }
                Navigator.pop(context, _QuoteInput(price, _ready, _note.text.trim().isEmpty ? null : _note.text.trim()));
              },
            ),
          ]),
        ),
      ),
    );
  }
}

Widget _kv(String k, String v) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(children: [
        Expanded(child: Text(k, style: AppText.body.copyWith(fontSize: 13.5, color: AppColors.grayBrown))),
        Text(v, style: AppText.label),
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
          if (title != null) ...[Semantics(header: true, child: Text(title!, style: AppText.section.copyWith(fontSize: 15))), const SizedBox(height: 8)],
          ...children,
        ]),
      );
}

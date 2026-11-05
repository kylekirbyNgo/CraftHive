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

/// Screen 8 – Chat: seller name and online status, the product being discussed,
/// message bubbles, quote cards with Confirm order / Ask for changes, photo attach and send.
class ChatScreen extends ConsumerStatefulWidget {
  const ChatScreen({super.key, required this.threadId});
  final String threadId;
  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen> {
  final _input = TextEditingController();
  final _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(chatsProvider.notifier).markRead(widget.threadId);
      _toBottom(jump: true);
    });
  }

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _toBottom({bool jump = false}) {
    if (!_scroll.hasClients) return;
    final target = _scroll.position.maxScrollExtent;
    jump ? _scroll.jumpTo(target) : _scroll.animateTo(target, duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
  }

  void _send() {
    final text = _input.text.trim();
    if (text.isEmpty) return;
    ref.read(chatsProvider.notifier).send(widget.threadId, text);
    _input.clear();
    WidgetsBinding.instance.addPostFrameCallback((_) => _toBottom());
  }

  void _onQuote(QuoteStatus status) {
    ref.read(chatsProvider.notifier).setQuoteStatus(widget.threadId, status);
    WidgetsBinding.instance.addPostFrameCallback((_) => _toBottom());
    if (status == QuoteStatus.accepted) {
      final order = ref.read(ordersProvider).where((o) => o.chatId == widget.threadId).firstOrNull;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(
          content: const Text('Order confirmed. Upload your payment proof to get started.'),
          action: order == null ? null : SnackBarAction(label: 'View order', textColor: AppColors.softHoney, onPressed: () => context.push('/order/${order.number}')),
        ));
    }
  }

  Future<void> _composeQuote(ChatThread t, Product? p) async {
    final result = await showModalBottomSheet<(Quote, String)>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _QuoteSheet(defaultItem: p?.title ?? 'Custom item', basePrice: p?.price ?? 0),
    );
    if (result == null) return;
    ref.read(chatsProvider.notifier).sendQuote(t.id, result.$1, result.$2);
    WidgetsBinding.instance.addPostFrameCallback((_) => _toBottom());
  }

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(chatsProvider).where((x) => x.id == widget.threadId).firstOrNull;
    if (t == null) {
      return Scaffold(appBar: const ScreenHeader(title: 'Chat', fallback: '/messages'), body: EmptyState(icon: CraftIcons.chat, title: 'Chat not found', message: 'This conversation is no longer available.', actionLabel: 'Back to messages', onAction: () => context.go('/messages')));
    }
    final p = t.productId == null ? null : ref.watch(productProvider(t.productId!));
    final isBuying = t.side == ChatSide.buying;
    final needsQuote = !isBuying && t.tag.tone == Tone.warning;

    ref.listen(chatsProvider, (_, __) => WidgetsBinding.instance.addPostFrameCallback((_) => _toBottom()));

    return Scaffold(
      backgroundColor: AppColors.warmCream,
      body: Column(children: [
        // Header
        Container(
          color: AppColors.white,
          padding: EdgeInsets.fromLTRB(10, MediaQuery.paddingOf(context).top + 8, 10, 10),
          child: ResponsiveCenter(
            maxWidth: 720,
            child: Row(children: [
              const BackRoundButton(fallback: '/messages'),
              const SizedBox(width: 6),
              Avatar(initials: t.initials, size: 40, color: t.color, online: t.isOnline),
              const SizedBox(width: 10),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(t.name, style: AppText.bodyStrong.copyWith(fontSize: 15), maxLines: 1, overflow: TextOverflow.ellipsis),
                  Text(
                    t.isOnline ? 'Online${isBuying ? ' · usually replies in ${ref.watch(sellerProvider(t.sellerId ?? ''))?.replyTime.replaceFirst('about ', '') ?? 'a few hours'}' : ''}' : (isBuying ? 'Maker' : 'Customer of your store'),
                    style: AppText.caption.copyWith(color: t.isOnline ? AppColors.fern : AppColors.grayBrown, fontWeight: FontWeight.w600),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ]),
              ),
              if (isBuying && t.sellerId != null)
                RoundIconButton(icon: CraftIcons.store, tooltip: 'View store', onPressed: () => context.push('/seller/${t.sellerId}')),
            ]),
          ),
        ),
        const Divider(),
        if (p != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
            child: ResponsiveCenter(
              maxWidth: 720,
              child: ProductSummaryRow(
                product: p,
                photo: 40,
                title: p.title,
                subtitle: '${Fmt.peso(p.price)} · ${t.productNote ?? (isBuying ? 'item you asked about' : 'item they asked about')}',
                trailing: const CraftIcon(CraftIcons.chevron, size: 18, color: AppColors.grayBrown),
                onTap: () => context.push('/product/${p.id}'),
              ),
            ),
          ),
        // Messages
        Expanded(
          child: ResponsiveCenter(
            maxWidth: 720,
            child: ListView.builder(
              controller: _scroll,
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
              itemCount: t.messages.length,
              itemBuilder: (_, i) {
                final m = t.messages[i];
                return Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: switch (m.kind) {
                    MessageKind.system => _SystemNote(m.text),
                    MessageKind.quote => _QuoteCard(quote: m.quote!, fromMe: m.fromMe, canAct: isBuying && !m.fromMe, onAction: _onQuote, time: m.time),
                    _ => _Bubble(message: m),
                  },
                );
              },
            ),
          ),
        ),
        if (needsQuote)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: ResponsiveCenter(
              maxWidth: 720,
              child: Row(children: [
                Expanded(child: AppButton(label: 'Send a quote', icon: CraftIcons.tag, height: 44, onPressed: () => _composeQuote(t, p))),
                const SizedBox(width: 8),
                Expanded(
                  child: AppButton(
                    label: 'Decline',
                    kind: ButtonKind.danger,
                    height: 44,
                    onPressed: () => showMessage(context, 'Declining asks for a reason first. This form arrives in Milestone 3.'),
                  ),
                ),
              ]),
            ),
          ),
        // Input bar
        Container(
          decoration: const BoxDecoration(color: AppColors.white, border: Border(top: BorderSide(color: AppColors.linen))),
          padding: EdgeInsets.fromLTRB(10, 8, 10, 8 + MediaQuery.paddingOf(context).bottom),
          child: ResponsiveCenter(
            maxWidth: 720,
            child: Row(children: [
              RoundIconButton(icon: CraftIcons.clip, tooltip: 'Attach a photo', size: 42, onPressed: () => showComingSoon(context, 'Photo sharing')),
              const SizedBox(width: 4),
              Expanded(
                child: TextField(
                  controller: _input,
                  minLines: 1,
                  maxLines: 4,
                  textCapitalization: TextCapitalization.sentences,
                  textInputAction: TextInputAction.send,
                  onSubmitted: (_) => _send(),
                  onChanged: (_) => setState(() {}),
                  style: AppText.body,
                  decoration: InputDecoration(
                    hintText: 'Type a message',
                    filled: true,
                    fillColor: AppColors.warmCream,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(22), borderSide: const BorderSide(color: AppColors.linen, width: 1.5)),
                    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(22), borderSide: const BorderSide(color: AppColors.linen, width: 1.5)),
                    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(22), borderSide: const BorderSide(color: AppColors.moss, width: 2)),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Semantics(
                button: true,
                label: 'Send message',
                excludeSemantics: true,
                child: Material(
                  color: _input.text.trim().isEmpty ? AppColors.linen : AppColors.moss,
                  shape: const CircleBorder(),
                  child: InkWell(
                    customBorder: const CircleBorder(),
                    onTap: _send,
                    child: const SizedBox(width: 44, height: 44, child: Center(child: CraftIcon(CraftIcons.send, size: 19, color: AppColors.white))),
                  ),
                ),
              ),
            ]),
          ),
        ),
      ]),
    );
  }
}

class _SystemNote extends StatelessWidget {
  const _SystemNote(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(color: AppColors.lightSand, borderRadius: BorderRadius.circular(10)),
          child: Text(text, style: AppText.caption.copyWith(fontSize: 11.5), textAlign: TextAlign.center),
        ),
      );
}

class _Bubble extends StatelessWidget {
  const _Bubble({required this.message});
  final ChatMessage message;
  @override
  Widget build(BuildContext context) {
    final me = message.fromMe;
    return Align(
      alignment: me ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * 0.76),
        child: Column(crossAxisAlignment: me ? CrossAxisAlignment.end : CrossAxisAlignment.start, children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 10),
            decoration: BoxDecoration(
              color: me ? AppColors.moss : AppColors.white,
              border: me ? null : Border.all(color: AppColors.linen),
              borderRadius: BorderRadius.only(
                topLeft: const Radius.circular(18),
                topRight: const Radius.circular(18),
                bottomLeft: Radius.circular(me ? 18 : 4),
                bottomRight: Radius.circular(me ? 4 : 18),
              ),
            ),
            child: Text(message.text, style: AppText.body.copyWith(color: me ? AppColors.white : AppColors.darkCocoa, height: 1.45)),
          ),
          if (message.time.isNotEmpty) ...[
            const SizedBox(height: 3),
            Text('${message.time}${me && message.seen ? ' · Seen' : ''}', style: AppText.caption.copyWith(fontSize: 10.5)),
          ],
        ]),
      ),
    );
  }
}

class _QuoteCard extends StatelessWidget {
  const _QuoteCard({required this.quote, required this.fromMe, required this.canAct, required this.onAction, required this.time});
  final Quote quote;
  final bool fromMe;
  final bool canAct;
  final ValueChanged<QuoteStatus> onAction;
  final String time;

  @override
  Widget build(BuildContext context) {
    final (headText, headColor, headTint) = switch (quote.status) {
      QuoteStatus.sent => (fromMe ? 'Quote sent' : 'Request accepted · quote', AppColors.fern, AppColors.fernTint),
      QuoteStatus.accepted => ('Quote confirmed · order created', AppColors.fern, AppColors.fernTint),
      QuoteStatus.changesRequested => ('Changes requested', AppColors.amberText, AppColors.amberTint),
    };
    Widget line(String a, String b) => Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Row(children: [Expanded(child: Text(a, style: AppText.body.copyWith(fontSize: 13, color: AppColors.grayBrown))), Text(b, style: AppText.bodyStrong.copyWith(fontSize: 13))]),
        );
    return Align(
      alignment: fromMe ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: (MediaQuery.sizeOf(context).width * 0.82).clamp(0.0, 420.0)),
        child: Container(
          decoration: BoxDecoration(color: AppColors.white, borderRadius: Radii.card, border: Border.all(color: headColor, width: 1.5)),
          clipBehavior: Clip.antiAlias,
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Container(
              color: headTint,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(children: [
                CraftIcon(CraftIcons.check, size: 15, color: headColor, strokeWidth: 2.6),
                const SizedBox(width: 6),
                Expanded(child: Text(headText, style: AppText.label.copyWith(fontSize: 12.5, fontWeight: FontWeight.w800, color: headColor))),
              ]),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                line(quote.item, Fmt.peso(quote.price)),
                line('Ready by', Fmt.date(quote.readyBy)),
                if (canAct && quote.status == QuoteStatus.sent) ...[
                  const SizedBox(height: 4),
                  Row(children: [
                    Expanded(child: AppButton(label: 'Confirm order', height: 40, onPressed: () => onAction(QuoteStatus.accepted))),
                    const SizedBox(width: 8),
                    Expanded(child: AppButton(label: 'Ask for changes', kind: ButtonKind.outline, height: 40, onPressed: () => onAction(QuoteStatus.changesRequested))),
                  ]),
                ],
                if (time.isNotEmpty) Align(alignment: Alignment.centerRight, child: Text(time, style: AppText.caption.copyWith(fontSize: 10.5))),
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}

/// Seller form for replying to a custom request with a price and ready date.
class _QuoteSheet extends StatefulWidget {
  const _QuoteSheet({required this.defaultItem, required this.basePrice});
  final String defaultItem;
  final double basePrice;
  @override
  State<_QuoteSheet> createState() => _QuoteSheetState();
}

class _QuoteSheetState extends State<_QuoteSheet> {
  final _form = GlobalKey<FormState>();
  late final _item = TextEditingController(text: widget.defaultItem);
  late final _price = TextEditingController(text: widget.basePrice > 0 ? widget.basePrice.toStringAsFixed(0) : '');
  final _note = TextEditingController();
  DateTime _ready = DateTime.now().add(const Duration(days: 7));

  @override
  void dispose() {
    _item.dispose();
    _price.dispose();
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(Insets.screen, 0, Insets.screen, 16),
          child: Form(
            key: _form,
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text('Send a quote', style: AppText.screenTitle),
              const SizedBox(height: 4),
              Text('The buyer pays only after confirming this price.', style: AppText.caption),
              const SizedBox(height: 14),
              LabeledField(label: 'Item', controller: _item, validator: (v) => (v ?? '').trim().isEmpty ? 'Describe the item.' : null),
              const SizedBox(height: 12),
              LabeledField(
                label: 'Total price',
                controller: _price,
                prefixText: '₱ ',
                keyboardType: TextInputType.number,
                validator: (v) => (double.tryParse((v ?? '').replaceAll(',', '')) ?? 0) > 0 ? null : 'Enter a price.',
              ),
              const SizedBox(height: 12),
              Text('Ready by', style: AppText.label),
              const SizedBox(height: 6),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(48),
                  foregroundColor: AppColors.darkCocoa,
                  side: const BorderSide(color: AppColors.linen, width: 1.5),
                  backgroundColor: AppColors.white,
                  alignment: Alignment.centerLeft,
                  shape: const RoundedRectangleBorder(borderRadius: Radii.field),
                  textStyle: AppText.body.copyWith(fontSize: 15),
                ),
                icon: const CraftIcon(CraftIcons.calendar, size: 18, color: AppColors.grayBrown),
                label: Text(Fmt.date(_ready)),
                onPressed: () async {
                  final d = await showDatePicker(context: context, initialDate: _ready, firstDate: DateTime.now(), lastDate: DateTime.now().add(const Duration(days: 180)));
                  if (d != null) setState(() => _ready = d);
                },
              ),
              const SizedBox(height: 12),
              LabeledField(label: 'Note to the buyer (optional)', controller: _note, maxLines: 2, hint: 'Details or conditions'),
              const SizedBox(height: 16),
              AppButton(
                label: 'Send quote',
                icon: CraftIcons.send,
                onPressed: () {
                  if (!_form.currentState!.validate()) return;
                  Navigator.pop(context, (Quote(item: _item.text.trim(), price: double.parse(_price.text.replaceAll(',', '')), readyBy: _ready), _note.text));
                },
              ),
            ]),
          ),
        ),
      ),
    );
  }
}

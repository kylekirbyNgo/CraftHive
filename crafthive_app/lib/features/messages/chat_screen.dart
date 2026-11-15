import 'dart:async';

import 'package:flutter/material.dart';
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

/// Screen 8 – Chat (Firestore chats/{chatId}/messages): the other person's name,
/// online status and typing (Realtime Database), the product being discussed,
/// message bubbles with "Seen", and quote cards with Confirm order / Ask for changes.
/// Quote cards and order updates are posted by the server after PostgreSQL saves them.
class ChatScreen extends ConsumerStatefulWidget {
  const ChatScreen({super.key, required this.threadId});
  final String threadId;
  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen> {
  final _input = TextEditingController();
  final _scroll = ScrollController();
  Timer? _typingOff;
  Timer? _waitForChat;
  bool _gaveUp = false;
  bool _typing = false;
  bool _sending = false;
  bool _sendingPhoto = false;
  late final ChatActions _chat = ref.read(chatActionsProvider);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _chat.markRead(widget.threadId);
      _toBottom(jump: true);
    });
  }

  @override
  void dispose() {
    _typingOff?.cancel();
    _waitForChat?.cancel();
    if (_typing) _chat.setTyping(widget.threadId, false);
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _toBottom({bool jump = false}) {
    if (!_scroll.hasClients) return;
    final target = _scroll.position.maxScrollExtent;
    jump ? _scroll.jumpTo(target) : _scroll.animateTo(target, duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
  }

  /// Typing dots for the other person: on while typing, off after 3 quiet seconds.
  void _onChanged(String text) {
    setState(() {});
    _typingOff?.cancel();
    if (text.trim().isEmpty) {
      _setTyping(false);
      return;
    }
    _setTyping(true);
    _typingOff = Timer(const Duration(seconds: 3), () => _setTyping(false));
  }

  void _setTyping(bool on) {
    if (_typing == on) return;
    _typing = on;
    _chat.setTyping(widget.threadId, on);
  }

  Future<void> _send(ChatThread t) async {
    final text = _input.text.trim();
    if (text.isEmpty || _sending) return;
    _typingOff?.cancel();
    _setTyping(false);
    setState(() => _sending = true);
    _input.clear();
    final ok = await runWithMessage(context, () => _chat.send(t, text));
    if (!mounted) return;
    // Keep what they typed if it could not be sent.
    if (!ok && _input.text.isEmpty) _input.text = text;
    setState(() => _sending = false);
    WidgetsBinding.instance.addPostFrameCallback((_) => _toBottom());
  }

  Future<void> _sendPhoto(ChatThread t) async {
    final photo = await pickOnePhoto(context);
    if (photo == null || !mounted) return;
    setState(() => _sendingPhoto = true);
    await runWithMessage(context, () => _chat.sendPhoto(t, photo));
    if (!mounted) return;
    setState(() => _sendingPhoto = false);
    WidgetsBinding.instance.addPostFrameCallback((_) => _toBottom());
  }

  Future<void> _acceptQuote(QuoteOffer q) async {
    final yes = await confirmAction(
      context,
      title: 'Confirm this order?',
      message: 'You agree to pay ${Fmt.peso(q.price)}, ready by ${Fmt.date(q.readyBy)}. The maker starts once your payment is confirmed.',
      confirmLabel: 'Confirm order',
    );
    if (!yes || !mounted) return;
    String? number;
    final ok = await runWithMessage(context, () async => number = await ref.read(customOrderActionsProvider).accept(q));
    if (!ok || !mounted || number == null) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: const Text('Order confirmed. Upload your payment proof to get started.'),
        action: SnackBarAction(label: 'View order', textColor: AppColors.softHoney, onPressed: () => context.push('/order/$number')),
      ));
  }

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(chatProvider(widget.threadId));
    if (t == null) {
      // A chat that was just created can take a moment to reach the list.
      _waitForChat ??= Timer(const Duration(seconds: 6), () {
        if (mounted) setState(() => _gaveUp = true);
      });
      final loading = !_gaveUp || ref.watch(chatsDataProvider).isLoading || ref.watch(firebaseUidProvider).isLoading;
      return Scaffold(
        appBar: const ScreenHeader(title: 'Chat', fallback: '/messages'),
        body: loading
            ? const Center(child: CircularProgressIndicator(color: AppColors.moss))
            : EmptyState(
                icon: CraftIcons.chat,
                title: 'Chat not found',
                message: 'This conversation is no longer available.',
                actionLabel: 'Back to messages',
                onAction: () => context.go('/messages'),
              ),
      );
    }
    final messages = ref.watch(chatMessagesProvider(t.id)).valueOrNull ?? t.messages;
    final p = t.productId == null ? null : ref.watch(productProvider(t.productId!));
    final isBuying = t.side == ChatSide.buying;
    final online = t.isOnline || (ref.watch(onlineProvider(t.otherUid)).valueOrNull ?? false);
    final typing = ref.watch(typingProvider((t.id, t.otherUid))).valueOrNull ?? false;
    final request = t.requestCode == null ? null : ref.watch(requestProvider(t.requestCode!));
    // A new request or changes asked: the seller answers on the request screen.
    final replyCode = (!isBuying && request != null && request.needsMyAction) ? request.code : null;

    // New messages: scroll down, and mark them read while the chat is open.
    ref.listen(chatMessagesProvider(t.id), (_, __) => WidgetsBinding.instance.addPostFrameCallback((_) => _toBottom()));
    ref.listen(chatProvider(widget.threadId), (_, next) {
      if ((next?.unread ?? 0) > 0) _chat.markRead(widget.threadId);
    });

    final status = typing
        ? 'typing…'
        : online
            ? 'Online${isBuying ? ' · usually replies in ${ref.watch(sellerProvider(t.sellerId ?? ''))?.replyTime.replaceFirst('about ', '') ?? 'a few hours'}' : ''}'
            : (isBuying ? 'Maker' : 'Customer of your store');

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
              Avatar(initials: t.initials, size: 40, color: t.color, online: online, imageUrl: isBuying ? ref.watch(sellerProvider(t.sellerId ?? ''))?.avatarUrl : null),
              const SizedBox(width: 10),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(t.name, style: AppText.bodyStrong.copyWith(fontSize: 15), maxLines: 1, overflow: TextOverflow.ellipsis),
                  Text(
                    status,
                    style: AppText.caption.copyWith(color: online || typing ? AppColors.fern : AppColors.grayBrown, fontWeight: FontWeight.w600),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ]),
              ),
              if (t.orderNumber != null)
                RoundIconButton(icon: CraftIcons.orders, tooltip: 'Order ${t.orderNumber}', onPressed: () => context.push('/order/${t.orderNumber}')),
              if (isBuying && t.sellerId != null) ...[
                const SizedBox(width: 6),
                RoundIconButton(icon: CraftIcons.store, tooltip: 'View store', onPressed: () => context.push('/seller/${t.sellerId}')),
              ],
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
            child: messages.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(isBuying ? 'Say hello and ask the maker anything about their items.' : 'Say hello to your customer.',
                          style: AppText.caption, textAlign: TextAlign.center),
                    ),
                  )
                : ListView.builder(
                    controller: _scroll,
                    padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                    itemCount: messages.length,
                    itemBuilder: (_, i) {
                      final m = messages[i];
                      final readAt = t.otherReadAt;
                      final seen = m.seen || (m.fromMe && readAt != null && m.sentAt != null && !m.sentAt!.isAfter(readAt));
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: switch (m.kind) {
                          MessageKind.system => _SystemNote(m.text),
                          MessageKind.photo => _PhotoBubble(message: m, seen: seen),
                          MessageKind.quote => _QuoteCard(
                              message: m,
                              isBuying: isBuying,
                              onAccept: _acceptQuote,
                              onAskChanges: (code) => context.push('/request/$code'),
                            ),
                          _ => _Bubble(message: m, seen: seen),
                        },
                      );
                    },
                  ),
          ),
        ),
        if (replyCode != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: ResponsiveCenter(
              maxWidth: 720,
              child: AppButton(
                label: 'Quote or decline $replyCode',
                icon: CraftIcons.tag,
                height: 44,
                onPressed: () => context.push('/request/$replyCode'),
              ),
            ),
          ),
        // Input bar
        Container(
          decoration: const BoxDecoration(color: AppColors.white, border: Border(top: BorderSide(color: AppColors.linen))),
          padding: EdgeInsets.fromLTRB(10, 8, 10, 8 + MediaQuery.paddingOf(context).bottom),
          child: ResponsiveCenter(
            maxWidth: 720,
            child: Row(children: [
              _sendingPhoto
                  ? const SizedBox(width: 42, height: 42, child: Padding(padding: EdgeInsets.all(11), child: CircularProgressIndicator(strokeWidth: 2.4, color: AppColors.moss)))
                  : RoundIconButton(icon: CraftIcons.image, tooltip: 'Send a photo', size: 42, onPressed: () => _sendPhoto(t)),
              const SizedBox(width: 4),
              Expanded(
                child: TextField(
                  controller: _input,
                  minLines: 1,
                  maxLines: 4,
                  maxLength: 2000,
                  textCapitalization: TextCapitalization.sentences,
                  textInputAction: TextInputAction.send,
                  onSubmitted: (_) => _send(t),
                  onChanged: _onChanged,
                  style: AppText.body,
                  decoration: InputDecoration(
                    hintText: 'Type a message',
                    counterText: '',
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
                  color: _input.text.trim().isEmpty || _sending ? AppColors.linen : AppColors.moss,
                  shape: const CircleBorder(),
                  child: InkWell(
                    customBorder: const CircleBorder(),
                    onTap: () => _send(t),
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
  const _Bubble({required this.message, required this.seen});
  final ChatMessage message;
  final bool seen;
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
            Text('${message.time}${me && seen ? ' · Seen' : ''}', style: AppText.caption.copyWith(fontSize: 10.5)),
          ],
        ]),
      ),
    );
  }
}


/// A seller's price offer, posted into the chat by the server when the quote is
/// saved. Its current state comes from the custom request in PostgreSQL.
class _QuoteCard extends ConsumerWidget {
  const _QuoteCard({required this.message, required this.isBuying, required this.onAccept, required this.onAskChanges});
  final ChatMessage message;
  final bool isBuying;
  final ValueChanged<QuoteOffer> onAccept;
  final ValueChanged<String> onAskChanges;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final quote = message.quote!;
    final code = message.requestCode;
    final request = code == null ? null : ref.watch(requestProvider(code));
    final offer = request?.quotes.where((q) => q.id == message.quoteId).firstOrNull;
    final canAct = isBuying && offer != null && request?.openQuote?.id == offer.id;
    final fromSeller = !isBuying;

    final (headText, headColor, headTint) = switch (offer?.status ?? OfferStatus.sent) {
      OfferStatus.sent => (fromSeller ? 'Quote sent · waiting for buyer' : 'Quote from the maker', AppColors.fern, AppColors.fernTint),
      OfferStatus.accepted => ('Quote confirmed · order created', AppColors.fern, AppColors.fernTint),
      OfferStatus.changesRequested => ('Changes requested', AppColors.amberText, AppColors.amberTint),
      OfferStatus.declined => ('Declined', AppColors.brick, AppColors.brickTint),
      OfferStatus.superseded => ('Replaced by a newer quote', AppColors.grayBrown, AppColors.lightSand),
    };
    Widget line(String a, String b) => Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Row(children: [
            Expanded(child: Text(a, style: AppText.body.copyWith(fontSize: 13, color: AppColors.grayBrown))),
            Text(b, style: AppText.bodyStrong.copyWith(fontSize: 13)),
          ]),
        );
    return Align(
      alignment: fromSeller ? Alignment.centerRight : Alignment.centerLeft,
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
                CraftIcon(CraftIcons.tag, size: 15, color: headColor, strokeWidth: 2.4),
                const SizedBox(width: 6),
                Expanded(child: Text(headText, style: AppText.label.copyWith(fontSize: 12.5, fontWeight: FontWeight.w800, color: headColor))),
                if (offer != null) Text('v${offer.version}', style: AppText.small.copyWith(color: headColor, fontWeight: FontWeight.w700)),
              ]),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                line(quote.item, Fmt.peso(quote.price)),
                line('Ready by', Fmt.date(quote.readyBy)),
                if (code != null) line('Request', code),
                if (message.text.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text('"${message.text}"', style: AppText.body.copyWith(fontSize: 13, fontStyle: FontStyle.italic)),
                  const SizedBox(height: 6),
                ],
                if (canAct) ...[
                  const SizedBox(height: 4),
                  Row(children: [
                    Expanded(child: AppButton(label: 'Confirm order', height: 40, onPressed: () => onAccept(offer))),
                    const SizedBox(width: 8),
                    Expanded(child: AppButton(label: 'Ask for changes', kind: ButtonKind.outline, height: 40, onPressed: () => onAskChanges(code!))),
                  ]),
                ] else if (code != null && request != null) ...[
                  const SizedBox(height: 2),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton(onPressed: () => onAskChanges(code), child: Text('View request $code')),
                  ),
                ],
                if (message.time.isNotEmpty) Align(alignment: Alignment.centerRight, child: Text(message.time, style: AppText.caption.copyWith(fontSize: 10.5))),
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}

/// A photo sent in the chat (private chat-photos bucket). Tap to see it full size.
class _PhotoBubble extends ConsumerWidget {
  const _PhotoBubble({required this.message, required this.seen});
  final ChatMessage message;
  final bool seen;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final me = message.fromMe;
    final path = message.imagePath;
    final url = path == null ? null : ref.watch(chatPhotoUrlProvider(path)).valueOrNull;
    final side = (MediaQuery.sizeOf(context).width * 0.6).clamp(140.0, 280.0);
    final placeholder = Container(
      color: AppColors.lightSand,
      alignment: Alignment.center,
      child: const CraftIcon(CraftIcons.image, size: 28, color: AppColors.grayBrown),
    );
    return Align(
      alignment: me ? Alignment.centerRight : Alignment.centerLeft,
      child: Column(crossAxisAlignment: me ? CrossAxisAlignment.end : CrossAxisAlignment.start, children: [
        Semantics(
          image: true,
          button: url != null && url.isNotEmpty,
          label: me ? 'Photo you sent' : 'Photo',
          child: GestureDetector(
            onTap: url == null || url.isEmpty
                ? null
                : () => showDialog<void>(context: context, builder: (_) => Dialog(child: InteractiveViewer(child: Image.network(url)))),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: SizedBox(
                width: side,
                height: side,
                child: url == null || url.isEmpty
                    ? placeholder
                    : Image.network(url, fit: BoxFit.cover, errorBuilder: (_, __, ___) => placeholder),
              ),
            ),
          ),
        ),
        if (message.time.isNotEmpty) ...[
          const SizedBox(height: 3),
          Text('${message.time}${me && seen ? ' · Seen' : ''}', style: AppText.caption.copyWith(fontSize: 10.5)),
        ],
      ]),
    );
  }
}

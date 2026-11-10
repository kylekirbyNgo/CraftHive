import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../data/models.dart';
import '../../data/providers.dart';
import '../../shared/widgets/common.dart';
import '../../shared/widgets/craft_icon.dart';

/// Screens 9 and 10 – Messages with two tabs:
/// Buying (shops I order from) in the buyer colour, and Selling (customers of my store) in the seller colour.
class MessagesScreen extends ConsumerStatefulWidget {
  const MessagesScreen({super.key});
  @override
  ConsumerState<MessagesScreen> createState() => _MessagesScreenState();
}

class _MessagesScreenState extends ConsumerState<MessagesScreen> {
  ChatSide _side = ChatSide.buying;
  bool _searching = false;
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final all = ref.watch(chatsProvider);
    final threads = all
        .where((t) => t.side == _side)
        .where((t) => _query.isEmpty || t.name.toLowerCase().contains(_query.toLowerCase()) || t.lastMessage.toLowerCase().contains(_query.toLowerCase()))
        .toList();
    final sellingUnread = all.where((t) => t.side == ChatSide.selling).fold(0, (s, t) => s + t.unread);
    final buyingUnread = all.where((t) => t.side == ChatSide.buying).fold(0, (s, t) => s + t.unread);

    return Scaffold(
      appBar: ScreenHeader(
        title: 'Messages',
        showBack: false,
        trailing: RoundIconButton(
          icon: _searching ? CraftIcons.close : CraftIcons.search,
          tooltip: _searching ? 'Close search' : 'Search messages',
          onPressed: () => setState(() {
            _searching = !_searching;
            _query = '';
          }),
        ),
      ),
      body: ResponsiveCenter(
        child: Column(children: [
          if (_searching)
            Padding(
              padding: const EdgeInsets.fromLTRB(Insets.screen, 0, Insets.screen, 10),
              child: TextField(
                autofocus: true,
                onChanged: (v) => setState(() => _query = v),
                decoration: const InputDecoration(
                  hintText: 'Search names or messages',
                  prefixIcon: Padding(padding: EdgeInsets.only(left: 14, right: 10), child: CraftIcon(CraftIcons.search, size: 18, color: AppColors.grayBrown)),
                  prefixIconConstraints: BoxConstraints(minWidth: 0, minHeight: 0),
                ),
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(Insets.screen, 2, Insets.screen, 12),
            child: _SideTabs(
              side: _side,
              buyingUnread: buyingUnread,
              sellingUnread: sellingUnread,
              onChanged: (s) => setState(() => _side = s),
            ),
          ),
          Expanded(
            child: threads.isEmpty
                ? ListView(children: [
                    EmptyState(
                      icon: CraftIcons.chat,
                      title: _query.isNotEmpty ? 'No matching chats' : (_side == ChatSide.buying ? 'No chats with shops yet' : 'No customer chats yet'),
                      message: _side == ChatSide.buying
                          ? 'Tap Buy now on any item to start a chat with its maker.'
                          : 'When a buyer messages your store, the chat appears here.',
                      actionLabel: _side == ChatSide.buying && _query.isEmpty ? 'Browse items' : null,
                      onAction: () => context.go('/home'),
                    ),
                  ])
                : RefreshIndicator(
                    color: AppColors.moss,
                    onRefresh: () => Future<void>.delayed(const Duration(milliseconds: 600)),
                    child: ListView.builder(
                      padding: const EdgeInsets.only(bottom: 110),
                      itemCount: threads.length,
                      itemBuilder: (_, i) => _ConversationTile(thread: threads[i]),
                    ),
                  ),
          ),
        ]),
      ),
    );
  }
}

class _SideTabs extends StatelessWidget {
  const _SideTabs({required this.side, required this.onChanged, required this.buyingUnread, required this.sellingUnread});
  final ChatSide side;
  final ValueChanged<ChatSide> onChanged;
  final int buyingUnread;
  final int sellingUnread;

  @override
  Widget build(BuildContext context) {
    Widget tab(ChatSide s, String label, String sub, Color color, int unread) {
      final on = side == s;
      return Expanded(
        child: Semantics(
          button: true,
          selected: on,
          label: '$label tab, $sub${unread > 0 ? ', $unread unread' : ''}',
          excludeSemantics: true,
          child: Material(
            color: on ? color : Colors.transparent,
            borderRadius: Radii.field,
            child: InkWell(
              borderRadius: Radii.field,
              onTap: () => onChanged(s),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 6),
                child: Column(children: [
                  Text(unread > 0 ? '$label ($unread)' : label, style: AppText.bodyStrong.copyWith(fontWeight: FontWeight.w800, color: on ? AppColors.white : AppColors.darkCocoa)),
                  Text(sub, style: AppText.small.copyWith(color: on ? AppColors.white.withValues(alpha: 0.92) : AppColors.grayBrown)),
                ]),
              ),
            ),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(color: AppColors.lightSand, borderRadius: BorderRadius.circular(16), border: Border.all(color: AppColors.linen)),
      child: Row(children: [
        tab(ChatSide.buying, 'Buying', 'Shops I order from', AppColors.moss, buyingUnread),
        const SizedBox(width: 4),
        tab(ChatSide.selling, 'Selling', 'Customers of my store', AppColors.clayText, sellingUnread),
      ]),
    );
  }
}

class _ConversationTile extends StatelessWidget {
  const _ConversationTile({required this.thread});
  final ChatThread thread;
  @override
  Widget build(BuildContext context) {
    final bold = thread.unread > 0;
    return Semantics(
      button: true,
      label: '${thread.name}. ${thread.lastMessage}. ${thread.tag.label}. ${thread.lastTime}${bold ? '. ${thread.unread} unread' : ''}',
      excludeSemantics: true,
      child: InkWell(
        onTap: () => context.push('/chat/${thread.id}'),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: Insets.screen, vertical: 12),
          decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: AppColors.linen))),
          child: Row(children: [
            Avatar(initials: thread.initials, size: 48, color: thread.color, online: thread.isOnline),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Expanded(child: Text(thread.name, style: AppText.bodyStrong.copyWith(fontSize: 14.5), maxLines: 1, overflow: TextOverflow.ellipsis)),
                  const SizedBox(width: 8),
                  Text(thread.lastTime, style: AppText.caption.copyWith(fontSize: 11.5)),
                ]),
                const SizedBox(height: 4),
                Text(
                  thread.lastMessage,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppText.body.copyWith(fontSize: 13, color: bold ? AppColors.darkCocoa : AppColors.grayBrown, fontWeight: bold ? FontWeight.w600 : FontWeight.w400),
                ),
                const SizedBox(height: 6),
                Row(children: [
                  StatusPill(thread.tag.label, tone: thread.tag.tone),
                  const Spacer(),
                  if (bold)
                    Container(
                      constraints: const BoxConstraints(minWidth: 20),
                      height: 20,
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                      decoration: BoxDecoration(color: AppColors.brick, borderRadius: Radii.pill),
                      alignment: Alignment.center,
                      child: Text('${thread.unread}', style: AppText.small.copyWith(color: AppColors.white, fontWeight: FontWeight.w800)),
                    ),
                ]),
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}

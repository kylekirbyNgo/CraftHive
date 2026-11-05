import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../data/models.dart';
import '../../data/providers.dart';
import '../../shared/widgets/common.dart';
import '../../shared/widgets/craft_icon.dart';

/// Supporting screen – Notifications: quotes, payments, requests, shipping and reviews.
/// Each one opens the related chat, order or store (deep links in Milestone 3).
class NotificationsScreen extends ConsumerWidget {
  const NotificationsScreen({super.key});

  static (String, Tone) _style(NoticeKind k) => switch (k) {
        NoticeKind.quote => (CraftIcons.tag, Tone.success),
        NoticeKind.payment => (CraftIcons.wallet, Tone.info),
        NoticeKind.request => (CraftIcons.edit, Tone.seller),
        NoticeKind.shipping => (CraftIcons.truck, Tone.info),
        NoticeKind.review => (CraftIcons.star, Tone.warning),
      };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notices = ref.watch(noticesProvider);
    final unread = notices.where((n) => !n.read).length;
    return Scaffold(
      appBar: ScreenHeader(
        title: 'Notifications',
        trailing: unread == 0 ? null : TextButton(onPressed: () => ref.read(noticesProvider.notifier).markAllRead(), child: const Text('Mark all read')),
      ),
      body: ResponsiveCenter(
        child: notices.isEmpty
            ? const EmptyState(icon: CraftIcons.bell, title: 'You are all caught up', message: 'Quotes, payments and order updates will show up here.')
            : ListView.separated(
                padding: const EdgeInsets.only(bottom: 24),
                itemCount: notices.length,
                separatorBuilder: (_, __) => const Divider(indent: Insets.screen, endIndent: Insets.screen),
                itemBuilder: (_, i) {
                  final n = notices[i];
                  final (icon, tone) = _style(n.kind);
                  final c = toneColors(tone);
                  return Semantics(
                    button: true,
                    label: '${n.read ? '' : 'Unread. '}${n.title}. ${n.body}. ${n.time}',
                    excludeSemantics: true,
                    child: InkWell(
                      onTap: () {
                        ref.read(noticesProvider.notifier).markRead(i);
                        context.push(n.route);
                      },
                      child: Container(
                        color: n.read ? Colors.transparent : AppColors.white,
                        padding: const EdgeInsets.symmetric(horizontal: Insets.screen, vertical: 14),
                        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Container(
                            width: 42,
                            height: 42,
                            decoration: BoxDecoration(color: tone == Tone.seller ? AppColors.clayTint : c.tint, shape: BoxShape.circle),
                            alignment: Alignment.center,
                            child: CraftIcon(icon, size: 20, color: c.ink),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Row(children: [
                                Expanded(child: Text(n.title, style: AppText.bodyStrong.copyWith(fontWeight: n.read ? FontWeight.w600 : FontWeight.w800))),
                                const SizedBox(width: 8),
                                Text(n.time, style: AppText.caption.copyWith(fontSize: 11.5)),
                              ]),
                              const SizedBox(height: 3),
                              Text(n.body, style: AppText.body.copyWith(fontSize: 13, color: AppColors.grayBrown)),
                            ]),
                          ),
                          if (!n.read) ...[
                            const SizedBox(width: 8),
                            Container(width: 9, height: 9, margin: const EdgeInsets.only(top: 6), decoration: const BoxDecoration(color: AppColors.brick, shape: BoxShape.circle)),
                          ],
                        ]),
                      ),
                    ),
                  );
                },
              ),
      ),
    );
  }
}

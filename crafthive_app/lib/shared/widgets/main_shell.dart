import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../data/providers.dart';
import 'craft_icon.dart';

/// Scaffold for the four main tabs with the CraftHive bottom bar:
/// Home · Messages · Sell (+) · Orders · Saved. The Sell button is always in the
/// centre, in the seller colour, so selling is one tap away from anywhere.
class MainShell extends ConsumerWidget {
  const MainShell({super.key, required this.shell});
  final StatefulNavigationShell shell;

  void _go(int index) => shell.goBranch(index, initialLocation: index == shell.currentIndex);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final unread = ref.watch(unreadCountProvider);
    return Scaffold(
      body: shell,
      extendBody: true,
      bottomNavigationBar: _BottomBar(
        current: shell.currentIndex,
        unread: unread,
        onTab: _go,
        onSell: () => context.push('/sell'),
      ),
    );
  }
}

class _BottomBar extends StatelessWidget {
  const _BottomBar({required this.current, required this.unread, required this.onTab, required this.onSell});
  final int current;
  final int unread;
  final ValueChanged<int> onTab;
  final VoidCallback onSell;

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.paddingOf(context).bottom;
    return Container(
      decoration: const BoxDecoration(color: AppColors.white, border: Border(top: BorderSide(color: AppColors.linen))),
      padding: EdgeInsets.only(bottom: bottomInset > 0 ? bottomInset : 8),
      child: SizedBox(
        height: 70,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            _Tab(icon: CraftIcons.home, label: 'Home', selected: current == 0, onTap: () => onTab(0)),
            _Tab(icon: CraftIcons.chat, label: 'Messages', selected: current == 1, onTap: () => onTab(1), badge: unread),
            Expanded(child: _SellButton(onTap: onSell)),
            _Tab(icon: CraftIcons.orders, label: 'Orders', selected: current == 2, onTap: () => onTab(2)),
            _Tab(icon: CraftIcons.heart, label: 'Saved', selected: current == 3, onTap: () => onTab(3)),
          ],
        ),
      ),
    );
  }
}

class _Tab extends StatelessWidget {
  const _Tab({required this.icon, required this.label, required this.selected, required this.onTap, this.badge = 0});
  final String icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final int badge;

  @override
  Widget build(BuildContext context) {
    final color = selected ? AppColors.moss : AppColors.grayBrown;
    Widget iconW = CraftIcon(icon, size: 23, color: color, strokeWidth: selected ? 2.1 : 1.9);
    if (badge > 0) {
      iconW = Badge(label: Text('$badge'), backgroundColor: AppColors.brick, offset: const Offset(8, -6), child: iconW);
    }
    return Expanded(
      child: Semantics(
        button: true,
        selected: selected,
        label: badge > 0 ? '$label, $badge unread' : label,
        excludeSemantics: true,
        child: InkResponse(
          onTap: onTap,
          radius: 32,
          child: SizedBox(
            height: 62,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                iconW,
                const SizedBox(height: 4),
                Text(label, style: AppText.small.copyWith(color: color, fontWeight: selected ? FontWeight.w700 : FontWeight.w600)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SellButton extends StatelessWidget {
  const _SellButton({required this.onTap});
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        label: 'Sell an item',
        excludeSemantics: true,
        child: GestureDetector(
          onTap: onTap,
          behavior: HitTestBehavior.opaque,
          child: OverflowBox(
            maxHeight: 110,
            alignment: Alignment.bottomCenter,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 60,
                  height: 60,
                  decoration: BoxDecoration(
                    color: AppColors.clay,
                    shape: BoxShape.circle,
                    border: Border.all(color: AppColors.warmCream, width: 4),
                    boxShadow: const [BoxShadow(color: Color(0x383B2A20), blurRadius: 14, offset: Offset(0, 6))],
                  ),
                  alignment: Alignment.center,
                  child: const CraftIcon(CraftIcons.plus, size: 28, color: AppColors.white, strokeWidth: 2.4),
                ),
                const SizedBox(height: 3),
                Text('Sell', style: AppText.label.copyWith(fontSize: 12, fontWeight: FontWeight.w800, color: AppColors.clayText)),
                const SizedBox(height: 8),
              ],
            ),
          ),
        ),
      );
}

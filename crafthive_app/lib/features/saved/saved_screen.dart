import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/format.dart';
import '../../data/providers.dart';
import '../../shared/widgets/common.dart';
import '../../shared/widgets/craft_icon.dart';
import '../../shared/widgets/product_widgets.dart';

/// Supporting screen – Saved items (grid of products the user saved with the heart).
class SavedScreen extends ConsumerWidget {
  const SavedScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ids = ref.watch(savedProvider);
    final items = ref.watch(catalogProvider).where((p) => ids.contains(p.id)).toList();
    return Scaffold(
      appBar: ScreenHeader(title: 'Saved', subtitle: Fmt.count(items.length, 'item'), showBack: false),
      body: ResponsiveCenter(
        maxWidth: 900,
        child: items.isEmpty
            ? ListView(children: [
                EmptyState(
                  icon: CraftIcons.heart,
                  title: 'Nothing saved yet',
                  message: 'Tap the heart on any item to keep it here for later.',
                  actionLabel: 'Browse items',
                  onAction: () => context.go('/home'),
                ),
              ])
            : ListView(padding: const EdgeInsets.only(top: 4, bottom: 110), children: [ProductGrid(products: items)]),
      ),
    );
  }
}

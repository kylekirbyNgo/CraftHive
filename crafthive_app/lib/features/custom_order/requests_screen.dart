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

/// Custom requests, split into Buying (requests I sent) and Selling
/// (requests for my store), like Orders and Messages.
class RequestsScreen extends ConsumerStatefulWidget {
  const RequestsScreen({super.key, this.initialSide = ChatSide.buying});
  final ChatSide initialSide;
  @override
  ConsumerState<RequestsScreen> createState() => _RequestsScreenState();
}

class _RequestsScreenState extends ConsumerState<RequestsScreen> {
  late ChatSide _side = widget.initialSide;

  @override
  Widget build(BuildContext context) {
    final data = ref.watch(requestsDataProvider);
    final all = ref.watch(requestsProvider);
    final list = all.where((r) => r.side == _side).toList();
    int waiting(ChatSide side) => all.where((r) => r.side == side && r.needsMyAction).length;

    return Scaffold(
      appBar: const ScreenHeader(title: 'Custom requests', fallback: '/orders'),
      body: ResponsiveCenter(
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(Insets.screen, 2, Insets.screen, 10),
            child: Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(color: AppColors.lightSand, borderRadius: BorderRadius.circular(16), border: Border.all(color: AppColors.linen)),
              child: Row(children: [
                _Tab(label: 'Buying', sub: 'Requests I sent', count: waiting(ChatSide.buying), on: _side == ChatSide.buying, color: AppColors.moss,
                    onTap: () => setState(() => _side = ChatSide.buying)),
                const SizedBox(width: 4),
                _Tab(label: 'Selling', sub: 'Requests for my store', count: waiting(ChatSide.selling), on: _side == ChatSide.selling, color: AppColors.clayText,
                    onTap: () => setState(() => _side = ChatSide.selling)),
              ]),
            ),
          ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: () => ref.refresh(requestsDataProvider.future),
              child: data.isLoading && all.isEmpty
                  ? const Center(child: CircularProgressIndicator())
                  : data.hasError && all.isEmpty
                      ? ListView(children: [
                          EmptyState(
                            icon: CraftIcons.info,
                            title: 'Could not load requests',
                            message: data.error is AppFailure ? (data.error as AppFailure).message : 'Please try again.',
                            actionLabel: 'Try again',
                            onAction: () => ref.invalidate(requestsDataProvider),
                          ),
                        ])
                      : list.isEmpty
                          ? ListView(children: [
                              EmptyState(
                                icon: CraftIcons.edit,
                                title: _side == ChatSide.buying ? 'No custom requests yet' : 'No requests for your store yet',
                                message: _side == ChatSide.buying
                                    ? 'Open an item with "Custom orders open" and tap Custom order to ask the maker for something made just for you.'
                                    : 'Turn on "Accept custom orders" on your listings so buyers can send you requests.',
                              ),
                            ])
                          : ListView.separated(
                              padding: const EdgeInsets.fromLTRB(Insets.screen, 4, Insets.screen, 32),
                              itemCount: list.length,
                              separatorBuilder: (_, __) => const SizedBox(height: 10),
                              itemBuilder: (_, i) => RequestCard(request: list[i]),
                            ),
            ),
          ),
        ]),
      ),
    );
  }
}

class _Tab extends StatelessWidget {
  const _Tab({required this.label, required this.sub, required this.count, required this.on, required this.color, required this.onTap});
  final String label;
  final String sub;
  final int count;
  final bool on;
  final Color color;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Expanded(
        child: Semantics(
          button: true,
          selected: on,
          label: '$label tab, $sub${count > 0 ? ', $count waiting for you' : ''}',
          excludeSemantics: true,
          child: Material(
            color: on ? color : Colors.transparent,
            borderRadius: Radii.field,
            child: InkWell(
              borderRadius: Radii.field,
              onTap: onTap,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 9),
                child: Column(children: [
                  Text(count > 0 ? '$label ($count)' : label,
                      style: AppText.bodyStrong.copyWith(fontWeight: FontWeight.w800, color: on ? AppColors.white : AppColors.darkCocoa)),
                  Text(sub, style: AppText.small.copyWith(color: on ? AppColors.white : AppColors.grayBrown)),
                ]),
              ),
            ),
          ),
        ),
      );
}

/// One request in the list.
class RequestCard extends ConsumerWidget {
  const RequestCard({super.key, required this.request});
  final CustomRequest request;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final r = request;
    final p = ref.watch(productProvider(r.productId));
    final q = r.latestQuote;
    final hint = switch (r.status) {
      RequestStatus.pending when r.side == ChatSide.selling => 'Send a quote or decline',
      RequestStatus.pending => q?.status == OfferStatus.changesRequested ? 'Waiting for a new quote' : 'Waiting for the maker',
      RequestStatus.quoted when r.side == ChatSide.buying && q != null => 'Quote ${Fmt.peso(q.price)} · accept or ask for changes',
      RequestStatus.quoted => 'Quote sent · waiting for the buyer',
      RequestStatus.accepted => 'Order ${r.orderNumber ?? ''}',
      RequestStatus.declined => 'Declined',
      RequestStatus.cancelled => 'Cancelled by the buyer',
    };
    return Semantics(
      button: true,
      label: 'Request ${r.code}, ${r.productTitle}, ${r.status.label}',
      excludeSemantics: true,
      child: Material(
        color: AppColors.white,
        shape: RoundedRectangleBorder(
            borderRadius: Radii.card, side: BorderSide(color: r.needsMyAction ? AppColors.amber : AppColors.linen, width: r.needsMyAction ? 1.5 : 1)),
        child: InkWell(
          borderRadius: Radii.card,
          onTap: () => context.push('/request/${r.code}'),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(children: [
              if (p != null) ...[ProductPhoto(product: p, width: 56, height: 56, radius: 10), const SizedBox(width: 12)],
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Expanded(child: Text(r.code, style: AppText.label.copyWith(fontWeight: FontWeight.w700))),
                    StatusPill(r.status.label, tone: r.status.tone, filled: true),
                  ]),
                  const SizedBox(height: 4),
                  Text('${r.productTitle} × ${r.quantity}', style: AppText.bodyStrong.copyWith(fontSize: 13.5), maxLines: 1, overflow: TextOverflow.ellipsis),
                  Text('${r.side == ChatSide.buying ? 'To' : 'From'} ${r.counterpart} · needed by ${Fmt.shortDate(r.neededBy)}',
                      style: AppText.caption, maxLines: 1, overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 4),
                  Text(hint,
                      style: AppText.label.copyWith(color: r.needsMyAction ? AppColors.amberText : AppColors.grayBrown, fontWeight: FontWeight.w700),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                ]),
              ),
              const SizedBox(width: 6),
              const CraftIcon(CraftIcons.chevron, size: 18, color: AppColors.grayBrown),
            ]),
          ),
        ),
      ),
    );
  }
}

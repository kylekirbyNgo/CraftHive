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
import '../disputes/report_problem_screen.dart';

/// Admin tab: open reports first (oldest first), then recent decisions.
class DisputeQueueList extends ConsumerWidget {
  const DisputeQueueList({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final active = ref.watch(disputeQueueProvider(true));
    final decided = ref.watch(disputeQueueProvider(false)).valueOrNull ?? const [];
    return RefreshIndicator(
      onRefresh: () async {
        ref
          ..invalidate(disputeQueueProvider(false))
          ..invalidate(disputeQueueProvider(true));
        await ref.read(disputeQueueProvider(true).future);
      },
      child: active.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => ListView(children: [
          EmptyState(
            icon: CraftIcons.info,
            title: "Couldn't load disputes",
            message: e is AppFailure ? e.message : 'Try again in a moment.',
            actionLabel: 'Try again',
            onAction: () => ref.invalidate(disputeQueueProvider(true)),
          ),
        ]),
        data: (open) => ListView(padding: const EdgeInsets.fromLTRB(Insets.screen, 12, Insets.screen, 32), children: [
          if (open.isEmpty)
            const EmptyState(icon: CraftIcons.check, title: 'No open disputes', message: 'Reports from buyers and sellers show up here.')
          else
            for (final d in open) ...[_DisputeTile(d), const SizedBox(height: 10)],
          if (decided.isNotEmpty) ...[
            const SizedBox(height: 8),
            const SectionHeader('Decided', padding: EdgeInsets.zero),
            const SizedBox(height: 6),
            for (final d in decided) ...[_DisputeTile(d), const SizedBox(height: 10)],
          ],
        ]),
      ),
    );
  }
}

class _DisputeTile extends StatelessWidget {
  const _DisputeTile(this.d);
  final Dispute d;

  @override
  Widget build(BuildContext context) => Material(
        color: AppColors.white,
        shape: const RoundedRectangleBorder(borderRadius: Radii.card, side: BorderSide(color: AppColors.linen)),
        child: InkWell(
          borderRadius: Radii.card,
          onTap: () => context.push('/admin/dispute/${d.id}'),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(children: [
              const CraftIcon(CraftIcons.info, size: 22, color: AppColors.brick),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('${d.orderNumber} · ${d.storeName}', style: AppText.bodyStrong),
                  Text(d.reason, style: AppText.caption, maxLines: 2, overflow: TextOverflow.ellipsis),
                  Text('By the ${d.openedByBuyer ? 'buyer' : 'seller'} · ${Fmt.stamp(d.openedAt)} · ${Fmt.count(d.evidence.length, 'photo')}',
                      style: AppText.caption.copyWith(fontSize: 11.5)),
                ]),
              ),
              const SizedBox(width: 8),
              StatusPill(d.status.label, tone: d.status.tone),
            ]),
          ),
        ),
      );
}

/// One dispute: the order, accepted quote, payments and both sides' photos,
/// then Start review / Resolve / Close.
class AdminDisputeScreen extends ConsumerStatefulWidget {
  const AdminDisputeScreen({super.key, required this.disputeId});
  final String disputeId;
  @override
  ConsumerState<AdminDisputeScreen> createState() => _AdminDisputeScreenState();
}

class _AdminDisputeScreenState extends ConsumerState<AdminDisputeScreen> {
  bool _busy = false;

  Future<void> _set(Dispute d, String status) async {
    String? text;
    if (status != 'under_review') {
      text = await askForText(
        context,
        title: status == 'resolved' ? 'Resolve the dispute' : 'Close without action',
        subtitle: 'Both the buyer and the seller see this decision.',
        hint: status == 'resolved'
            ? 'For example: The seller will refund ₱450 by GCash within 3 days.'
            : 'For example: The photos show the item as described, so no action is needed.',
        button: status == 'resolved' ? 'Resolve' : 'Close report',
        minLength: 10,
      );
      if (text == null) return;
    }
    if (!mounted) return;
    setState(() => _busy = true);
    final ok = await runWithMessage(
      context,
      () => ref.read(disputeActionsProvider).update(d, status, resolution: text),
      success: switch (status) { 'under_review' => 'Marked as under review.', 'resolved' => 'Dispute resolved.', _ => 'Report closed.' },
    );
    if (!mounted) return;
    setState(() => _busy = false);
    if (ok && status != 'under_review') context.pop();
  }

  @override
  Widget build(BuildContext context) {
    final all = [...?ref.watch(disputeQueueProvider(true)).valueOrNull, ...?ref.watch(disputeQueueProvider(false)).valueOrNull];
    final d = all.where((x) => x.id == widget.disputeId).firstOrNull;
    return Scaffold(
      appBar: ScreenHeader(title: d == null ? 'Dispute' : 'Dispute · ${d.orderNumber}', subtitle: d?.status.label, fallback: '/admin'),
      body: SafeArea(
        top: false,
        child: ResponsiveCenter(
          maxWidth: 760,
          child: d == null
              ? const Center(child: CircularProgressIndicator())
              : ListView(padding: const EdgeInsets.fromLTRB(Insets.screen, 4, Insets.screen, 32), children: [
                  _Row('Order', '${d.orderNumber} · ${d.orderStatus.replaceAll('_', ' ')} · ${Fmt.peso(d.orderTotal)}'),
                  _Row('Buyer', '${d.buyerName}${d.buyerUsername.isEmpty ? '' : ' (@${d.buyerUsername})'}'),
                  _Row('Store', d.storeName),
                  if (d.isCustom && d.quotePrice != null)
                    _Row('Quote', 'v${d.quoteVersion} · ${Fmt.peso(d.quotePrice!)}${d.quoteReadyBy == null ? '' : ' · ready by ${Fmt.date(d.quoteReadyBy!)}'}'),
                  for (final p in d.payments) _Row('Payment', '${Fmt.peso(p.amount)} · ref ${p.reference} · ${p.status.name}'),
                  if (d.payments.isEmpty) const _Row('Payment', 'No payment proof'),
                  const SizedBox(height: 12),
                  DisputeCard(dispute: d, showAddPhotos: false),
                  if (d.payments.any((p) => p.proofPath != null)) ...[
                    const SizedBox(height: 16),
                    Text('Payment proof', style: AppText.section),
                    const SizedBox(height: 8),
                    for (final p in d.payments)
                      if (p.proofPath != null) ...[PrivateImage(path: p.proofPath!, height: 180), const SizedBox(height: 8)],
                  ],
                  if (d.status.isActive) ...[
                    const SizedBox(height: 16),
                    if (d.status == DisputeStatus.open) ...[
                      AppButton(label: 'Start review', kind: ButtonKind.outline, icon: CraftIcons.clock, loading: _busy, onPressed: _busy ? null : () => _set(d, 'under_review')),
                      const SizedBox(height: 10),
                    ],
                    AppButton(label: 'Resolve', icon: CraftIcons.check, onPressed: _busy ? null : () => _set(d, 'resolved')),
                    const SizedBox(height: 10),
                    AppButton(label: 'Close without action', kind: ButtonKind.danger, onPressed: _busy ? null : () => _set(d, 'closed')),
                  ],
                ]),
        ),
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row(this.label, this.value);
  final String label;
  final String value;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(width: 78, child: Text(label, style: AppText.caption.copyWith(fontSize: 13))),
          Expanded(child: Text(value, style: AppText.body)),
        ]),
      );
}

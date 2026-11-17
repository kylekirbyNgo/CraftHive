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

const _maxPhotos = 5;

/// "Report a problem" on an order: the buyer or seller says what went wrong
/// and adds photos or screenshots. A CraftHive admin reviews it
/// (database/12_disputes.sql).
class ReportProblemScreen extends ConsumerStatefulWidget {
  const ReportProblemScreen({super.key, required this.number});
  final String number;
  @override
  ConsumerState<ReportProblemScreen> createState() => _ReportProblemScreenState();
}

class _ReportProblemScreenState extends ConsumerState<ReportProblemScreen> {
  String? _problem;
  final _details = TextEditingController();
  final _photos = <PickedImage>[];
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _details.dispose();
    super.dispose();
  }

  Future<void> _addPhoto() async {
    final p = await ref.read(photoPickerProvider)(context);
    if (p != null) setState(() => _photos.add(p));
  }

  Future<void> _send(Order o) async {
    final details = _details.text.trim();
    final error = _problem == null
        ? 'Choose what went wrong.'
        : details.length < 15
            ? 'Describe the problem in at least 15 characters.'
            : null;
    setState(() => _error = error);
    if (error != null) return;
    setState(() => _busy = true);
    final ok = await runWithMessage(
      context,
      () => ref.read(disputeActionsProvider).open(orderId: o.id, reason: '$_problem: $details', photos: List.of(_photos)),
      success: 'Problem reported. A CraftHive admin will review it.',
    );
    if (!mounted) return;
    setState(() => _busy = false);
    if (ok) context.pop();
  }

  @override
  Widget build(BuildContext context) {
    final o = ref.watch(orderProvider(widget.number));
    if (o == null) {
      return const Scaffold(appBar: ScreenHeader(title: 'Report a problem', fallback: '/orders'), body: Center(child: CircularProgressIndicator()));
    }
    final problems = o.side == ChatSide.buying ? buyerProblems : sellerProblems;
    return Scaffold(
      appBar: ScreenHeader(title: 'Report a problem', subtitle: o.number, fallback: '/order/${o.number}'),
      body: SafeArea(
        top: false,
        child: ResponsiveCenter(
          child: ListView(padding: const EdgeInsets.fromLTRB(Insets.screen, 4, Insets.screen, 32), children: [
            InfoNote(
              'Try the chat with ${o.counterpart} first. If you still can\'t agree, a CraftHive admin will look at the order, '
              'its payments${o.isCustom ? ', the accepted quote' : ''} and both sides\' photos, then decide.',
            ),
            const SizedBox(height: 18),
            Text('What went wrong?', style: AppText.section),
            const SizedBox(height: 8),
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final p in problems) AppChip(label: p, selected: _problem == p, color: AppColors.brick, onTap: () => setState(() => _problem = p)),
            ]),
            const SizedBox(height: 18),
            Text('Tell us what happened', style: AppText.section),
            const SizedBox(height: 8),
            TextField(
              controller: _details,
              maxLines: 5,
              maxLength: 900,
              decoration: const InputDecoration(hintText: 'What you expected, what you got, and what you already tried with the other side.'),
            ),
            const SizedBox(height: 10),
            Text('Photos or screenshots (${_photos.length} of $_maxPhotos)', style: AppText.section),
            const SizedBox(height: 4),
            Text('For example the item you received, the package, or the payment receipt. Both sides and the admin can see them.', style: AppText.caption),
            const SizedBox(height: 10),
            GridView.count(
              crossAxisCount: 3,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 8,
              crossAxisSpacing: 8,
              children: [
                for (var i = 0; i < _photos.length; i++) _PickedThumb(image: _photos[i], label: 'Photo ${i + 1}', onRemove: () => setState(() => _photos.removeAt(i))),
                if (_photos.length < _maxPhotos) DashedAddBox(label: 'Add photo', vertical: true, onTap: _addPhoto),
              ],
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!, style: AppText.caption.copyWith(color: AppColors.brick, fontSize: 13)),
            ],
            const SizedBox(height: 16),
            AppButton(label: 'Send report', kind: ButtonKind.danger, icon: CraftIcons.send, loading: _busy, onPressed: _busy ? null : () => _send(o)),
          ]),
        ),
      ),
    );
  }
}

class _PickedThumb extends StatelessWidget {
  const _PickedThumb({required this.image, required this.label, required this.onRemove});
  final PickedImage image;
  final String label;
  final VoidCallback onRemove;
  @override
  Widget build(BuildContext context) => Semantics(
        label: label,
        image: true,
        child: Stack(fit: StackFit.expand, children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Image.memory(image.bytes, fit: BoxFit.cover, errorBuilder: (_, __, ___) => Container(color: AppColors.lightSand)),
          ),
          Positioned(
            top: 4,
            right: 4,
            child: RoundIconButton(icon: CraftIcons.close, tooltip: 'Remove $label', size: 32, background: AppColors.white, onPressed: onRemove),
          ),
        ]),
      );
}

/// The report on an order, shown on Order details (buyer and seller) and to admins.
class DisputeCard extends ConsumerStatefulWidget {
  const DisputeCard({super.key, required this.dispute, this.showAddPhotos = true});
  final Dispute dispute;
  final bool showAddPhotos;
  @override
  ConsumerState<DisputeCard> createState() => _DisputeCardState();
}

class _DisputeCardState extends ConsumerState<DisputeCard> {
  bool _busy = false;

  Future<void> _addPhoto() async {
    final p = await ref.read(photoPickerProvider)(context);
    if (p == null || !mounted) return;
    setState(() => _busy = true);
    await runWithMessage(context, () => ref.read(disputeActionsProvider).addEvidence(widget.dispute, [p]), success: 'Photo added to the report.');
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final d = widget.dispute;
    String who(bool buyer, bool me) => me ? 'You' : (buyer ? 'The buyer' : 'The seller');
    final decided = !d.status.isActive;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: Radii.card,
        border: Border.all(color: decided ? AppColors.linen : AppColors.brick.withValues(alpha: 0.5)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Expanded(child: Text('Reported problem', style: AppText.section)),
          StatusPill(d.status.label, tone: d.status.tone),
        ]),
        const SizedBox(height: 6),
        Text('${who(d.openedByBuyer, d.openedByMe)} reported this on ${Fmt.stamp(d.openedAt)}', style: AppText.caption),
        const SizedBox(height: 8),
        Text(d.reason, style: AppText.body),
        if (decided && d.resolution != null) ...[
          const SizedBox(height: 12),
          InfoNote(
            'Decision${d.resolvedBy == null ? '' : ' by ${d.resolvedBy}'}${d.resolvedAt == null ? '' : ' on ${Fmt.date(d.resolvedAt!)}'}: ${d.resolution}',
            icon: CraftIcons.check,
            tone: d.status == DisputeStatus.resolved ? Tone.success : Tone.neutral,
          ),
        ] else if (d.status == DisputeStatus.underReview) ...[
          const SizedBox(height: 12),
          const InfoNote('A CraftHive admin is reviewing this report.', icon: CraftIcons.clock, tone: Tone.warning),
        ],
        if (d.evidence.isNotEmpty) ...[
          const SizedBox(height: 14),
          Text('Photos (${d.evidence.length})', style: AppText.label),
          const SizedBox(height: 8),
          GridView.count(
            crossAxisCount: 3,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 8,
            crossAxisSpacing: 8,
            childAspectRatio: 0.85,
            children: [
              for (final e in d.evidence)
                Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Expanded(child: PrivateImage(path: e.path, height: 90)),
                  const SizedBox(height: 2),
                  Text(who(e.byBuyer, e.byMe), style: AppText.small.copyWith(color: AppColors.grayBrown), maxLines: 1, overflow: TextOverflow.ellipsis),
                ]),
            ],
          ),
        ],
        if (widget.showAddPhotos && d.status.isActive && d.myRole != 'admin') ...[
          const SizedBox(height: 12),
          AppButton(label: 'Add a photo', icon: CraftIcons.camera, kind: ButtonKind.outline, height: 44, loading: _busy, onPressed: _busy ? null : _addPhoto),
        ],
      ]),
    );
  }
}

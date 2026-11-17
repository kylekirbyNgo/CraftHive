import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/format.dart';
import '../../data/models.dart';
import '../../data/providers.dart';
import '../../shared/widgets/action_helpers.dart';
import '../../shared/widgets/common.dart';
import '../../shared/widgets/craft_icon.dart';

/// Verified Maker: the maker sends a government ID and 2–6 photos of their
/// work; a CraftHive admin reviews them. The ID photo is only seen by admins
/// and is deleted 30 days after the review (Data Privacy Act of 2012).
class VerificationScreen extends ConsumerStatefulWidget {
  const VerificationScreen({super.key});
  @override
  ConsumerState<VerificationScreen> createState() => _VerificationScreenState();
}

const _minPortfolio = 2;
const _maxPortfolio = 6;

class _VerificationScreenState extends ConsumerState<VerificationScreen> {
  String? _idType;
  PickedImage? _id;
  final _portfolio = <PickedImage>[];
  bool _consent = false;
  bool _busy = false;
  bool _tried = false;

  Future<void> _pickId() async {
    final p = await ref.read(photoPickerProvider)(context);
    if (p != null) setState(() => _id = p);
  }

  Future<void> _addWork() async {
    final p = await ref.read(photoPickerProvider)(context);
    if (p != null) setState(() => _portfolio.add(p));
  }

  String? get _problem {
    if (_idType == null) return 'Choose the type of ID you are sending.';
    if (_id == null) return 'Add a photo of your ID.';
    if (_portfolio.length < _minPortfolio) return 'Add at least $_minPortfolio photos of your work.';
    if (!_consent) return 'Tick the box to agree to the ID check.';
    return null;
  }

  Future<void> _submit() async {
    setState(() => _tried = true);
    if (_problem != null) return;
    setState(() => _busy = true);
    final ok = await runWithMessage(
      context,
      () => ref.read(verificationActionsProvider).submit(idType: _idType!, id: _id!, portfolio: List.of(_portfolio)),
      success: 'Sent for review. We will update this page once an admin has checked it.',
    );
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (ok) {
        _id = null;
        _portfolio.clear();
        _consent = false;
        _tried = false;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final mine = ref.watch(myVerificationProvider);
    return Scaffold(
      appBar: const ScreenHeader(title: 'Verified Maker', fallback: '/store'),
      body: SafeArea(
        top: false,
        child: ResponsiveCenter(
          child: mine.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => EmptyState(
              icon: CraftIcons.info,
              title: "Couldn't load your status",
              message: e is AppFailure ? e.message : 'Try again in a moment.',
              actionLabel: 'Try again',
              onAction: () => ref.invalidate(myVerificationProvider),
            ),
            data: (v) => ListView(
              padding: const EdgeInsets.fromLTRB(Insets.screen, 4, Insets.screen, 32),
              children: [
                _StatusCard(v ?? const MyVerification()),
                const SizedBox(height: 12),
                _PrivacyNote(v ?? const MyVerification()),
                if ((v ?? const MyVerification()).status.canApply) ..._form(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _form() {
    final problem = _tried ? _problem : null;
    return [
      const SizedBox(height: 20),
      Text('1. Your government ID', style: AppText.section),
      const SizedBox(height: 8),
      DropdownButtonFormField<String>(
        initialValue: _idType,
        isExpanded: true,
        hint: const Text('Type of ID'),
        items: [for (final t in acceptedIdTypes) DropdownMenuItem(value: t, child: Text(t))],
        onChanged: (v) => setState(() => _idType = v),
      ),
      const SizedBox(height: 10),
      if (_id == null)
        DashedAddBox(label: 'Add ID photo', height: 96, onTap: _pickId)
      else
        _Thumb(image: _id!, height: 160, label: 'ID photo', onRemove: () => setState(() => _id = null)),
      const SizedBox(height: 6),
      Text('Front side, all four corners showing, name and photo readable.', style: AppText.caption),
      const SizedBox(height: 20),
      Text('2. Photos of your work', style: AppText.section),
      const SizedBox(height: 4),
      Text('$_minPortfolio to $_maxPortfolio photos of things you made yourself (${_portfolio.length} added).', style: AppText.caption),
      const SizedBox(height: 10),
      GridView.count(
        crossAxisCount: 3,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        mainAxisSpacing: 8,
        crossAxisSpacing: 8,
        children: [
          for (var i = 0; i < _portfolio.length; i++)
            _Thumb(image: _portfolio[i], label: 'Work photo ${i + 1}', onRemove: () => setState(() => _portfolio.removeAt(i))),
          if (_portfolio.length < _maxPortfolio) DashedAddBox(label: 'Add photo', vertical: true, onTap: _addWork),
        ],
      ),
      const SizedBox(height: 16),
      CheckboxListTile(
        value: _consent,
        contentPadding: EdgeInsets.zero,
        controlAffinity: ListTileControlAffinity.leading,
        onChanged: (v) => setState(() => _consent = v ?? false),
        title: Text(
          'I agree to CraftHive using my ID only to confirm who I am. It is seen only by CraftHive admins '
          'and deleted $idRetentionDays days after the review (Data Privacy Act of 2012).',
          style: AppText.body.copyWith(fontSize: 13),
        ),
      ),
      if (problem != null) ...[
        const SizedBox(height: 4),
        Text(problem, style: AppText.caption.copyWith(color: AppColors.brick, fontSize: 13)),
      ],
      const SizedBox(height: 12),
      AppButton(label: 'Send for review', icon: CraftIcons.send, loading: _busy, onPressed: _busy ? null : _submit),
    ];
  }
}

class _StatusCard extends StatelessWidget {
  const _StatusCard(this.v);
  final MyVerification v;

  @override
  Widget build(BuildContext context) {
    final (icon, title, body) = switch (v.status) {
      VerificationStatus.unverified => (
          CraftIcons.verified,
          'Get the Verified Maker badge',
          'Show buyers you make what you sell. Send a government ID and a few photos of your work, and a CraftHive admin will review them.',
        ),
      VerificationStatus.pending => (
          CraftIcons.clock,
          'Under review',
          'Sent${v.submittedAt == null ? '' : ' on ${Fmt.date(v.submittedAt!)}'}. This page updates once an admin has checked your documents.',
        ),
      VerificationStatus.verified => (
          CraftIcons.verified,
          'You are a Verified Maker',
          'Verified${v.verifiedAt == null ? '' : ' on ${Fmt.date(v.verifiedAt!)}'}. The badge shows on your store and listings.',
        ),
      VerificationStatus.rejected => (
          CraftIcons.info,
          'Not approved yet',
          '${v.reviewNote == null ? 'The admin could not confirm your documents.' : 'Admin note: ${v.reviewNote}'} You can fix this and send again below.',
        ),
    };
    final c = toneColors(v.status.tone);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: AppColors.white, borderRadius: Radii.card, border: Border.all(color: AppColors.linen)),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(color: c.tint, shape: BoxShape.circle),
          alignment: Alignment.center,
          child: CraftIcon(icon, size: 22, color: c.ink),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(child: Text(title, style: AppText.bodyStrong.copyWith(fontSize: 15))),
              StatusPill(v.status.label, tone: v.status.tone),
            ]),
            const SizedBox(height: 4),
            Text(body, style: AppText.body.copyWith(fontSize: 13)),
          ]),
        ),
      ]),
    );
  }
}

class _PrivacyNote extends StatelessWidget {
  const _PrivacyNote(this.v);
  final MyVerification v;

  @override
  Widget build(BuildContext context) {
    final purge = v.idPurgeDate;
    final today = DateUtils.dateOnly(DateTime.now());
    final String text;
    if (purge != null && !purge.isAfter(today) && !v.idOnFile) {
      text = 'Your ID photo was deleted on ${Fmt.date(purge)}, $idRetentionDays days after the review, as the Data Privacy Act requires.';
    } else if (purge != null) {
      text = 'Your ID photo will be deleted on ${Fmt.date(purge)}, $idRetentionDays days after the review. Only CraftHive admins can see it.';
    } else {
      text = 'Your ID is stored privately, seen only by CraftHive admins, and deleted $idRetentionDays days after the review (Data Privacy Act of 2012).';
    }
    return InfoNote(text, icon: CraftIcons.lock);
  }
}

class _Thumb extends StatelessWidget {
  const _Thumb({required this.image, required this.label, required this.onRemove, this.height});
  final PickedImage image;
  final String label;
  final VoidCallback onRemove;
  final double? height;

  @override
  Widget build(BuildContext context) => Semantics(
        label: label,
        image: true,
        child: SizedBox(
          height: height,
          child: Stack(fit: StackFit.expand, children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Image.memory(
                image.bytes,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => Container(
                  color: AppColors.lightSand,
                  alignment: Alignment.center,
                  child: const CraftIcon(CraftIcons.image, size: 24, color: AppColors.grayBrown),
                ),
              ),
            ),
            Positioned(
              top: 4,
              right: 4,
              child: RoundIconButton(icon: CraftIcons.close, tooltip: 'Remove $label', size: 32, background: AppColors.white, color: AppColors.darkCocoa, onPressed: onRemove),
            ),
          ]),
        ),
      );
}

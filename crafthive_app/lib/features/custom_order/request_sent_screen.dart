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

/// Screen 7 – Request sent: waiting for the seller, request summary with a
/// Pending pill, progress steps, and links to the request or Home.
class RequestSentScreen extends ConsumerWidget {
  const RequestSentScreen({super.key, required this.code});
  final String code;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final r = ref.watch(requestProvider(code));
    if (r == null) return const Scaffold(appBar: ScreenHeader(title: 'Request sent'), body: SizedBox());
    final p = ref.watch(productProvider(r.productId));
    final seller = p == null ? null : ref.watch(sellerProvider(p.sellerId));
    final accepted = r.status == RequestStatus.accepted;
    final quoted = r.status == RequestStatus.quoted || accepted;

    return Scaffold(
      appBar: const ScreenHeader(title: 'Request sent'),
      body: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(Insets.screen, 4, Insets.screen, 24),
          child: ResponsiveCenter(
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Container(
                width: 76,
                height: 76,
                margin: const EdgeInsets.only(top: 6),
                decoration: const BoxDecoration(color: Color(0xFFF8EBCB), shape: BoxShape.circle),
                alignment: Alignment.center,
                child: const CraftIcon(CraftIcons.clock, size: 38, color: AppColors.amberText, strokeWidth: 1.8),
              ),
              const SizedBox(height: 14),
              Text('Waiting for the seller', style: AppText.headline.copyWith(fontSize: 21), textAlign: TextAlign.center),
              const SizedBox(height: 6),
              Text('${r.counterpart.isEmpty ? 'The maker' : r.counterpart} usually replies within ${(seller?.replyTime ?? 'a few hours').replaceFirst('about ', '')}. Check Orders › Custom requests for their quote.',
                  style: AppText.body.copyWith(color: AppColors.grayBrown, fontSize: 13.5), textAlign: TextAlign.center),
              const SizedBox(height: 18),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(color: AppColors.white, borderRadius: Radii.card, border: Border.all(color: AppColors.linen)),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Expanded(child: Text('Request ${r.code}', style: AppText.label.copyWith(fontWeight: FontWeight.w700))),
                    StatusPill(r.status.label, tone: r.status.tone, filled: true),
                  ]),
                  const SizedBox(height: 10),
                  Row(children: [
                    if (p != null) ...[ProductPhoto(product: p, width: 48, height: 48, radius: 10), const SizedBox(width: 12)],
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text('${r.productTitle.isEmpty ? (p?.title ?? 'Item') : r.productTitle} × ${r.quantity}', style: AppText.bodyStrong.copyWith(fontSize: 13.5), maxLines: 1, overflow: TextOverflow.ellipsis),
                        const SizedBox(height: 2),
                        Text('${r.budget != null ? 'Budget ${Fmt.peso(r.budget!)} · ' : ''}needed by ${Fmt.shortDate(r.neededBy)}', style: AppText.caption),
                      ]),
                    ),
                  ]),
                  if (r.options.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    Wrap(spacing: 6, runSpacing: 6, children: [for (final o in r.options) StatusPill(o, tone: Tone.seller, filled: true)]),
                  ],
                ]),
              ),
              const SizedBox(height: 20),
              _Step(title: 'Request sent', sub: Fmt.stamp(r.sentAt), state: _S.done),
              _Step(title: 'Seller is reviewing', sub: 'Accepts with a price, or declines with a reason', state: quoted ? _S.done : _S.now),
              _Step(title: 'You confirm the quote', sub: 'Pay the seller and track the order in Orders', state: accepted ? _S.done : (quoted ? _S.now : _S.next)),
              const _Step(title: 'Made and delivered', sub: 'The seller updates progress with photos', state: _S.next, last: true),
              const SizedBox(height: 22),
              AppButton(label: 'View request', icon: CraftIcons.orders, onPressed: () => context.pushReplacement('/request/${r.code}')),
              const SizedBox(height: 10),
              AppButton(label: 'Back to home', kind: ButtonKind.outline, onPressed: () => context.go('/home')),
            ]),
          ),
        ),
      ),
    );
  }
}

enum _S { done, now, next }

class _Step extends StatelessWidget {
  const _Step({required this.title, required this.sub, required this.state, this.last = false});
  final String title;
  final String sub;
  final _S state;
  final bool last;

  @override
  Widget build(BuildContext context) {
    final color = switch (state) { _S.done => AppColors.fern, _S.now => AppColors.amber, _S.next => AppColors.linen };
    return Semantics(
      label: '$title, ${switch (state) { _S.done => 'done', _S.now => 'in progress', _S.next => 'not yet' }}. $sub',
      excludeSemantics: true,
      child: IntrinsicHeight(
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Column(children: [
            Container(
              width: 26,
              height: 26,
              decoration: BoxDecoration(color: state == _S.next ? AppColors.white : color, shape: BoxShape.circle, border: Border.all(color: color, width: 2)),
              alignment: Alignment.center,
              child: switch (state) {
                _S.done => const CraftIcon(CraftIcons.check, size: 15, color: AppColors.white, strokeWidth: 2.6),
                _S.now => const CraftIcon(CraftIcons.clock, size: 15, color: AppColors.white, strokeWidth: 2.2),
                _S.next => const SizedBox(),
              },
            ),
            if (!last) Expanded(child: Container(width: 2, margin: const EdgeInsets.symmetric(vertical: 3), color: state == _S.done ? AppColors.fern : AppColors.linen)),
          ]),
          const SizedBox(width: 12),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(top: 3, bottom: last ? 0 : 14),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(title, style: AppText.bodyStrong.copyWith(color: state == _S.next ? AppColors.grayBrown : AppColors.darkCocoa)),
                const SizedBox(height: 2),
                Text(sub, style: AppText.caption),
              ]),
            ),
          ),
        ]),
      ),
    );
  }
}

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
import 'admin_dashboard.dart';
import '../reports/reports_screen.dart';
import 'admin_dispute_screen.dart';

/// Admin home (CraftHive staff only): Overview dashboard, makers waiting for the
/// Verified Maker badge, past decisions, disputes, and staff accounts.
class AdminVerificationScreen extends ConsumerWidget {
  const AdminVerificationScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final waiting = ref.watch(verificationQueueProvider(true));
    final count = waiting.valueOrNull?.length;
    final disputes = ref.watch(disputeQueueProvider(true)).valueOrNull?.length;
    final user = ref.watch(authProvider);
    return DefaultTabController(
      length: 6,
      child: Scaffold(
        appBar: ScreenHeader(
          title: 'CraftHive admin',
          subtitle: user?.isSuperadmin ?? false ? 'Superadmin' : 'Moderator',
          showBack: false,
          trailing: TextButton.icon(
            onPressed: () => ref.read(authProvider.notifier).signOut(),
            icon: const CraftIcon(CraftIcons.logout, size: 16, color: AppColors.brick),
            label: const Text('Sign out'),
            style: TextButton.styleFrom(foregroundColor: AppColors.brick),
          ),
        ),
        body: SafeArea(
          top: false,
          child: ResponsiveCenter(
            maxWidth: 760,
            child: Column(children: [
              TabBar(isScrollable: true, tabAlignment: TabAlignment.start, tabs: [
                const Tab(text: 'Overview'),
                Tab(text: count == null ? 'Makers' : 'Makers ($count)'),
                const Tab(text: 'Reviewed'),
                Tab(text: disputes == null ? 'Disputes' : 'Disputes ($disputes)'),
                const Tab(text: 'Reports'),
                const Tab(text: 'Staff'),
              ]),
              const Expanded(
                child: TabBarView(children: [
                  AdminOverview(),
                  _QueueList(pending: true),
                  _QueueList(pending: false),
                  DisputeQueueList(),
                  ReportsList(sellerMode: false),
                  StaffList(),
                ]),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}

class _QueueList extends ConsumerWidget {
  const _QueueList({required this.pending});
  final bool pending;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final list = ref.watch(verificationQueueProvider(pending));
    return RefreshIndicator(
      onRefresh: () => ref.refresh(verificationQueueProvider(pending).future),
      child: list.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => ListView(children: [
          EmptyState(
            icon: CraftIcons.info,
            title: "Couldn't load applications",
            message: e is AppFailure ? e.message : 'Try again in a moment.',
            actionLabel: 'Try again',
            onAction: () => ref.invalidate(verificationQueueProvider(pending)),
          ),
        ]),
        data: (apps) => apps.isEmpty
            ? ListView(children: [
                EmptyState(
                  icon: CraftIcons.verified,
                  title: pending ? 'No one is waiting' : 'No decisions yet',
                  message: pending ? 'New applications show up here.' : 'Approved and rejected makers show up here.',
                ),
              ])
            : ListView.separated(
                padding: const EdgeInsets.fromLTRB(Insets.screen, 12, Insets.screen, 32),
                itemCount: apps.length,
                separatorBuilder: (_, __) => const SizedBox(height: 10),
                itemBuilder: (_, i) => _ApplicationTile(apps[i]),
              ),
      ),
    );
  }
}

class _ApplicationTile extends StatelessWidget {
  const _ApplicationTile(this.a);
  final VerificationApplication a;

  @override
  Widget build(BuildContext context) => Material(
        color: AppColors.white,
        shape: const RoundedRectangleBorder(borderRadius: Radii.card, side: BorderSide(color: AppColors.linen)),
        child: InkWell(
          borderRadius: Radii.card,
          onTap: () => context.push('/admin/maker/${a.sellerId}'),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(children: [
              Avatar(initials: _initials(a.storeName), color: AppColors.moss),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(a.storeName, style: AppText.bodyStrong),
                  Text('${a.ownerName} · ${a.city}', style: AppText.caption),
                  Text('Sent ${Fmt.stamp(a.submittedAt)} · ${a.idType ?? 'ID'} · ${Fmt.count(a.portfolio.length, 'work photo')}',
                      style: AppText.caption.copyWith(fontSize: 11.5)),
                ]),
              ),
              const SizedBox(width: 8),
              StatusPill(a.status.label, tone: a.status.tone),
            ]),
          ),
        ),
      );
}

String _initials(String name) {
  final w = name.trim().split(RegExp(r'\s+')).where((x) => x.isNotEmpty).toList();
  if (w.isEmpty) return '?';
  return (w.length == 1 ? w.first.substring(0, w.first.length >= 2 ? 2 : 1) : w[0][0] + w[1][0]).toUpperCase();
}

/// One application: the ID, the portfolio, and Approve / Not approved.
class AdminApplicationScreen extends ConsumerStatefulWidget {
  const AdminApplicationScreen({super.key, required this.sellerId});
  final String sellerId;
  @override
  ConsumerState<AdminApplicationScreen> createState() => _AdminApplicationScreenState();
}

class _AdminApplicationScreenState extends ConsumerState<AdminApplicationScreen> {
  bool _busy = false;

  Future<void> _decide(VerificationApplication a, bool approve) async {
    String? note;
    if (approve) {
      final ok = await confirmAction(context,
          title: 'Approve ${a.storeName}?',
          message: 'They get the Verified Maker badge. The ID photo will be deleted in $idRetentionDays days.',
          confirmLabel: 'Approve');
      if (!ok) return;
    } else {
      note = await askForText(context,
          title: 'Why is it not approved?',
          subtitle: 'The maker sees this and can send new documents.',
          hint: 'For example: The name on the ID is hard to read. Please send a clearer photo.',
          button: 'Send decision',
          minLength: 5);
      if (note == null) return;
    }
    if (!mounted) return;
    setState(() => _busy = true);
    final done = await runWithMessage(
      context,
      () => ref.read(verificationActionsProvider).review(sellerId: a.sellerId, approve: approve, note: note),
      success: approve ? '${a.storeName} is now a Verified Maker.' : 'Decision sent to ${a.storeName}.',
    );
    if (!mounted) return;
    setState(() => _busy = false);
    if (done) context.pop();
  }

  @override
  Widget build(BuildContext context) {
    final all = [...?ref.watch(verificationQueueProvider(true)).valueOrNull, ...?ref.watch(verificationQueueProvider(false)).valueOrNull];
    final a = all.where((x) => x.sellerId == widget.sellerId).firstOrNull;
    return Scaffold(
      appBar: ScreenHeader(title: a?.storeName ?? 'Application', subtitle: a?.status.label, fallback: '/admin'),
      body: SafeArea(
        top: false,
        child: ResponsiveCenter(
          maxWidth: 760,
          child: a == null
              ? const Center(child: CircularProgressIndicator())
              : ListView(padding: const EdgeInsets.fromLTRB(Insets.screen, 4, Insets.screen, 32), children: [
                  _InfoRow('Maker', '${a.ownerName} (@${a.username})'),
                  _InfoRow('Store', '${a.storeName} · ${a.city}'),
                  _InfoRow('Sent', Fmt.stamp(a.submittedAt)),
                  if (a.storeDescription.isNotEmpty) _InfoRow('About', a.storeDescription),
                  if (a.status != VerificationStatus.pending) ...[
                    _InfoRow('Decision', a.status.label + (a.verifiedAt == null ? '' : ' on ${Fmt.date(a.verifiedAt!)}')),
                    if (a.reviewNote != null) _InfoRow('Note', a.reviewNote!),
                  ],
                  const SizedBox(height: 16),
                  Text('Government ID · ${a.idType ?? 'not given'}', style: AppText.section),
                  const SizedBox(height: 8),
                  if (a.idImagePath != null)
                    PrivateImage(path: a.idImagePath!, height: 220)
                  else
                    InfoNote(
                      'The ID photo was deleted${a.idPurgeDate == null ? '' : ' on ${Fmt.date(a.idPurgeDate!)}'} under the Data Privacy Act.',
                      icon: CraftIcons.lock,
                    ),
                  if (a.idImagePath != null && a.idPurgeDate != null) ...[
                    const SizedBox(height: 6),
                    Text('Deleted automatically on ${Fmt.date(a.idPurgeDate!)}.', style: AppText.caption),
                  ],
                  const SizedBox(height: 18),
                  Text('Work photos (${a.portfolio.length})', style: AppText.section),
                  const SizedBox(height: 8),
                  GridView.count(
                    crossAxisCount: 3,
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    mainAxisSpacing: 8,
                    crossAxisSpacing: 8,
                    children: [for (final p in a.portfolio) PrivateImage(path: p, height: 110)],
                  ),
                  if (a.status == VerificationStatus.pending) ...[
                    const SizedBox(height: 16),
                    const InfoNote('Check that the name and photo on the ID match the maker, and that the work photos look like their listings.'),
                    const SizedBox(height: 16),
                    AppButton(label: 'Approve', icon: CraftIcons.verified, loading: _busy, onPressed: _busy ? null : () => _decide(a, true)),
                    const SizedBox(height: 10),
                    AppButton(label: 'Not approved', kind: ButtonKind.danger, onPressed: _busy ? null : () => _decide(a, false)),
                  ],
                ]),
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow(this.label, this.value);
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

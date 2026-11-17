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

/// Tab indexes on the admin home (admin_verification_screen.dart).
abstract final class AdminTabs {
  static const overview = 0, makers = 1, reviewed = 2, disputes = 3, reports = 4, staff = 5;
}

/// Admin dashboard: what is waiting, what was decided this week, and how the
/// ID-photo deletion (Data Privacy Act) is doing.
class AdminOverview extends ConsumerWidget {
  const AdminOverview({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authProvider);
    final dash = ref.watch(adminDashboardProvider);
    void go(int tab) => DefaultTabController.of(context).animateTo(tab);
    String since(DateTime? d) => d == null ? '' : 'Oldest from ${Fmt.shortDate(d)}';

    return RefreshIndicator(
      onRefresh: () => ref.read(adminActionsProvider).refreshAll(),
      child: dash.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => ListView(children: [
          EmptyState(
            icon: CraftIcons.info,
            title: "Couldn't load the dashboard",
            message: e is AppFailure ? e.message : 'Try again in a moment.',
            actionLabel: 'Try again',
            onAction: () => ref.invalidate(adminDashboardProvider),
          ),
        ]),
        data: (d) {
          final x = d ?? const AdminDashboard();
          return ListView(padding: const EdgeInsets.fromLTRB(Insets.screen, 14, Insets.screen, 32), children: [
            Row(children: [
              Expanded(child: Text('Hi, ${user?.firstName ?? 'admin'}', style: AppText.headline)),
              StatusPill(x.myRole == 'superadmin' ? 'Superadmin' : 'Moderator', tone: Tone.seller, filled: true),
            ]),
            const SizedBox(height: 4),
            Text('Pull down to refresh.', style: AppText.caption),
            const SizedBox(height: 14),
            if (x.idsOverdue > 0) ...[
              InfoNote(
                '${Fmt.count(x.idsOverdue, 'ID photo')} ${x.idsOverdue == 1 ? 'is' : 'are'} past the $idRetentionDays-day deletion date. '
                'Check that the purge-private-files job runs every day (Data Privacy Act).',
                tone: Tone.error,
                icon: CraftIcons.lock,
              ),
              const SizedBox(height: 12),
            ],
            _Grid(children: [
              _StatCard(
                label: 'Makers waiting',
                value: x.makersWaiting,
                detail: x.makersWaiting == 0 ? 'Nothing to review' : since(x.oldestWaitingAt),
                icon: CraftIcons.verified,
                tone: x.makersWaiting > 0 ? Tone.warning : Tone.success,
                onTap: () => go(AdminTabs.makers),
              ),
              _StatCard(
                label: 'Open disputes',
                value: x.disputesActive,
                detail: x.disputesActive == 0 ? 'Nothing to review' : '${x.disputesOpen} new · ${x.disputesUnderReview} under review',
                icon: CraftIcons.info,
                tone: x.disputesActive > 0 ? Tone.error : Tone.success,
                onTap: () => go(AdminTabs.disputes),
              ),
              _StatCard(
                label: 'Decided this week',
                value: x.approved7d + x.rejected7d + x.disputesDecided7d,
                detail: '${x.approved7d} approved · ${x.rejected7d} not approved · ${Fmt.count(x.disputesDecided7d, 'dispute')}',
                icon: CraftIcons.check,
                tone: Tone.info,
                onTap: () => go(AdminTabs.reviewed),
              ),
              _StatCard(
                label: 'Verified makers',
                value: x.makersVerified,
                detail: 'of ${Fmt.count(x.stores, 'store')}',
                icon: CraftIcons.store,
                tone: Tone.success,
              ),
              _StatCard(
                label: 'Your decisions',
                value: x.myDecisions7d,
                detail: 'Disputes you closed in 7 days',
                icon: CraftIcons.user,
                tone: Tone.neutral,
              ),
              _StatCard(
                label: 'Staff',
                value: x.staff,
                detail: x.myRole == 'superadmin' ? 'Add or deactivate staff' : 'Active admin accounts',
                icon: CraftIcons.lock,
                tone: Tone.seller,
                onTap: () => go(AdminTabs.staff),
              ),
            ]),
            const SizedBox(height: 18),
            Text('ID photos (Data Privacy Act)', style: AppText.section),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(color: AppColors.white, borderRadius: Radii.card, border: Border.all(color: AppColors.linen)),
              child: Column(children: [
                _Line('On file now', '${x.idsOnFile}'),
                _Line('Deleted within 7 days', '${x.idsDue7d}'),
                _Line('Deleted in the last 30 days', '${x.idsDeleted30d}'),
                _Line('Past their deletion date', '${x.idsOverdue}', alert: x.idsOverdue > 0),
              ]),
            ),
            const SizedBox(height: 6),
            Text('IDs are deleted $idRetentionDays days after the review.', style: AppText.caption),
          ]);
        },
      ),
    );
  }
}

class _Grid extends StatelessWidget {
  const _Grid({required this.children});
  final List<Widget> children;
  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, c) {
        final columns = c.maxWidth >= 600 ? 3 : 2;
        final w = (c.maxWidth - 10 * (columns - 1)) / columns;
        return Wrap(spacing: 10, runSpacing: 10, children: [for (final ch in children) SizedBox(width: w, child: ch)]);
      });
}

class _StatCard extends StatelessWidget {
  const _StatCard({required this.label, required this.value, required this.detail, required this.icon, required this.tone, this.onTap});
  final String label;
  final int value;
  final String detail;
  final String icon;
  final Tone tone;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = toneColors(tone);
    return Semantics(
      button: onTap != null,
      label: '$label: $value. $detail',
      excludeSemantics: true,
      child: Material(
        color: AppColors.white,
        shape: const RoundedRectangleBorder(borderRadius: Radii.card, side: BorderSide(color: AppColors.linen)),
        child: InkWell(
          borderRadius: Radii.card,
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Container(
                  width: 30,
                  height: 30,
                  decoration: BoxDecoration(color: c.tint, shape: BoxShape.circle),
                  alignment: Alignment.center,
                  child: CraftIcon(icon, size: 16, color: c.ink),
                ),
                const Spacer(),
                if (onTap != null) const CraftIcon(CraftIcons.chevron, size: 16, color: AppColors.grayBrown),
              ]),
              const SizedBox(height: 10),
              Text('$value', style: AppText.display.copyWith(fontSize: 26)),
              Text(label, style: AppText.bodyStrong.copyWith(fontSize: 13)),
              const SizedBox(height: 2),
              Text(detail, style: AppText.caption.copyWith(fontSize: 11.5), maxLines: 2, overflow: TextOverflow.ellipsis),
            ]),
          ),
        ),
      ),
    );
  }
}

class _Line extends StatelessWidget {
  const _Line(this.label, this.value, {this.alert = false});
  final String label;
  final String value;
  final bool alert;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(children: [
          Expanded(child: Text(label, style: AppText.body)),
          Text(value, style: AppText.bodyStrong.copyWith(color: alert ? AppColors.brick : AppColors.darkCocoa)),
        ]),
      );
}

// ---------------------------------------------------------------------------
// Staff accounts
// ---------------------------------------------------------------------------
class StaffList extends ConsumerWidget {
  const StaffList({super.key});

  Future<void> _add(BuildContext context, WidgetRef ref) async {
    final input = await showModalBottomSheet<_NewStaff>(context: context, isScrollControlled: true, builder: (_) => const _AddStaffSheet());
    if (input == null || !context.mounted) return;
    await runWithMessage(
      context,
      () => ref.read(adminActionsProvider).invite(email: input.email, firstName: input.first, lastName: input.last, role: input.role),
      success: 'Added ${input.first}. They will get an email to choose a password.',
    );
  }

  Future<void> _menu(BuildContext context, WidgetRef ref, StaffMember s, String action) async {
    final actions = ref.read(adminActionsProvider);
    switch (action) {
      case 'superadmin':
      case 'moderator':
        await runWithMessage(context, () => actions.setRole(s, action), success: '${s.firstName} is now a $action.');
      case 'deactivate':
        final ok = await confirmAction(context,
            title: 'Deactivate ${s.name}?',
            message: 'They can no longer sign in. Their name stays on the makers and disputes they decided.',
            confirmLabel: 'Deactivate',
            danger: true);
        if (ok && context.mounted) await runWithMessage(context, () => actions.setActive(s, false), success: '${s.firstName} was deactivated.');
      case 'reactivate':
        await runWithMessage(context, () => actions.setActive(s, true), success: '${s.firstName} can sign in again.');
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isSuper = ref.watch(authProvider)?.isSuperadmin ?? false;
    final staff = ref.watch(staffProvider);
    return RefreshIndicator(
      onRefresh: () => ref.refresh(staffProvider.future),
      child: staff.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => ListView(children: [
          EmptyState(
            icon: CraftIcons.info,
            title: "Couldn't load staff",
            message: e is AppFailure ? e.message : 'Try again in a moment.',
            actionLabel: 'Try again',
            onAction: () => ref.invalidate(staffProvider),
          ),
        ]),
        data: (list) => ListView(padding: const EdgeInsets.fromLTRB(Insets.screen, 12, Insets.screen, 32), children: [
          if (isSuper)
            AppButton(label: 'Add staff member', icon: CraftIcons.plus, onPressed: () => _add(context, ref))
          else
            const InfoNote('Only superadmins can add or deactivate staff.'),
          const SizedBox(height: 12),
          for (final s in list) ...[
            _StaffTile(s: s, canManage: isSuper && !s.isMe, onAction: (a) => _menu(context, ref, s, a)),
            const SizedBox(height: 10),
          ],
        ]),
      ),
    );
  }
}

class _StaffTile extends StatelessWidget {
  const _StaffTile({required this.s, required this.canManage, required this.onAction});
  final StaffMember s;
  final bool canManage;
  final ValueChanged<String> onAction;

  @override
  Widget build(BuildContext context) => Opacity(
        opacity: s.isActive ? 1 : 0.6,
        child: Container(
          padding: const EdgeInsets.fromLTRB(14, 12, 4, 12),
          decoration: BoxDecoration(color: AppColors.white, borderRadius: Radii.card, border: Border.all(color: AppColors.linen)),
          child: Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Flexible(child: Text(s.isMe ? '${s.name} (you)' : s.name, style: AppText.bodyStrong, overflow: TextOverflow.ellipsis)),
                  const SizedBox(width: 6),
                  StatusPill(s.isSuperadmin ? 'Superadmin' : 'Moderator', tone: s.isSuperadmin ? Tone.seller : Tone.info),
                  if (!s.isActive) ...[const SizedBox(width: 6), const StatusPill('Deactivated', tone: Tone.neutral)],
                ]),
                Text(s.email, style: AppText.caption),
                Text(
                  '${Fmt.count(s.decisions, 'decision')}${s.lastSignInAt == null ? '' : ' · last signed in ${Fmt.shortDate(s.lastSignInAt!)}'}',
                  style: AppText.caption.copyWith(fontSize: 11.5),
                ),
              ]),
            ),
            if (canManage)
              PopupMenuButton<String>(
                tooltip: 'Manage ${s.name}',
                onSelected: onAction,
                itemBuilder: (_) => [
                  if (s.isActive && !s.isSuperadmin) const PopupMenuItem(value: 'superadmin', child: Text('Make superadmin')),
                  if (s.isActive && s.isSuperadmin) const PopupMenuItem(value: 'moderator', child: Text('Make moderator')),
                  if (s.isActive) const PopupMenuItem(value: 'deactivate', child: Text('Deactivate')),
                  if (!s.isActive) const PopupMenuItem(value: 'reactivate', child: Text('Reactivate')),
                ],
              ),
          ]),
        ),
      );
}

class _NewStaff {
  const _NewStaff(this.first, this.last, this.email, this.role);
  final String first;
  final String last;
  final String email;
  final String role;
}

class _AddStaffSheet extends StatefulWidget {
  const _AddStaffSheet();
  @override
  State<_AddStaffSheet> createState() => _AddStaffSheetState();
}

class _AddStaffSheetState extends State<_AddStaffSheet> {
  final _first = TextEditingController();
  final _last = TextEditingController();
  final _email = TextEditingController();
  String _role = 'moderator';
  String? _error;

  @override
  void dispose() {
    for (final c in [_first, _last, _email]) {
      c.dispose();
    }
    super.dispose();
  }

  void _save() {
    final email = _email.text.trim().toLowerCase();
    final error = _first.text.trim().isEmpty || _last.text.trim().isEmpty
        ? 'Enter their first and last name.'
        : !RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email)
            ? 'Enter a valid work email.'
            : null;
    if (error != null) {
      setState(() => _error = error);
      return;
    }
    Navigator.pop(context, _NewStaff(_first.text.trim(), _last.text.trim(), email, _role));
  }

  @override
  Widget build(BuildContext context) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(Insets.screen, 0, Insets.screen, 16),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text('Add staff member', style: AppText.screenTitle),
              const SizedBox(height: 4),
              Text('Use a work email, not a marketplace account. They get an email to choose their own password.', style: AppText.caption.copyWith(fontSize: 13)),
              const SizedBox(height: 12),
              TextField(controller: _first, textCapitalization: TextCapitalization.words, decoration: const InputDecoration(labelText: 'First name')),
              const SizedBox(height: 10),
              TextField(controller: _last, textCapitalization: TextCapitalization.words, decoration: const InputDecoration(labelText: 'Last name')),
              const SizedBox(height: 10),
              TextField(controller: _email, keyboardType: TextInputType.emailAddress, decoration: const InputDecoration(labelText: 'Work email')),
              const SizedBox(height: 12),
              Text('Role', style: AppText.label),
              const SizedBox(height: 6),
              Wrap(spacing: 8, children: [
                AppChip(label: 'Moderator', selected: _role == 'moderator', onTap: () => setState(() => _role = 'moderator')),
                AppChip(label: 'Superadmin', selected: _role == 'superadmin', onTap: () => setState(() => _role = 'superadmin')),
              ]),
              const SizedBox(height: 6),
              Text(_role == 'moderator' ? 'Reviews makers and disputes.' : 'Also adds, promotes and deactivates staff.', style: AppText.caption),
              if (_error != null) ...[const SizedBox(height: 8), Text(_error!, style: AppText.caption.copyWith(color: AppColors.brick, fontSize: 13))],
              const SizedBox(height: 14),
              AppButton(label: 'Send invite', icon: CraftIcons.send, onPressed: _save),
            ]),
          ),
        ),
      );
}

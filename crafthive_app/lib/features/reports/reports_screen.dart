import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/geo.dart';
import '../../data/models.dart';
import '../../data/providers.dart';
import '../../shared/widgets/common.dart';
import '../../shared/widgets/craft_icon.dart';

/// The list of reports: all seven for admins; for a seller, the four about their own store.
class ReportsList extends StatelessWidget {
  const ReportsList({super.key, required this.sellerMode});
  final bool sellerMode;

  @override
  Widget build(BuildContext context) {
    final kinds = [for (final k in ReportKind.values) if (!sellerMode || k.forSellers) k];
    return ListView(padding: const EdgeInsets.fromLTRB(Insets.screen, 12, Insets.screen, 32), children: [
      Text(sellerMode ? 'Reports about your store. Copy any report as CSV to open it in a spreadsheet.' : 'Copy any report as CSV to open it in a spreadsheet.',
          style: AppText.caption.copyWith(fontSize: 13)),
      const SizedBox(height: 12),
      for (final k in kinds) ...[
        Material(
          color: AppColors.white,
          shape: const RoundedRectangleBorder(borderRadius: Radii.card, side: BorderSide(color: AppColors.linen)),
          child: InkWell(
            borderRadius: Radii.card,
            onTap: () => context.push(sellerMode ? '/store/reports/${k.name}' : '/admin/report/${k.name}'),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(children: [
                const CraftIcon(CraftIcons.grid, size: 22, color: AppColors.moss),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(k.title, style: AppText.bodyStrong),
                    Text(k.description, style: AppText.caption),
                  ]),
                ),
                const CraftIcon(CraftIcons.chevron, size: 16, color: AppColors.grayBrown),
              ]),
            ),
          ),
        ),
        const SizedBox(height: 10),
      ],
    ]);
  }
}

/// Seller page: My store → Store reports.
class StoreReportsScreen extends StatelessWidget {
  const StoreReportsScreen({super.key});
  @override
  Widget build(BuildContext context) => const Scaffold(
        appBar: ScreenHeader(title: 'Store reports', fallback: '/store'),
        body: SafeArea(top: false, child: ResponsiveCenter(child: ReportsList(sellerMode: true))),
      );
}

enum _Period {
  days30('30 days'),
  days90('90 days'),
  year('This year'),
  all('All time');

  const _Period(this.label);
  final String label;

  (DateTime?, DateTime?) range(DateTime now) {
    final today = DateTime(now.year, now.month, now.day);
    return switch (this) {
      _Period.days30 => (today.subtract(const Duration(days: 30)), today),
      _Period.days90 => (today.subtract(const Duration(days: 90)), today),
      _Period.year => (DateTime(now.year), today),
      _Period.all => (DateTime(2020), today),
    };
  }
}

/// One report with its filters (period, store, category, search term) and "Copy as CSV".
class ReportScreen extends ConsumerStatefulWidget {
  const ReportScreen({super.key, required this.kind, required this.sellerMode});
  final ReportKind kind;
  final bool sellerMode;
  @override
  ConsumerState<ReportScreen> createState() => _ReportScreenState();
}

class _ReportScreenState extends ConsumerState<ReportScreen> {
  _Period _period = _Period.days90;
  String? _storeId;
  String? _categoryId;
  String? _nearCity;
  final _query = TextEditingController();
  Future<ReportResult>? _future;

  ReportKind get kind => widget.kind;

  @override
  void initState() {
    super.initState();
    _nearCity = Geo.resolveCity(ref.read(authProvider)?.location ?? '');
    if (kind != ReportKind.searchBrowse) _future = _run();
  }

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  Future<ReportResult> _run() {
    final (from, to) = kind.usesPeriod ? _period.range(DateTime.now()) : (null, null);
    final store = widget.sellerMode ? ref.read(myStoreIdProvider) : _storeId;
    final f = ReportFilters(storeId: store, categoryId: _categoryId, from: from, to: to, query: _query.text, nearCity: _nearCity);
    return ref.read(reportRunnerProvider).run(kind, f);
  }

  void _load() {
    final future = _run();
    setState(() {
      _future = future;
    });
  }

  Future<void> _copy(ReportResult r) async {
    await Clipboard.setData(ClipboardData(text: r.toCsv()));
    if (mounted) showMessage(context, 'Copied ${r.records.length} rows as CSV. Paste them into a spreadsheet.');
  }

  @override
  Widget build(BuildContext context) {
    final categories = ref.watch(categoriesProvider);
    final stores = [for (final s in ref.watch(sellersProvider)) if (s.id != 'me') s];
    return Scaffold(
      appBar: ScreenHeader(
        title: kind.title,
        subtitle: 'Report',
        fallback: widget.sellerMode ? '/store/reports' : '/admin',
        trailing: FutureBuilder<ReportResult>(
          future: _future,
          builder: (_, snap) => snap.hasData
              ? RoundIconButton(icon: CraftIcons.share, tooltip: 'Copy as CSV', onPressed: () => _copy(snap.data!))
              : const SizedBox.shrink(),
        ),
      ),
      body: SafeArea(
        top: false,
        child: ResponsiveCenter(
          maxWidth: 900,
          child: ListView(padding: const EdgeInsets.fromLTRB(Insets.screen, 4, Insets.screen, 32), children: [
            Text(kind.description, style: AppText.caption.copyWith(fontSize: 13)),
            const SizedBox(height: 12),
            if (kind == ReportKind.searchBrowse) ...[
              TextField(
                controller: _query,
                textInputAction: TextInputAction.search,
                onSubmitted: (_) => _load(),
                decoration: const InputDecoration(hintText: 'Search term, e.g. crochet bag'),
              ),
              const SizedBox(height: 10),
              DropdownButtonFormField<String?>(
                initialValue: _nearCity,
                isExpanded: true,
                menuMaxHeight: 360,
                decoration: const InputDecoration(labelText: 'Distance from'),
                items: [
                  const DropdownMenuItem<String?>(value: null, child: Text('No city')),
                  for (final c in Geo.cities.keys) DropdownMenuItem<String?>(value: c, child: Text(c)),
                ],
                onChanged: (v) => _nearCity = v,
              ),
              const SizedBox(height: 10),
            ],
            if (kind.usesPeriod) ...[
              Wrap(spacing: 8, runSpacing: 8, children: [
                for (final p in _Period.values)
                  AppChip(label: p.label, selected: _period == p, onTap: () {
                    _period = p;
                    _load();
                  }),
              ]),
              const SizedBox(height: 10),
            ],
            if (kind.usesStore && !widget.sellerMode) ...[
              DropdownButtonFormField<String?>(
                initialValue: _storeId,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Store'),
                items: [
                  const DropdownMenuItem<String?>(value: null, child: Text('All stores')),
                  for (final s in stores) DropdownMenuItem<String?>(value: s.id, child: Text(s.name)),
                ],
                onChanged: (v) {
                  _storeId = v;
                  _load();
                },
              ),
              const SizedBox(height: 10),
            ],
            if (kind.usesCategory) ...[
              DropdownButtonFormField<String?>(
                initialValue: _categoryId,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Category'),
                items: [
                  const DropdownMenuItem<String?>(value: null, child: Text('All categories')),
                  for (final c in categories) DropdownMenuItem<String?>(value: c.id, child: Text(c.name)),
                ],
                onChanged: (v) {
                  _categoryId = v;
                  if (kind != ReportKind.searchBrowse) _load();
                },
              ),
              const SizedBox(height: 10),
            ],
            if (kind == ReportKind.searchBrowse) ...[
              AppButton(label: 'Run search', icon: CraftIcons.search, onPressed: _load),
              const SizedBox(height: 12),
            ],
            if (_future != null)
              FutureBuilder<ReportResult>(
                future: _future,
                builder: (_, snap) {
                  if (snap.connectionState != ConnectionState.done) {
                    return const Padding(padding: EdgeInsets.all(32), child: Center(child: CircularProgressIndicator()));
                  }
                  if (snap.hasError) {
                    final e = snap.error;
                    return EmptyState(
                      icon: CraftIcons.info,
                      title: "Couldn't load the report",
                      message: e is AppFailure ? e.message : 'Try again in a moment.',
                      actionLabel: 'Try again',
                      onAction: _load,
                    );
                  }
                  return _ReportBody(snap.data!);
                },
              ),
          ]),
        ),
      ),
    );
  }
}

class _ReportBody extends StatelessWidget {
  const _ReportBody(this.r);
  final ReportResult r;

  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final s in r.summary) StatusPill('${s.$1}: ${s.$2}', tone: Tone.info, filled: true),
        ]),
        const SizedBox(height: 12),
        if (r.records.isEmpty)
          const EmptyState(icon: CraftIcons.grid, title: 'Nothing to show', message: 'Try another period, store or category.')
        else
          for (final rec in r.records) ...[_RecordCard(rec), const SizedBox(height: 10)],
      ]);
}

class _RecordCard extends StatelessWidget {
  const _RecordCard(this.r);
  final ReportRecord r;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: AppColors.white, borderRadius: Radii.card, border: Border.all(color: AppColors.linen)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(r.title, style: AppText.bodyStrong.copyWith(fontSize: 15)),
                if (r.subtitle != null) Text(r.subtitle!, style: AppText.caption),
              ]),
            ),
            if (r.badge != null) ...[const SizedBox(width: 8), StatusPill(r.badge!, tone: r.badgeTone)],
          ]),
          const SizedBox(height: 8),
          for (final f in r.fields)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                SizedBox(width: 150, child: Text(f.$1, style: AppText.caption)),
                Expanded(child: Text(f.$2, style: AppText.body.copyWith(fontSize: 13))),
              ]),
            ),
          if (r.lines.isNotEmpty) ...[
            const SizedBox(height: 8),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                headingRowHeight: 34,
                dataRowMinHeight: 30,
                dataRowMaxHeight: 40,
                horizontalMargin: 8,
                columnSpacing: 16,
                headingTextStyle: AppText.small.copyWith(color: AppColors.grayBrown),
                columns: [for (final c in r.lineColumns) DataColumn(label: Text(c))],
                rows: [
                  for (final line in r.lines)
                    DataRow(cells: [for (var i = 0; i < r.lineColumns.length; i++) DataCell(Text(i < line.length ? line[i] : '', style: AppText.caption.copyWith(color: AppColors.darkCocoa)))]),
                ],
              ),
            ),
          ],
        ]),
      );
}

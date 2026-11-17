import '../core/utils/format.dart';
import '../core/utils/geo.dart';
import 'models.dart';
import 'search.dart';

/// The seven reports from Milestone II ("Information Needs"). The database
/// builds them (database/14_reports.sql), except Search and Browse, which runs
/// the app's own search over the catalog.
enum ReportKind {
  storeDirectory('Store Directory', 'Every store with its listings, rating, items sold and verified status.', ReportScope.admin),
  productListing('Product Listing', 'Listings by store or category, with stock, photos and reviews.', ReportScope.store),
  searchBrowse('Search and Browse', 'What buyers see for a search: ready-by date, trust score and distance.', ReportScope.admin),
  customRequests('Custom Request and Quote', 'Each request once, with its quote versions in order.', ReportScope.store),
  orderPayment('Order and Payment', 'Each order once, with its items and payment proofs.', ReportScope.store),
  sellerReliability('Seller Reliability', 'Completed, cancelled and on-time orders, conversion, rating, disputes and trust score.', ReportScope.store),
  marketplaceActivity('Marketplace Activity', 'Listings, orders, requests and value per category.', ReportScope.admin);

  const ReportKind(this.title, this.description, this.scope);
  final String title;
  final String description;
  final ReportScope scope;

  /// Sellers can run this report for their own store.
  bool get forSellers => scope == ReportScope.store;
  bool get usesPeriod => this == customRequests || this == orderPayment || this == sellerReliability || this == marketplaceActivity;
  bool get usesStore => scope == ReportScope.store;
  bool get usesCategory => this == productListing || this == searchBrowse;

  static ReportKind? byName(String name) => values.where((k) => k.name == name).firstOrNull;
}

enum ReportScope { admin, store }

/// What a report is run for. Null dates mean "all time" (reliability and
/// activity then use the last 90 days, as the database does).
class ReportFilters {
  const ReportFilters({this.storeId, this.categoryId, this.from, this.to, this.query = '', this.nearCity});
  final String? storeId;
  final String? categoryId;
  final DateTime? from;
  final DateTime? to;
  final String query;
  final String? nearCity;
}

/// One report line: header fields once, then repeating lines (quote versions,
/// order items, payments) under it.
class ReportRecord {
  const ReportRecord({required this.title, this.subtitle, this.badge, this.badgeTone = Tone.neutral, this.fields = const [], this.lineColumns = const [], this.lines = const []});
  final String title;
  final String? subtitle;
  final String? badge;
  final Tone badgeTone;
  final List<(String, String)> fields;
  final List<String> lineColumns;
  final List<List<String>> lines;
}

class ReportResult {
  const ReportResult({required this.kind, required this.titleLabel, required this.records, this.summary = const []});
  final ReportKind kind;

  /// Column name for [ReportRecord.title] in the CSV, e.g. "Store Name".
  final String titleLabel;
  final List<ReportRecord> records;
  final List<(String, String)> summary;

  /// One CSV row per repeating line (or per record when it has none); header
  /// fields are repeated on each of its lines so the file sorts and filters well.
  String toCsv() {
    final fieldNames = <String>[];
    final lineNames = <String>[];
    for (final r in records) {
      for (final f in r.fields) {
        if (!fieldNames.contains(f.$1)) fieldNames.add(f.$1);
      }
      for (final c in r.lineColumns) {
        if (!lineNames.contains(c)) lineNames.add(c);
      }
    }
    String cell(String v) => RegExp(r'[",\n]').hasMatch(v) ? '"${v.replaceAll('"', '""')}"' : v;
    final out = StringBuffer()..writeln([titleLabel, ...fieldNames, ...lineNames].map(cell).join(','));
    for (final r in records) {
      final values = {for (final f in r.fields) f.$1: f.$2};
      final head = [r.title, for (final n in fieldNames) values[n] ?? ''];
      if (r.lines.isEmpty) {
        out.writeln([...head, for (final _ in lineNames) ''].map(cell).join(','));
      }
      for (final line in r.lines) {
        final byName = {for (var i = 0; i < r.lineColumns.length && i < line.length; i++) r.lineColumns[i]: line[i]};
        out.writeln([...head, for (final n in lineNames) byName[n] ?? ''].map(cell).join(','));
      }
    }
    return out.toString();
  }
}

// ---------------------------------------------------------------------------
// JSON rows → report (plain functions so they can be unit-tested)
// ---------------------------------------------------------------------------
String _s(Object? v) => v == null ? '—' : '$v';
String _peso(Object? v) => v == null ? '—' : Fmt.peso((v as num).toDouble());
String _rating(Object? v) => v == null ? 'No reviews' : (v as num).toStringAsFixed(1);
String _pct(Object? v) => v == null ? '—' : '${((v as num) * 100).round()}%';
String _date(Object? v) {
  if (v == null) return '—';
  final d = DateTime.tryParse(v as String);
  return d == null ? v : Fmt.date(d.toLocal());
}

String _words(Object? v) => _s(v).replaceAll('_', ' ');
List<Map<String, dynamic>> _rows(Object? rows) => [for (final r in (rows as List?) ?? const []) Map<String, dynamic>.from(r as Map)];

Tone _verifiedTone(String s) => switch (s) { 'verified' => Tone.success, 'pending' => Tone.warning, 'rejected' => Tone.error, _ => Tone.neutral };

ReportResult storeDirectoryReport(Object? json) {
  final rows = _rows(json);
  return ReportResult(
    kind: ReportKind.storeDirectory,
    titleLabel: 'Store Name',
    summary: [('Stores', '${rows.length}'), ('Verified', '${rows.where((r) => r['verified_status'] == 'verified').length}')],
    records: [
      for (final r in rows)
        ReportRecord(
          title: _s(r['store_name']),
          subtitle: '@${_s(r['seller_username'])}${r['archived'] == true ? ' · archived' : ''}',
          badge: _words(r['verified_status']),
          badgeTone: _verifiedTone('${r['verified_status']}'),
          fields: [
            ('Seller Username', _s(r['seller_username'])),
            ('Store Description', _s(r['store_description'])),
            ('Address', _s(r['address'])),
            ('Category Count', _s(r['category_count'])),
            ('Active Listings', _s(r['active_listings'])),
            ('Average Rating', _rating(r['avg_rating'])),
            ('Items Sold', _s(r['items_sold'])),
            ('Verified Status', _words(r['verified_status'])),
          ],
        ),
    ],
  );
}

ReportResult productListingReport(Object? json) {
  final rows = _rows(json);
  return ReportResult(
    kind: ReportKind.productListing,
    titleLabel: 'Product Title',
    summary: [('Listings', '${rows.length}'), ('Active', '${rows.where((r) => r['status'] == 'active').length}')],
    records: [
      for (final r in rows)
        ReportRecord(
          title: _s(r['product_title']),
          subtitle: '${_s(r['store_name'])} · ${_s(r['category_name'])}',
          badge: _s(r['status']),
          badgeTone: r['status'] == 'active' ? Tone.success : Tone.neutral,
          fields: [
            ('Category Name', _s(r['category_name'])),
            ('Store Name', _s(r['store_name'])),
            ('Price', _peso(r['price'])),
            ('Stock Quantity', _s(r['stock_quantity'])),
            ('Has Custom Option', r['has_custom_option'] == true ? 'Yes' : 'No'),
            ('Date Created', _date(r['created_at'])),
            ('Number of Images', _s(r['images'])),
            ('Number of Reviews', _s(r['reviews'])),
            ('Average Rating', _rating(r['avg_rating'])),
          ],
        ),
    ],
  );
}

ReportResult customRequestReport(Object? json) {
  final rows = _rows(json);
  return ReportResult(
    kind: ReportKind.customRequests,
    titleLabel: 'Request Number',
    summary: [('Requests', '${rows.length}'), ('Accepted', '${rows.where((r) => r['status'] == 'accepted').length}')],
    records: [
      for (final r in rows)
        ReportRecord(
          title: _s(r['request_number']),
          subtitle: '${_s(r['product_title'])} · ${_s(r['store_name'])}',
          badge: _s(r['status']),
          badgeTone: r['status'] == 'accepted' ? Tone.success : (r['status'] == 'declined' || r['status'] == 'cancelled' ? Tone.error : Tone.info),
          fields: [
            ('Buyer Username', _s(r['buyer_username'])),
            ('Seller Username', _s(r['seller_username'])),
            ('Base Product Title', _s(r['product_title'])),
            ('Quantity', _s(r['quantity'])),
            ('Budget', _peso(r['budget'])),
            ('Needed-By Date', _date(r['needed_by'])),
            ('Number of Reference Photos', _s(r['reference_photos'])),
          ],
          lineColumns: const ['Quote Number', 'Offered Price', 'Estimated Completion Date', 'Quote Status', 'Date Quoted'],
          lines: [
            for (final q in _rows(r['quotes']))
              ['v${_s(q['version'])}', _peso(q['price']), _date(q['completion']), _words(q['status']), _date(q['created_at'])],
          ],
        ),
    ],
  );
}

ReportResult orderPaymentReport(Object? json) {
  final rows = _rows(json);
  final value = rows.where((r) => r['status'] != 'cancelled').fold<double>(0, (s, r) => s + ((r['total'] as num?)?.toDouble() ?? 0));
  return ReportResult(
    kind: ReportKind.orderPayment,
    titleLabel: 'Order Number',
    summary: [('Orders', '${rows.length}'), ('Value (not cancelled)', Fmt.peso(value))],
    records: [
      for (final r in rows)
        ReportRecord(
          title: _s(r['order_number']),
          subtitle: '${_s(r['customer_name'])} → ${_s(r['store_name'])}',
          badge: _words(r['status']),
          badgeTone: r['status'] == 'cancelled' ? Tone.error : (r['status'] == 'completed' || r['status'] == 'delivered' ? Tone.success : Tone.info),
          fields: [
            ('Customer Full Name', _s(r['customer_name'])),
            ('Customer Username', _s(r['customer_username'])),
            ('Merchant Store Name', _s(r['store_name'])),
            ('Transaction Date', _date(r['order_date'])),
            ('Overall Amount', _peso(r['total'])),
            ('Current Order State', _words(r['status'])),
            ('Total Paid', _peso(r['total_paid'])),
          ],
          lineColumns: const ['Purchased Item Name', 'Order Quantity', 'Unit Cost at Sale', 'Payment Transaction Reference', 'Payment Amount', 'Verification Status of Payment', 'Date Confirmed'],
          lines: [
            for (final i in _rows(r['items'])) [_s(i['title']), _s(i['quantity']), _peso(i['unit_price']), '', '', '', ''],
            for (final p in _rows(r['payments'])) ['', '', '', _s(p['reference']), _peso(p['amount']), _s(p['status']), _date(p['verified_at'])],
          ],
        ),
    ],
  );
}

ReportResult sellerReliabilityReport(Object? json) {
  final rows = _rows(json);
  final first = rows.firstOrNull;
  return ReportResult(
    kind: ReportKind.sellerReliability,
    titleLabel: 'Store Name',
    summary: [
      if (first != null) ('Period', '${_date(first['from'])} – ${_date(first['to'])}'),
      ('Stores', '${rows.length}'),
    ],
    records: [
      for (final r in rows)
        ReportRecord(
          title: _s(r['store_name']),
          subtitle: '@${_s(r['seller_username'])}',
          badge: 'Trust ${_s(r['trust_score'])}',
          badgeTone: ((r['trust_score'] as num?) ?? 0) >= 75 ? Tone.success : (((r['trust_score'] as num?) ?? 0) >= 55 ? Tone.warning : Tone.error),
          fields: [
            ('Seller Username', _s(r['seller_username'])),
            ('Starting Date', _date(r['from'])),
            ('Ending Date', _date(r['to'])),
            ('Completed Orders', _s(r['completed'])),
            ('Cancelled Orders', _s(r['cancelled'])),
            ('On-Time Completion Rate', _pct(r['on_time_rate'])),
            ('Custom Requests Received', _s(r['requests'])),
            ('Quotes Accepted', _s(r['quotes_accepted'])),
            ('Request-to-Order Conversion Rate', _pct(r['conversion_rate'])),
            ('Average Review Rating', _rating(r['avg_rating'])),
            ('Disputes Opened', _s(r['disputes'])),
            ('Trust Score', _s(r['trust_score'])),
          ],
        ),
    ],
  );
}

ReportResult marketplaceReport(Object? json) {
  final rows = _rows(json);
  final first = rows.firstOrNull;
  final value = rows.fold<double>(0, (s, r) => s + ((r['total_order_value'] as num?)?.toDouble() ?? 0));
  return ReportResult(
    kind: ReportKind.marketplaceActivity,
    titleLabel: 'Category Name',
    summary: [
      if (first != null) ('Period', '${_date(first['from'])} – ${_date(first['to'])}'),
      ('Total order value', Fmt.peso(value)),
    ],
    records: [
      for (final r in rows)
        ReportRecord(
          title: _s(r['category_name']),
          fields: [
            ('Starting Date', _date(r['from'])),
            ('Ending Date', _date(r['to'])),
            ('Number of Listings', _s(r['listings'])),
            ('Number of Orders', _s(r['orders'])),
            ('Number of Custom Requests', _s(r['custom_requests'])),
            ('Total Order Value', _peso(r['total_order_value'])),
            ('Number of Verified Sellers', _s(r['verified_sellers'])),
            ('Average Trust Score', r['avg_trust_score'] == null ? '—' : _s(r['avg_trust_score'])),
          ],
        ),
    ],
  );
}

/// Search and Browse: runs the app's own search (typo-tolerant, every filter)
/// and lists what a buyer would see. [trust] maps store_id → trust score;
/// [storeIdOf] turns a catalog seller id into its store_id ("me" → my store).
ReportResult searchBrowseReport({
  required List<Product> products,
  required List<Seller> sellers,
  required List<Category> categories,
  required ReportFilters filters,
  required Map<String, int> trust,
  String Function(String sellerId)? storeIdOf,
  DateTime? today,
}) {
  final search = SearchFilters(query: filters.query, categoryId: filters.categoryId, nearCity: filters.nearCity);
  final results = searchProducts(products, sellers, search, categories: categories, today: today);
  final sellerById = {for (final s in sellers) s.id: s};
  final categoryName = {for (final c in categories) c.id: c.name};
  final here = filters.nearCity == null ? null : Geo.cityCoords(filters.nearCity!);
  final applied = [
    if (filters.categoryId != null) 'category: ${categoryName[filters.categoryId] ?? filters.categoryId}',
    if (filters.nearCity != null) 'near ${filters.nearCity}',
  ];
  return ReportResult(
    kind: ReportKind.searchBrowse,
    titleLabel: 'Product Title',
    summary: [('Search term', filters.query.trim().isEmpty ? '(none)' : '"${filters.query.trim()}"'), ('Results', '${results.length}')],
    records: [
      for (final p in results)
        () {
          final s = sellerById[p.sellerId];
          final there = s == null ? null : sellerCoords(s);
          final km = here == null || there == null ? null : Geo.distanceKm(here, there);
          final ready = estimateArrival(p, distanceKm: km, today: today);
          final score = trust[storeIdOf?.call(p.sellerId) ?? p.sellerId];
          return ReportRecord(
            title: p.title,
            subtitle: '${s?.name ?? ''} · ${Fmt.peso(p.price)}',
            badge: score == null ? null : 'Trust $score',
            badgeTone: (score ?? 0) >= 75 ? Tone.success : Tone.warning,
            fields: [
              ('Search Term', filters.query.trim()),
              ('Filters Applied', applied.isEmpty ? 'none' : applied.join('; ')),
              ('Category', categoryName[p.categoryId] ?? ''),
              ('Store Name', s?.name ?? ''),
              ('Price', Fmt.peso(p.price)),
              ('Ready-By Date', ready == null ? 'Sold out' : Fmt.date(ready)),
              ('Seller Trust Score', score == null ? '—' : '$score'),
              ('Distance', km == null ? '—' : '${km.round()} km'),
            ],
          );
        }(),
    ],
  );
}

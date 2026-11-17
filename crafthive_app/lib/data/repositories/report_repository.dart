import 'package:flutter/foundation.dart' show debugPrint;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../reports.dart';
import 'auth_repository.dart';

/// Reads the database reports (database/14_reports.sql). Returns the raw JSON
/// rows; lib/data/reports.dart turns them into a [ReportResult].
abstract class ReportRepository {
  Future<Object?> rows(ReportKind kind, ReportFilters f);

  /// store_id → seller trust score (last 180 days).
  Future<Map<String, int>> trustScores();
}

String? _day(DateTime? d) => d == null ? null : '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

class SupabaseReportRepository implements ReportRepository {
  SupabaseReportRepository(this._db);
  final SupabaseClient _db;

  Future<T> _run<T>(String what, Future<T> Function() call) => SupabaseAuthRepository.guard(() async {
        try {
          return await call();
        } on PostgrestException catch (e) {
          debugPrint('CraftHive: $what failed: ${e.code} ${e.message}');
          if (e.code == 'P0001') throw AppFailure(e.message);
          if (e.code == 'PGRST202' || e.code == '42883') {
            throw const AppFailure('Reports are not set up on the server yet. Run database/14_reports.sql in Supabase.');
          }
          rethrow;
        }
      });

  @override
  Future<Object?> rows(ReportKind kind, ReportFilters f) => _run('report ${kind.name}', () async {
        final period = {'p_from': _day(f.from), 'p_to': _day(f.to)};
        return switch (kind) {
          ReportKind.storeDirectory => _db.rpc<dynamic>('report_store_directory'),
          ReportKind.productListing => _db.rpc<dynamic>('report_product_listing', params: {'p_store_id': f.storeId, 'p_category_id': f.categoryId}),
          ReportKind.customRequests => _db.rpc<dynamic>('report_custom_requests', params: {'p_store_id': f.storeId, ...period}),
          ReportKind.orderPayment => _db.rpc<dynamic>('report_orders', params: {'p_store_id': f.storeId, ...period}),
          ReportKind.sellerReliability => _db.rpc<dynamic>('report_seller_reliability', params: {'p_store_id': f.storeId, ...period}),
          ReportKind.marketplaceActivity => _db.rpc<dynamic>('report_marketplace_activity', params: period),
          ReportKind.searchBrowse => Future.value(null), // built in the app
        };
      });

  @override
  Future<Map<String, int>> trustScores() => _run('trust scores', () async {
        final m = await _db.rpc<dynamic>('store_trust_scores');
        return {for (final e in Map<String, dynamic>.from((m as Map?) ?? const {}).entries) e.key: (e.value as num).toInt()};
      });
}

/// Turns raw rows into the report the screen shows.
ReportResult reportFromRows(ReportKind kind, Object? rows) => switch (kind) {
      ReportKind.storeDirectory => storeDirectoryReport(rows),
      ReportKind.productListing => productListingReport(rows),
      ReportKind.customRequests => customRequestReport(rows),
      ReportKind.orderPayment => orderPaymentReport(rows),
      ReportKind.sellerReliability => sellerReliabilityReport(rows),
      ReportKind.marketplaceActivity => marketplaceReport(rows),
      ReportKind.searchBrowse => throw ArgumentError('Search and Browse is built from the catalog'),
    };

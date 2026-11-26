import 'package:flutter/foundation.dart' show debugPrint;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models.dart';
import 'auth_repository.dart';
import 'listing_repository.dart' show photoType;
import 'order_repository.dart' show PickedImage, privateBucket;

/// Disputes ("Report a problem"): the buyer or seller of an order reports a
/// problem with photos, both sides add evidence, and a CraftHive admin records
/// the decision (database/12_disputes.sql).
abstract class DisputeRepository {
  /// The latest report on an order, or null.
  Future<Dispute?> forOrder(String orderId);

  /// Uploads up to 5 photos to private-files/{user_id}/{order_id}/ and opens the report.
  Future<Dispute> open({required String orderId, required String reason, List<PickedImage> photos = const [], String? note});

  /// Adds more photos (either side, while the report is open).
  Future<Dispute> addEvidence({required Dispute dispute, required List<PickedImage> photos, String? note});

  /// Admin: open and under-review reports ([active]) or decided ones.
  Future<List<Dispute>> queue({bool active = true});

  /// Admin: 'under_review', or 'resolved' / 'closed' with the decision text.
  Future<Dispute> update({required String disputeId, required String status, String? resolution});
}

Future<T> _run<T>(String what, Future<T> Function() call) => SupabaseAuthRepository.guard(() async {
      try {
        return await call();
      } on PostgrestException catch (e) {
        debugPrint('CraftHive: $what failed: ${e.code} ${e.message}');
        if (e.code == 'P0001' || (e.code ?? '').startsWith('PT')) throw AppFailure(e.message);
        if (e.code == 'PGRST202' || e.code == '42883') {
          throw const AppFailure('Reporting a problem is not set up on the server yet. Run database/12_disputes.sql in Supabase.');
        }
        rethrow;
      } on StorageException catch (e) {
        debugPrint('CraftHive: $what failed: ${e.statusCode} ${e.message}');
        throw const AppFailure("A photo didn't upload. Check your connection and try again.");
      }
    });

class SupabaseDisputeRepository implements DisputeRepository {
  SupabaseDisputeRepository(this._db);
  final SupabaseClient _db;

  String get _me => _db.auth.currentUser?.id ?? '';

  Future<List<String>> _upload(String orderId, List<PickedImage> photos) async {
    final stamp = DateTime.now().millisecondsSinceEpoch;
    final paths = <String>[];
    try {
      for (var i = 0; i < photos.length; i++) {
        final type = photoType(photos[i].fileName);
        final path = '$_me/$orderId/dispute_${stamp}_${i + 1}.${type.ext}';
        await _run('upload evidence', () => _db.storage.from(privateBucket).uploadBinary(path, photos[i].bytes, fileOptions: FileOptions(contentType: type.mime)));
        paths.add(path);
      }
      return paths;
    } catch (_) {
      await _remove(paths);
      rethrow;
    }
  }

  Future<void> _remove(List<String> paths) async {
    if (paths.isEmpty) return;
    try {
      await _db.storage.from(privateBucket).remove(paths);
    } catch (e) {
      debugPrint('CraftHive: clean-up of evidence photos failed: $e');
    }
  }

  @override
  Future<Dispute?> forOrder(String orderId) => _run('load report', () async {
        final row = await _db.rpc<dynamic>('order_dispute', params: {'p_order_id': orderId});
        return row == null ? null : disputeFromJson(Map<String, dynamic>.from(row as Map));
      });

  @override
  Future<Dispute> open({required String orderId, required String reason, List<PickedImage> photos = const [], String? note}) async {
    final paths = await _upload(orderId, photos);
    try {
      return await _run('open report', () async {
        final row = await _db.rpc<dynamic>('open_dispute', params: {'p_order_id': orderId, 'p_reason': reason, 'p_evidence_paths': paths, 'p_note': note});
        return disputeFromJson(Map<String, dynamic>.from(row as Map));
      });
    } catch (_) {
      await _remove(paths); // nothing was saved, so don't keep the photos
      rethrow;
    }
  }

  @override
  Future<Dispute> addEvidence({required Dispute dispute, required List<PickedImage> photos, String? note}) async {
    final paths = await _upload(dispute.orderId, photos);
    try {
      return await _run('add evidence', () async {
        final row = await _db.rpc<dynamic>('add_dispute_evidence', params: {'p_dispute_id': dispute.id, 'p_paths': paths, 'p_note': note});
        return disputeFromJson(Map<String, dynamic>.from(row as Map));
      });
    } catch (_) {
      await _remove(paths);
      rethrow;
    }
  }

  @override
  Future<List<Dispute>> queue({bool active = true}) => _run('load disputes', () async {
        final rows = await _db.rpc<dynamic>('dispute_queue', params: {'p_active': active});
        return [for (final r in (rows as List? ?? const [])) disputeFromJson(Map<String, dynamic>.from(r as Map))];
      });

  @override
  Future<Dispute> update({required String disputeId, required String status, String? resolution}) => _run('update dispute', () async {
        final row = await _db.rpc<dynamic>('update_dispute', params: {'p_dispute_id': disputeId, 'p_status': status, 'p_resolution': resolution});
        return disputeFromJson(Map<String, dynamic>.from(row as Map));
      });
}

// ---------------------------------------------------------------------------
// JSON → model (plain functions so they can be unit-tested)
// ---------------------------------------------------------------------------
DisputeStatus disputeStatusFromDb(String? s) => switch (s) {
      'under_review' => DisputeStatus.underReview,
      'resolved' => DisputeStatus.resolved,
      'closed' => DisputeStatus.closed,
      _ => DisputeStatus.open,
    };

String disputeStatusToDb(DisputeStatus s) => switch (s) {
      DisputeStatus.open => 'open',
      DisputeStatus.underReview => 'under_review',
      DisputeStatus.resolved => 'resolved',
      DisputeStatus.closed => 'closed',
    };

DateTime? _date(Object? v) => v == null ? null : DateTime.tryParse(v as String)?.toLocal();
double _num(Object? v) => (v as num?)?.toDouble() ?? 0;

PaymentStatus _payStatus(String? s) => switch (s) {
      'verified' => PaymentStatus.verified,
      'rejected' => PaymentStatus.rejected,
      _ => PaymentStatus.submitted,
    };

Dispute disputeFromJson(Map<String, dynamic> j) {
  final q = j['quote'] as Map?;
  return Dispute(
    id: j['dispute_id'] as String,
    orderId: j['order_id'] as String,
    orderNumber: (j['order_number'] as String?) ?? '',
    reason: (j['reason'] as String?) ?? '',
    status: disputeStatusFromDb(j['status'] as String?),
    openedAt: _date(j['opened_at']) ?? DateTime.now(),
    openedByBuyer: j['opened_by_role'] != 'seller',
    openedByMe: j['opened_by_me'] == true,
    myRole: (j['my_role'] as String?) ?? 'buyer',
    orderStatus: (j['order_status'] as String?) ?? '',
    orderTotal: _num(j['order_total']),
    isCustom: j['is_custom'] == true,
    buyerName: (j['buyer_name'] as String?) ?? '',
    buyerUsername: (j['buyer_username'] as String?) ?? '',
    storeName: (j['store_name'] as String?) ?? '',
    resolution: j['resolution'] as String?,
    resolvedAt: _date(j['resolved_at']),
    resolvedBy: j['resolved_by_name'] as String?,
    quoteVersion: (q?['version'] as num?)?.toInt(),
    quotePrice: q == null ? null : _num(q['price']),
    quoteReadyBy: _date(q?['ready_by']),
    payments: [
      for (final p in (j['payments'] as List?) ?? const [])
        DisputePayment(
          reference: ((p as Map)['reference'] as String?) ?? '',
          amount: _num(p['amount']),
          status: _payStatus(p['status'] as String?),
          proofPath: p['proof_path'] as String?,
        ),
    ],
    evidence: [
      for (final e in (j['evidence'] as List?) ?? const [])
        DisputeEvidence(
          path: (e as Map)['path'] as String,
          byBuyer: e['by_role'] != 'seller',
          byMe: e['by_me'] == true,
          uploadedAt: _date(e['uploaded_at']) ?? DateTime.now(),
          description: e['description'] as String?,
        ),
    ],
  );
}

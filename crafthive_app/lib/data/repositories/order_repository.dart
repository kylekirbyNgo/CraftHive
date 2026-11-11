import 'dart:typed_data';

import 'package:crypto/crypto.dart' show sha256;
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/utils/format.dart';
import '../models.dart';
import 'auth_repository.dart';
import 'listing_repository.dart' show photoType;

/// A photo picked on the phone, not uploaded yet (payment proof, reference photo).
class PickedImage {
  const PickedImage({required this.bytes, required this.fileName});
  final Uint8List bytes;
  final String fileName;

  /// SHA-256 of the file; the database rejects a receipt image used before.
  String get hash => sha256.convert(bytes).toString();
}

/// Ready-made orders (PostgreSQL: ORDERS, ORDER_ITEM, PAYMENT, ORDER_STATUS_HISTORY, REVIEW).
/// Every change goes through a database function that checks who may make it
/// (database/04_orders_and_custom_orders.sql).
abstract class OrderRepository {
  /// Orders I bought and orders for my store, newest first.
  Future<List<Order>> loadOrders();

  /// Buy now: reserves the stock and returns the new order number (CH-YYYY-000000).
  Future<String> placeOrder({required String productId, required int quantity});

  /// Uploads the receipt screenshot to private-files/{buyer_id}/{order_id}/ and saves the PAYMENT row.
  Future<void> submitPayment({required Order order, required String reference, required PickedImage proof});

  /// Seller: payment arrived (order becomes Confirmed) or it did not (with a reason).
  Future<void> reviewPayment({required Order order, required bool accept, String? reason});

  /// in_production, shipped, delivered (seller); completed (buyer); cancelled (either, while unpaid).
  Future<void> setStatus({required Order order, required String status, String? note});

  /// One review per product in a completed order.
  Future<void> postReview({required Order order, required int rating, String? comment});

  /// Signed link to view a private image (payment proof or reference photo).
  Future<String> privateImageUrl(String path);
}

const privateBucket = 'private-files';

/// Runs a call against Supabase and turns database errors into messages for the user.
/// Functions in 04_orders_and_custom_orders.sql raise their messages with SQLSTATE P0001.
Future<T> runDb<T>(String what, Future<T> Function() call) => SupabaseAuthRepository.guard(() async {
      try {
        return await call();
      } on PostgrestException catch (e) {
        debugPrint('CraftHive: $what failed: ${e.code} ${e.message}');
        if (e.code == 'P0001') throw AppFailure(e.message);
        if (e.code == '23505') throw AppFailure(duplicateMessage(e.message));
        if (e.code == 'PGRST202' || e.code == '42883') {
          throw const AppFailure('The order features are not set up on the server yet. Run database/04_orders_and_custom_orders.sql in Supabase.');
        }
        rethrow;
      } catch (e) {
        if (e is! AppFailure) debugPrint('CraftHive: $what failed: $e');
        rethrow;
      }
    });

String duplicateMessage(String dbMessage) {
  if (dbMessage.contains('reference_number')) return 'This reference number was already used for another payment.';
  if (dbMessage.contains('proof_image_hash')) return 'This receipt screenshot was already uploaded before.';
  if (dbMessage.contains('review')) return 'You already reviewed this item.';
  return 'This was already saved.';
}

class SupabaseOrderRepository implements OrderRepository {
  SupabaseOrderRepository(this._db);
  final SupabaseClient _db;

  String get _me => _db.auth.currentUser?.id ?? '';

  @override
  Future<List<Order>> loadOrders() => runDb('load orders', () async {
        try {
          // Frees stock held by orders that were never paid (24-hour reservation).
          await _db.rpc<dynamic>('release_expired_reservations');
        } on PostgrestException catch (e) {
          debugPrint('CraftHive: release reservations skipped: ${e.message}');
        }
        final rows = await _db.rpc<dynamic>('my_orders');
        return [for (final r in (rows as List? ?? const [])) orderFromJson(Map<String, dynamic>.from(r as Map))];
      });

  @override
  Future<String> placeOrder({required String productId, required int quantity}) => runDb('place order',
      () async => (await _db.rpc<dynamic>('place_order', params: {'p_product_id': productId, 'p_quantity': quantity})) as String);

  @override
  Future<void> submitPayment({required Order order, required String reference, required PickedImage proof}) async {
    final type = photoType(proof.fileName);
    final path = '$_me/${order.id}/proof_${DateTime.now().millisecondsSinceEpoch}.${type.ext}';
    await runDb('upload payment proof', () async {
      await _db.storage.from(privateBucket).uploadBinary(path, proof.bytes, fileOptions: FileOptions(contentType: type.mime));
    });
    try {
      await runDb('save payment', () async {
        await _db.rpc<dynamic>('submit_payment', params: {
          'p_order_id': order.id,
          'p_reference': reference,
          'p_proof_path': path,
          'p_proof_hash': proof.hash,
          'p_amount': order.total,
        });
      });
    } catch (_) {
      // The payment was refused (for example a reused reference), so remove the unused file.
      try {
        await _db.storage.from(privateBucket).remove([path]);
      } catch (e) {
        debugPrint('CraftHive: clean-up of $path failed: $e');
      }
      rethrow;
    }
  }

  @override
  Future<void> reviewPayment({required Order order, required bool accept, String? reason}) => runDb('check payment', () async {
        await _db.rpc<dynamic>('review_payment', params: {'p_order_id': order.id, 'p_accept': accept, 'p_reason': reason});
      });

  @override
  Future<void> setStatus({required Order order, required String status, String? note}) => runDb('update order', () async {
        await _db.rpc<dynamic>('set_order_status', params: {'p_order_id': order.id, 'p_status': status, 'p_note': note});
      });

  @override
  Future<void> postReview({required Order order, required int rating, String? comment}) => runDb('post review', () async {
        await _db.from('review').insert({
          'order_id': order.id,
          'product_id': order.productId,
          'rating': rating,
          'comment': (comment ?? '').trim().isEmpty ? null : comment!.trim(),
        });
      });

  @override
  Future<String> privateImageUrl(String path) =>
      runDb('open image', () => _db.storage.from(privateBucket).createSignedUrl(path, 60 * 60));
}

// ---------------------------------------------------------------------------
// JSON (from my_orders) → model. Plain functions so they can be unit-tested.
// ---------------------------------------------------------------------------

OrderStatus orderStatusFromDb(String s) => switch (s) {
      'pending' => OrderStatus.pending,
      'confirmed' => OrderStatus.confirmed,
      'in_production' => OrderStatus.inProduction,
      'shipped' => OrderStatus.shipped,
      'delivered' || 'completed' => OrderStatus.delivered,
      _ => OrderStatus.cancelled,
    };

PaymentStatus? paymentStatusFromDb(String? s) => switch (s) {
      'submitted' => PaymentStatus.submitted,
      'verified' => PaymentStatus.verified,
      'rejected' => PaymentStatus.rejected,
      _ => null,
    };

DateTime? _date(Object? v) => v == null ? null : DateTime.tryParse(v as String)?.toLocal();

Order orderFromJson(Map<String, dynamic> j) {
  final payment = j['payment'] == null ? null : Map<String, dynamic>.from(j['payment'] as Map);
  final placed = _date(j['order_date']) ?? DateTime.now();
  final status = orderStatusFromDb(j['status'] as String);
  return Order(
    id: j['order_id'] as String,
    number: j['order_number'] as String,
    side: j['side'] == 'selling' ? ChatSide.selling : ChatSide.buying,
    productId: (j['product_id'] as String?) ?? '',
    itemLabel: (j['product_title'] as String?) ?? 'Item',
    quantity: (j['quantity'] as num?)?.toInt() ?? 1,
    total: (j['total_amount'] as num).toDouble(),
    status: status,
    counterpart: (j['counterpart'] as String?) ?? '',
    placedOn: Fmt.date(placed),
    isCustom: j['is_custom'] == true,
    requestCode: j['request_number'] as String?,
    fulfillment: 'Arrange in chat',
    paymentMethod: 'GCash or bank transfer',
    paymentRef: payment?['reference_number'] as String?,
    paymentStatus: paymentStatusFromDb(payment?['status'] as String?),
    proofPath: payment?['proof_image_path'] as String?,
    dueDate: _date(j['due_date']),
    reservedUntil: status == OrderStatus.pending ? _date(j['reservation_expires_at']) : null,
    reviewed: j['reviewed'] == true,
    history: [
      for (final h in (j['history'] as List? ?? const []))
        OrderEvent(
          orderStatusFromDb((h as Map)['to_status'] as String),
          Fmt.stamp(_date(h['changed_at']) ?? placed),
          h['note'] as String?,
        ),
    ],
  );
}

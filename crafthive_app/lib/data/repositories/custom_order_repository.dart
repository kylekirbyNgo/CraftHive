import 'package:flutter/foundation.dart' show debugPrint;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models.dart';
import 'listing_repository.dart' show photoType;
import 'order_repository.dart';

/// What the buyer typed on the Custom order form (CUSTOM_REQUEST columns).
class CustomRequestInput {
  const CustomRequestInput({
    required this.productId,
    required this.description,
    required this.options,
    required this.quantity,
    required this.neededBy,
    this.budget,
    this.photo,
  });
  final String productId;
  final String description;
  final List<String> options;
  final int quantity;
  final DateTime neededBy;
  final double? budget;
  final PickedImage? photo;
}

/// Custom requests and quotes (PostgreSQL: CUSTOM_REQUEST, CUSTOM_REQUEST_OPTION,
/// CUSTOM_REQUEST_IMAGE, QUOTE; accepting a quote creates ORDERS and CAPACITY_BOOKING).
abstract class CustomOrderRepository {
  /// Requests I sent and requests for my store, newest first.
  Future<List<CustomRequest>> loadRequests();

  /// Returns the request number (CR-…).
  Future<String> submitRequest(CustomRequestInput input);

  Future<void> cancelRequest(CustomRequest request);

  /// Seller: a price and ready date. A new quote replaces the open one.
  Future<void> sendQuote({required CustomRequest request, required double price, required DateTime readyBy, String? message});

  /// Seller: say no, with a reason for the buyer.
  Future<void> declineRequest({required CustomRequest request, required String reason});

  /// Buyer accepts: returns the new order number. Fails when the maker is fully booked that week.
  Future<String> acceptQuote(QuoteOffer quote);

  /// Buyer asks for a different price or date; the seller can send a new quote.
  Future<void> requestChanges(QuoteOffer quote, String note);
}

String _day(DateTime d) => '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

class SupabaseCustomOrderRepository implements CustomOrderRepository {
  SupabaseCustomOrderRepository(this._db);
  final SupabaseClient _db;

  String get _me => _db.auth.currentUser?.id ?? '';

  @override
  Future<List<CustomRequest>> loadRequests() => runDb('load custom requests', () async {
        final rows = await _db.rpc<dynamic>('my_custom_requests');
        return [for (final r in (rows as List? ?? const [])) customRequestFromJson(Map<String, dynamic>.from(r as Map))];
      });

  @override
  Future<String> submitRequest(CustomRequestInput i) async {
    final saved = await runDb('send custom request', () async {
      final res = await _db.rpc<dynamic>('submit_custom_request', params: {
        'p_product_id': i.productId,
        'p_description': i.description,
        'p_quantity': i.quantity,
        'p_budget': i.budget,
        'p_needed_by': _day(i.neededBy),
        'p_options': i.options,
      });
      return Map<String, dynamic>.from(res as Map);
    });
    final requestId = saved['request_id'] as String;
    final photo = i.photo;
    if (photo != null) {
      // The request is already saved; a failed photo upload should not lose it.
      try {
        final type = photoType(photo.fileName);
        final path = '$_me/$requestId/reference_1.${type.ext}';
        await runDb('upload reference photo', () async {
          await _db.storage.from(privateBucket).uploadBinary(path, photo.bytes, fileOptions: FileOptions(contentType: type.mime));
          await _db.from('custom_request_image').insert({'request_id': requestId, 'image_path': path});
        });
      } catch (e) {
        debugPrint('CraftHive: reference photo not saved: $e');
      }
    }
    return saved['request_number'] as String;
  }

  @override
  Future<void> cancelRequest(CustomRequest r) => runDb('cancel request', () async {
        await _db.rpc<dynamic>('cancel_custom_request', params: {'p_request_id': r.id});
      });

  @override
  Future<void> sendQuote({required CustomRequest request, required double price, required DateTime readyBy, String? message}) =>
      runDb('send quote', () async {
        await _db.rpc<dynamic>('send_quote', params: {'p_request_id': request.id, 'p_price': price, 'p_ready_by': _day(readyBy), 'p_message': message});
      });

  @override
  Future<void> declineRequest({required CustomRequest request, required String reason}) => runDb('decline request', () async {
        await _db.rpc<dynamic>('decline_custom_request', params: {'p_request_id': request.id, 'p_reason': reason});
      });

  @override
  Future<String> acceptQuote(QuoteOffer quote) => runDb('accept quote',
      () async => (await _db.rpc<dynamic>('respond_to_quote', params: {'p_quote_id': quote.id, 'p_accept': true})) as String);

  @override
  Future<void> requestChanges(QuoteOffer quote, String note) => runDb('ask for changes', () async {
        await _db.rpc<dynamic>('respond_to_quote', params: {'p_quote_id': quote.id, 'p_accept': false, 'p_note': note});
      });
}

// ---------------------------------------------------------------------------
// JSON (from my_custom_requests) → model
// ---------------------------------------------------------------------------

RequestStatus requestStatusFromDb(String s) => switch (s) {
      'quoted' => RequestStatus.quoted,
      'accepted' => RequestStatus.accepted,
      'declined' => RequestStatus.declined,
      'cancelled' => RequestStatus.cancelled,
      _ => RequestStatus.pending,
    };

OfferStatus offerStatusFromDb(String s) => switch (s) {
      'accepted' => OfferStatus.accepted,
      'changes_requested' => OfferStatus.changesRequested,
      'declined' => OfferStatus.declined,
      'superseded' => OfferStatus.superseded,
      _ => OfferStatus.sent,
    };

DateTime _dt(Object? v) => (v == null ? null : DateTime.tryParse(v as String)?.toLocal()) ?? DateTime.now();

CustomRequest customRequestFromJson(Map<String, dynamic> j) => CustomRequest(
      id: j['request_id'] as String,
      code: j['request_number'] as String,
      side: j['side'] == 'selling' ? ChatSide.selling : ChatSide.buying,
      counterpart: (j['counterpart'] as String?) ?? '',
      productId: j['product_id'] as String,
      productTitle: (j['product_title'] as String?) ?? 'Item',
      description: (j['description'] as String?) ?? '',
      options: [for (final o in (j['options'] as List? ?? const [])) o as String],
      quantity: (j['quantity'] as num).toInt(),
      budget: (j['budget'] as num?)?.toDouble(),
      neededBy: _dt(j['needed_by_date']),
      sentAt: _dt(j['created_at']),
      status: requestStatusFromDb(j['status'] as String),
      orderNumber: j['order_number'] as String?,
      imagePaths: [for (final p in (j['image_paths'] as List? ?? const [])) p as String],
      quotes: [
        for (final q in (j['quotes'] as List? ?? const []))
          QuoteOffer(
            id: (q as Map)['quote_id'] as String,
            version: (q['version_no'] as num).toInt(),
            price: (q['offered_price'] as num).toDouble(),
            readyBy: _dt(q['estimated_completion_date']),
            status: offerStatusFromDb(q['status'] as String),
            createdAt: _dt(q['created_at']),
            message: q['message'] as String?,
            declineReason: q['decline_reason'] as String?,
          ),
      ],
    );

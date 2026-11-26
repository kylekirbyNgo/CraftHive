import 'package:flutter/foundation.dart' show debugPrint;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../api/api_client.dart';
import '../models.dart';
import 'auth_repository.dart' show AppFailure;
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

/// Custom requests and quotes through the CraftHive REST API (/api/v1/custom-requests).
class SupabaseCustomOrderRepository implements CustomOrderRepository {
  SupabaseCustomOrderRepository(this._db) : _api = ApiClient(_db);
  final SupabaseClient _db;
  final ApiClient _api;

  /// quote id → request id, so a quote can be answered at
  /// /custom-requests/{requestId}/quotes/{quoteId}.
  final _requestOfQuote = <String, String>{};

  String get _me => _db.auth.currentUser?.id ?? '';

  /// GET /custom-requests
  @override
  Future<List<CustomRequest>> loadRequests() async {
    final res = await _api.get('/custom-requests');
    final requests = [for (final j in res.list) customRequestFromApi(j)];
    for (final r in requests) {
      for (final q in r.quotes) {
        _requestOfQuote[q.id] = r.id;
      }
    }
    return requests;
  }

  /// POST /custom-requests, then the optional reference photo:
  /// upload to private-files/{buyer}/{request}/ and POST /custom-requests/{id}/images.
  @override
  Future<String> submitRequest(CustomRequestInput i) async {
    final res = await _api.post('/custom-requests', body: {
      'productId': i.productId,
      'description': i.description,
      'quantity': i.quantity,
      if (i.budget != null) 'budget': i.budget,
      'neededBy': _day(i.neededBy),
      'options': i.options,
    });
    final saved = res.map;
    final requestId = saved['requestId'] as String;
    final photo = i.photo;
    if (photo != null) {
      // The request is already saved; a failed photo upload should not lose it.
      try {
        final type = photoType(photo.fileName);
        final path = '$_me/$requestId/reference_1.${type.ext}';
        await runDb('upload reference photo', () async {
          await _db.storage.from(privateBucket).uploadBinary(path, photo.bytes, fileOptions: FileOptions(contentType: type.mime));
        });
        await _api.post('/custom-requests/$requestId/images', body: {'imagePath': path});
      } catch (e) {
        debugPrint('CraftHive: reference photo not saved: $e');
      }
    }
    return saved['requestNumber'] as String;
  }

  /// PATCH /custom-requests/{requestId} {"status": "cancelled"}
  @override
  Future<void> cancelRequest(CustomRequest r) async {
    await _api.patch('/custom-requests/${r.id}', body: {'status': 'cancelled'});
  }

  /// POST /custom-requests/{requestId}/quotes
  @override
  Future<void> sendQuote({required CustomRequest request, required double price, required DateTime readyBy, String? message}) async {
    await _api.post('/custom-requests/${request.id}/quotes', body: {
      'price': price,
      'readyBy': _day(readyBy),
      if (message != null && message.trim().isNotEmpty) 'message': message.trim(),
    });
  }

  /// PATCH /custom-requests/{requestId} {"status": "declined", "reason": ...}
  @override
  Future<void> declineRequest({required CustomRequest request, required String reason}) async {
    await _api.patch('/custom-requests/${request.id}', body: {'status': 'declined', 'reason': reason});
  }

  /// PATCH /custom-requests/{requestId}/quotes/{quoteId} {"status": "accepted"} → the new order.
  @override
  Future<String> acceptQuote(QuoteOffer quote) async {
    final res = await _api.patch(await _quotePath(quote), body: {'status': 'accepted'});
    final order = Map<String, dynamic>.from(res.map['order'] as Map);
    return order['orderNumber'] as String;
  }

  /// PATCH /custom-requests/{requestId}/quotes/{quoteId} {"status": "changes_requested"}
  @override
  Future<void> requestChanges(QuoteOffer quote, String note) async {
    await _api.patch(await _quotePath(quote), body: {
      'status': 'changes_requested',
      if (note.trim().isNotEmpty) 'note': note.trim(),
    });
  }

  Future<String> _quotePath(QuoteOffer quote) async {
    if (!_requestOfQuote.containsKey(quote.id)) await loadRequests();
    final requestId = _requestOfQuote[quote.id];
    if (requestId == null) throw const AppFailure('This quote is no longer open. Refresh to see the latest one.');
    return '/custom-requests/$requestId/quotes/${quote.id}';
  }
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


/// JSON from the REST API (GET /custom-requests, camelCase) → model.
CustomRequest customRequestFromApi(Map<String, dynamic> j) => CustomRequest(
      id: j['requestId'] as String,
      code: j['requestNumber'] as String,
      side: j['side'] == 'selling' ? ChatSide.selling : ChatSide.buying,
      counterpart: (j['counterpart'] as String?) ?? '',
      productId: j['productId'] as String,
      productTitle: (j['productTitle'] as String?) ?? 'Item',
      description: (j['description'] as String?) ?? '',
      options: [for (final o in (j['options'] as List? ?? const [])) o as String],
      quantity: (j['quantity'] as num).toInt(),
      budget: (j['budget'] as num?)?.toDouble(),
      neededBy: _dt(j['neededByDate']),
      sentAt: _dt(j['createdAt']),
      status: requestStatusFromDb(j['status'] as String),
      orderNumber: j['orderNumber'] as String?,
      imagePaths: [for (final p in (j['imagePaths'] as List? ?? const [])) p as String],
      quotes: [
        for (final q in (j['quotes'] as List? ?? const []))
          QuoteOffer(
            id: (q as Map)['quoteId'] as String,
            version: (q['versionNo'] as num).toInt(),
            price: (q['offeredPrice'] as num).toDouble(),
            readyBy: _dt(q['estimatedCompletionDate']),
            status: offerStatusFromDb(q['status'] as String),
            createdAt: _dt(q['createdAt']),
            message: q['message'] as String?,
            declineReason: q['declineReason'] as String?,
          ),
      ],
    );

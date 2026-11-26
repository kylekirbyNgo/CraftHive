import 'dart:typed_data';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../api/api_client.dart';
import 'auth_repository.dart';

/// One photo on the listing form: either already saved in Storage, or just
/// picked from the phone and not uploaded yet.
class ListingPhoto {
  const ListingPhoto.stored({required this.path, required this.url})
      : bytes = null,
        fileName = '';
  const ListingPhoto.picked({required this.bytes, required this.fileName})
      : path = null,
        url = null;

  /// Storage path (product_image.image_path) of a saved photo.
  final String? path;

  /// Public link of a saved photo.
  final String? url;

  /// The picked image, already resized and compressed by the picker.
  final Uint8List? bytes;
  final String fileName;

  bool get isNew => bytes != null;
}

/// What the seller typed on New listing / Edit listing (PRODUCT columns).
class ListingInput {
  const ListingInput({
    required this.title,
    required this.categoryId,
    required this.price,
    required this.stock,
    required this.leadDays,
    required this.description,
    required this.acceptsCustom,
    required this.customOptions,
    required this.photos,
    this.isDraft = false,
  });

  final String title;
  final String categoryId;
  final double price;
  final int stock;
  final int leadDays;
  final String description;
  final bool acceptsCustom;
  final List<String> customOptions;

  /// Cover first; at most 5 (product_image.sort_order 1–5).
  final List<ListingPhoto> photos;

  /// Drafts are saved with is_draft = true: only the seller sees them.
  final bool isDraft;

  Map<String, dynamic> toRow() => {
        'category_id': categoryId,
        'title': title,
        'description': description.isEmpty ? null : description,
        'price': price,
        'stock_quantity': stock,
        'lead_time_days': leadDays,
        'has_custom_option': acceptsCustom,
        'is_draft': isDraft,
      };

  /// The body for POST /products and PUT /products/{productId}.
  Map<String, dynamic> toApi(List<String> imagePaths) => {
        'categoryId': categoryId,
        'title': title,
        if (description.isNotEmpty) 'description': description,
        'price': price,
        'stockQuantity': stock,
        'leadTimeDays': leadDays,
        'acceptsCustomOrders': acceptsCustom,
        'customOptions': customOptions,
        'status': isDraft ? 'draft' : 'active',
        'imagePaths': imagePaths,
      };
}

/// What the seller typed on "Open your store" (STORE columns).
class StoreInput {
  const StoreInput({
    required this.storeName,
    required this.description,
    required this.address,
    required this.city,
    required this.postalCode,
    required this.weeklyCapacity,
  });

  final String storeName;
  final String description;
  final String address;
  final String city;
  final String postalCode;
  final int weeklyCapacity;
}

/// Opening a store and posting, editing and archiving listings.
abstract class ListingRepository {
  /// The user's store_id, or null when they have not opened a store yet.
  Future<String?> findMyStoreId(String userId);

  /// Makes the user a seller (SELLER, unverified) and opens their STORE. Returns the store_id.
  Future<String> openStore(String userId, StoreInput store);

  /// Saves PRODUCT, uploads the photos (PRODUCT_IMAGE) and the custom options
  /// (PRODUCT_CUSTOM_OPTION). Returns the new product_id.
  Future<String> createListing({required String storeId, required ListingInput input});

  /// [previousPaths] and [previousOptions] are what the listing had before
  /// editing, so removed photos and options can be deleted.
  Future<void> updateListing({
    required String storeId,
    required String productId,
    required ListingInput input,
    required List<String> previousPaths,
    required List<String> previousOptions,
  });

  /// Hides the listing from buyers (is_archived). Past orders keep their records.
  Future<void> archiveListing(String productId);
}

/// Content type for an image file; the product-images bucket accepts JPEG, PNG and WebP.
({String ext, String mime}) photoType(String fileName) {
  final n = fileName.toLowerCase();
  if (n.endsWith('.png')) return (ext: 'png', mime: 'image/png');
  if (n.endsWith('.webp')) return (ext: 'webp', mime: 'image/webp');
  return (ext: 'jpg', mime: 'image/jpeg');
}

/// Stores and listings through the CraftHive REST API (/api/v1/stores, /api/v1/products).
/// Photos are uploaded to Storage first; the API then saves the listing, its
/// photo list and its custom options in one database transaction.
class SupabaseListingRepository implements ListingRepository {
  SupabaseListingRepository(this._db) : _api = ApiClient(_db);
  final SupabaseClient _db;
  final ApiClient _api;

  static const bucket = 'product-images';

  /// One upload with the shared time limit and plain error messages.
  Future<T> _step<T>(String what, Future<T> Function() call) => SupabaseAuthRepository.guard(() async {
        try {
          return await call();
        } catch (e) {
          debugPrint('CraftHive listing: $what failed: $e');
          rethrow;
        }
      });

  /// Clean-up work whose failure should not hide the real error.
  Future<void> _quietly(String what, Future<void> Function() call) async {
    try {
      await call().timeout(const Duration(seconds: 20));
    } catch (e) {
      debugPrint('CraftHive listing: clean-up "$what" failed: $e');
    }
  }

  /// GET /stores → the one marked isMine.
  @override
  Future<String?> findMyStoreId(String userId) async {
    final res = await _api.get('/stores');
    return res.list.where((s) => s['isMine'] == true).map((s) => s['storeId'] as String).firstOrNull;
  }

  /// POST /stores → 201 Created. The API also makes the user a seller.
  @override
  Future<String> openStore(String userId, StoreInput s) async {
    final res = await _api.post('/stores', body: {
      'name': s.storeName,
      if (s.description.isNotEmpty) 'description': s.description,
      'address': s.address,
      'city': s.city,
      'postalCode': s.postalCode,
      'weeklyCapacity': s.weeklyCapacity,
    });
    return res.map['storeId'] as String;
  }

  /// Uploads the photos to {storeId}/listing_{time}/, then POST /products.
  @override
  Future<String> createListing({required String storeId, required ListingInput input}) async {
    final uploaded = <String>[];
    try {
      final folder = '$storeId/listing_${DateTime.now().millisecondsSinceEpoch}';
      final paths = await _savePhotos(folder, input.photos, uploaded);
      final res = await _api.post('/products', body: input.toApi(paths));
      return res.map['productId'] as String;
    } catch (_) {
      // Nothing was saved in the database, so only the uploaded files need removing.
      await _removeFiles(uploaded);
      rethrow;
    }
  }

  /// Uploads new photos to {storeId}/{productId}/, then PUT /products/{productId}
  /// with the whole listing. Photos left out are deleted from Storage afterwards.
  @override
  Future<void> updateListing({
    required String storeId,
    required String productId,
    required ListingInput input,
    required List<String> previousPaths,
    required List<String> previousOptions,
  }) async {
    final uploaded = <String>[];
    var paths = <String>[];
    try {
      paths = await _savePhotos('$storeId/$productId', input.photos, uploaded);
      await _api.put('/products/$productId', body: input.toApi(paths));
    } catch (_) {
      await _removeFiles(uploaded);
      rethrow;
    }
    await _removeFiles([for (final p in previousPaths) if (!paths.contains(p)) p]);
  }

  /// PATCH /products/{productId} {"status": "archived"}: hidden from buyers, past orders keep their records.
  @override
  Future<void> archiveListing(String productId) async {
    await _api.patch('/products/$productId', body: {'status': 'archived'});
  }

  /// Uploads the new photos into [folder] and returns every photo's path in
  /// order (cover first). [uploaded] collects new paths for clean-up.
  Future<List<String>> _savePhotos(String folder, List<ListingPhoto> photos, List<String> uploaded) async {
    final paths = <String>[];
    final stamp = DateTime.now().millisecondsSinceEpoch;
    for (var i = 0; i < photos.length; i++) {
      final photo = photos[i];
      if (!photo.isNew) {
        paths.add(photo.path!);
        continue;
      }
      final type = photoType(photo.fileName);
      final path = '$folder/${stamp}_${i + 1}.${type.ext}';
      await _step('upload photo ${i + 1}', () async {
        await _db.storage.from(bucket).uploadBinary(path, photo.bytes!, fileOptions: FileOptions(contentType: type.mime));
      });
      uploaded.add(path);
      paths.add(path);
    }
    return paths;
  }

  Future<void> _removeFiles(List<String> paths) async {
    final inStorage = [for (final p in paths) if (!p.startsWith('http')) p];
    if (inStorage.isEmpty) return;
    await _quietly('remove photos', () async {
      await _db.storage.from(bucket).remove(inStorage);
    });
  }
}

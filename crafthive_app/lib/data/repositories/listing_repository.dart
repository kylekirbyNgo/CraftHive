import 'dart:typed_data';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:supabase_flutter/supabase_flutter.dart';

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

class SupabaseListingRepository implements ListingRepository {
  SupabaseListingRepository(this._db);
  final SupabaseClient _db;

  static const bucket = 'product-images';

  /// One network step with the shared time limit and plain error messages.
  /// The original error is printed to the debug console to help testing.
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

  @override
  Future<String?> findMyStoreId(String userId) => _step('find store', () async {
        final row = await _db.from('store').select('store_id').eq('seller_id', userId).maybeSingle();
        return row?['store_id'] as String?;
      });

  @override
  Future<String> openStore(String userId, StoreInput s) => _step('open store', () async {
        final seller = await _db.from('seller').select('user_id').eq('user_id', userId).maybeSingle();
        if (seller == null) {
          await _db.from('seller').insert({'user_id': userId}); // verification_status starts as 'unverified'
        }
        final row = await _db
            .from('store')
            .insert({
              'seller_id': userId,
              'store_name': s.storeName,
              'store_description': s.description.isEmpty ? null : s.description,
              'address': s.address,
              'city': s.city,
              'postal_code': s.postalCode,
              'weekly_capacity': s.weeklyCapacity,
            })
            .select('store_id')
            .single();
        return row['store_id'] as String;
      });

  @override
  Future<String> createListing({required String storeId, required ListingInput input}) async {
    // Saved as a draft first, so buyers never see it before its photos are in.
    final productId = await _step('save product', () async {
      final row = await _db.from('product').insert({...input.toRow(), 'store_id': storeId, 'is_draft': true}).select('product_id').single();
      return row['product_id'] as String;
    });
    final uploaded = <String>[];
    try {
      final paths = await _savePhotos(storeId, productId, input.photos, uploaded);
      await _replaceImageRows(productId, paths);
      await _syncOptions(productId, input.customOptions, const []);
      if (!input.isDraft) {
        await _step('publish product', () async {
          await _db.from('product').update({'is_draft': false}).eq('product_id', productId);
        });
      }
      return productId;
    } catch (_) {
      // Undo the half-saved listing so the seller can simply try again.
      await _quietly('delete product', () async {
        await _db.from('product').delete().eq('product_id', productId);
      });
      await _removeFiles(uploaded);
      rethrow;
    }
  }

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
      paths = await _savePhotos(storeId, productId, input.photos, uploaded);
      await _replaceImageRows(productId, paths);
    } catch (_) {
      await _removeFiles(uploaded);
      rethrow;
    }
    await _syncOptions(productId, input.customOptions, previousOptions);
    // The product row last: publishing a draft only happens once its photos are saved.
    await _step('save product', () async {
      await _db.from('product').update(input.toRow()).eq('product_id', productId);
    });
    await _removeFiles([for (final p in previousPaths) if (!paths.contains(p)) p]);
  }

  @override
  Future<void> archiveListing(String productId) => _step('archive product', () async {
        await _db.from('product').update({'is_archived': true}).eq('product_id', productId);
      });

  /// Uploads the new photos to {store_id}/{product_id}/… and returns every
  /// photo's path in order (cover first). [uploaded] collects new paths for clean-up.
  Future<List<String>> _savePhotos(String storeId, String productId, List<ListingPhoto> photos, List<String> uploaded) async {
    final paths = <String>[];
    final stamp = DateTime.now().millisecondsSinceEpoch;
    for (var i = 0; i < photos.length; i++) {
      final photo = photos[i];
      if (!photo.isNew) {
        paths.add(photo.path!);
        continue;
      }
      final type = photoType(photo.fileName);
      final path = '$storeId/$productId/${stamp}_${i + 1}.${type.ext}';
      await _step('upload photo ${i + 1}', () async {
        await _db.storage.from(bucket).uploadBinary(path, photo.bytes!, fileOptions: FileOptions(contentType: type.mime));
      });
      uploaded.add(path);
      paths.add(path);
    }
    return paths;
  }

  Future<void> _replaceImageRows(String productId, List<String> paths) => _step('save photo list', () async {
        await _db.from('product_image').delete().eq('product_id', productId);
        if (paths.isEmpty) return;
        await _db.from('product_image').insert([
          for (var i = 0; i < paths.length; i++) {'product_id': productId, 'image_path': paths[i], 'sort_order': i + 1},
        ]);
      });

  /// Adds new option labels and deletes removed ones (kept ones stay, so past
  /// custom requests keep their links to them).
  Future<void> _syncOptions(String productId, List<String> wanted, List<String> previous) => _step('save options', () async {
        final removed = [for (final o in previous) if (!wanted.contains(o)) o];
        final added = [for (final o in wanted) if (!previous.contains(o)) o];
        if (removed.isNotEmpty) {
          await _db.from('product_custom_option').delete().eq('product_id', productId).inFilter('label', removed);
        }
        if (added.isNotEmpty) {
          await _db.from('product_custom_option').insert([for (final o in added) {'product_id': productId, 'label': o}]);
        }
      });

  Future<void> _removeFiles(List<String> paths) async {
    final inStorage = [for (final p in paths) if (!p.startsWith('http')) p];
    if (inStorage.isEmpty) return;
    await _quietly('remove photos', () async {
      await _db.storage.from(bucket).remove(inStorage);
    });
  }
}

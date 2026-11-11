import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/theme/app_colors.dart';
import '../../shared/widgets/craft_icon.dart';
import '../mock_data.dart';
import '../models.dart';
import 'auth_repository.dart';

/// Everything Home, Search and the stores need, loaded in one go.
class CatalogData {
  const CatalogData({required this.categories, required this.sellers, required this.products, this.myStoreId});
  final List<Category> categories;
  final List<Seller> sellers;
  final List<Product> products;

  /// The signed-in user's store (store.store_id), or null if they have not opened one yet.
  final String? myStoreId;

  static const empty = CatalogData(categories: [], sellers: [], products: []);
}

/// Reads categories, stores and product listings from PostgreSQL.
abstract class CatalogRepository {
  /// [myUserId] marks the signed-in user's own store and listings with the id "me".
  Future<CatalogData> load({required String myUserId});
}

/// How many top-rated listings appear in Home's Featured row.
const featuredCount = 5;

class SupabaseCatalogRepository implements CatalogRepository {
  SupabaseCatalogRepository(this._db);
  final SupabaseClient _db;

  @override
  Future<CatalogData> load({required String myUserId}) => SupabaseAuthRepository.guard(() async {
        final results = await Future.wait([
          _db.from('category').select('category_id, category_name'),
          _db.from('store_card').select(),
          _db.from('product_card').select().order('created_at', ascending: false),
        ]);
        final categories = [for (final r in results[0]) categoryFromRow(r)]..sort(_byPreferredOrder);
        final storeRows = results[1];
        final myStoreId = storeRows.where((r) => r['seller_id'] == myUserId).map((r) => r['store_id'] as String).firstOrNull;
        final sellers = [
          for (final r in storeRows)
            if (r['is_archived'] != true || r['store_id'] == myStoreId) sellerFromRow(r, isMine: r['store_id'] == myStoreId),
        ];
        final products = [
          for (final r in results[2])
            productFromRow(r, sellerId: r['store_id'] == myStoreId ? 'me' : r['store_id'] as String, imageUrl: _imageUrl),
        ];
        return CatalogData(categories: categories, sellers: sellers, products: markFeatured(products), myStoreId: myStoreId);
      });

  String _imageUrl(String path) =>
      path.startsWith('http') ? path : _db.storage.from('product-images').getPublicUrl(path);
}

// ---------------------------------------------------------------------------
// Row → model mapping (kept as plain functions so they can be unit-tested)
// ---------------------------------------------------------------------------

/// Icons and colours come from the app; the database keeps the names.
Category categoryFromRow(Map<String, dynamic> r) {
  final name = r['category_name'] as String;
  final look = MockData.categories.where((c) => c.name.toLowerCase() == name.toLowerCase()).firstOrNull;
  return Category(
    id: r['category_id'] as String,
    name: name,
    icon: look?.icon ?? CraftIcons.tag,
    tint: look?.tint ?? AppColors.lightSand,
    ink: look?.ink ?? AppColors.grayBrown,
  );
}

int _byPreferredOrder(Category a, Category b) {
  int rank(Category c) {
    final i = MockData.categories.indexWhere((m) => m.name.toLowerCase() == c.name.toLowerCase());
    return i < 0 ? 999 : i;
  }

  final r = rank(a).compareTo(rank(b));
  return r != 0 ? r : a.name.compareTo(b.name);
}

const _storeColors = [AppColors.moss, AppColors.clay, AppColors.slateTeal, Color(0xFFB07A16), Color(0xFF7B5A80), Color(0xFF9A6B12)];

Seller sellerFromRow(Map<String, dynamic> r, {required bool isMine}) {
  final name = r['store_name'] as String;
  final storeId = r['store_id'] as String;
  return Seller(
    id: isMine ? 'me' : storeId,
    name: name,
    initials: initialsOf(name),
    color: _storeColors[storeId.hashCode.abs() % _storeColors.length],
    location: (r['city'] as String?) ?? '',
    isVerified: r['verification_status'] == 'verified',
    rating: (r['rating'] as num?)?.toDouble() ?? 0,
    sold: (r['items_sold_count'] as num?)?.toInt() ?? 0,
    replyTime: 'a few hours',
    bio: (r['store_description'] as String?) ?? '',
  );
}

Product productFromRow(Map<String, dynamic> r, {required String sellerId, required String Function(String path) imageUrl}) {
  final paths = [for (final p in (r['image_paths'] as List?) ?? const []) p as String];
  return Product(
    id: r['product_id'] as String,
    title: r['title'] as String,
    sellerId: sellerId,
    categoryId: r['category_id'] as String,
    price: (r['price'] as num).toDouble(),
    description: (r['description'] as String?) ?? '',
    rating: (r['rating'] as num?)?.toDouble() ?? 0,
    reviewCount: (r['review_count'] as num?)?.toInt() ?? 0,
    sold: (r['sold_count'] as num?)?.toInt() ?? 0,
    stock: (r['stock_quantity'] as num?)?.toInt() ?? 0,
    leadDays: (r['lead_time_days'] as num?)?.toInt() ?? 0,
    acceptsCustom: r['has_custom_option'] == true,
    customOptions: [for (final o in (r['custom_options'] as List?) ?? const []) o as String],
    photoCount: paths.isEmpty ? 1 : paths.length,
    imageUrls: [for (final p in paths) imageUrl(p)],
    imagePaths: paths,
    status: r['is_archived'] == true
        ? ListingStatus.archived
        : r['is_draft'] == true
            ? ListingStatus.hidden
            : ListingStatus.active,
  );
}

/// Featured = the best-rated active listings from other makers (ties: more reviews, then more sold).
List<Product> markFeatured(List<Product> products) {
  final ranked = products.where((p) => p.status == ListingStatus.active && p.sellerId != 'me' && p.reviewCount > 0).toList()
    ..sort((a, b) {
      final r = b.rating.compareTo(a.rating);
      if (r != 0) return r;
      final c = b.reviewCount.compareTo(a.reviewCount);
      return c != 0 ? c : b.sold.compareTo(a.sold);
    });
  final featured = {for (final p in ranked.take(featuredCount)) p.id};
  return [for (final p in products) p.copyWith(isFeatured: featured.contains(p.id))];
}

String initialsOf(String name) {
  final words = name.replaceAll(RegExp(r'[^A-Za-z0-9 ]'), ' ').trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
  if (words.isEmpty) return '?';
  if (words.length == 1) return words.first.substring(0, words.first.length >= 2 ? 2 : 1).toUpperCase();
  return (words[0][0] + words[1][0]).toUpperCase();
}

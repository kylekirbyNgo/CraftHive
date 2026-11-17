import '../../data/models.dart';
import 'format.dart';

/// Links that open an item or a store in the CraftHive app, on the same
/// ph.crafthive.app scheme as password-reset links:
///   ph.crafthive.app://open/product/{product_id}
///   ph.crafthive.app://open/store/{store_id}
/// The shared message also names the item, price and store, so it is useful
/// even where a chat app does not make the link tappable.
abstract final class ShareLinks {
  static const scheme = 'ph.crafthive.app';
  static const host = 'open';
  static final _id = RegExp(r'^[A-Za-z0-9-]{1,64}$');

  static String product(String productId) => '$scheme://$host/product/$productId';
  static String store(String storeId) => '$scheme://$host/store/$storeId';

  /// The screen a shared link opens, or null if it is not a share link.
  /// [myStoreId] turns a link to your own store into My store.
  static String? routeFor(Uri uri, {String? myStoreId}) {
    if (uri.scheme != scheme || uri.host != host) return null;
    final parts = uri.pathSegments.where((s) => s.isNotEmpty).toList();
    if (parts.length != 2 || !_id.hasMatch(parts[1])) return null;
    return switch (parts[0]) {
      'product' => '/product/${parts[1]}',
      'store' => parts[1] == myStoreId ? '/store' : '/seller/${parts[1]}',
      _ => null,
    };
  }

  static String productText(Product p, Seller? s) {
    final where = s == null ? '' : ' by ${s.name}${s.location.isEmpty ? '' : ' (${s.location})'}';
    final custom = p.acceptsCustom ? ' Custom orders welcome.' : '';
    final rating = p.reviewCount > 0 ? ' ★ ${p.rating.toStringAsFixed(1)} (${Fmt.count(p.reviewCount, 'review')}).' : '';
    return '${p.title} – ${Fmt.peso(p.price)}$where on CraftHive.$rating$custom\n'
        'Open in the app: ${product(p.id)}';
  }

  static String storeText(Seller s, String storeId, {int listings = 0}) {
    final badge = s.isVerified ? ' (Verified Maker)' : '';
    final where = s.location.isEmpty ? '' : ' in ${s.location}';
    final count = listings > 0 ? ' ${Fmt.count(listings, 'handmade item')}.' : '';
    return '${s.name}$badge – handmade$where on CraftHive.$count\n'
        'Open in the app: ${store(storeId)}';
  }
}

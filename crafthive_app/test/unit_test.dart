import 'package:crafthive/core/utils/validators.dart';
import 'package:crafthive/data/models.dart';
import 'package:crafthive/data/repositories/auth_repository.dart';
import 'package:crafthive/data/repositories/catalog_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Validators', () {
    test('email', () {
      expect(Validators.email('you@email.com'), isNull);
      expect(Validators.email('  you@email.com '), isNull);
      expect(Validators.email(''), isNotNull);
      expect(Validators.email('you@email'), isNotNull);
      expect(Validators.email('you email@x.com'), isNotNull);
    });

    test('full name', () {
      expect(Validators.fullName('Ana Reyes'), isNull);
      expect(Validators.fullName("Ma. Liza Dela Cruz-O'Neil"), isNull);
      expect(Validators.fullName('Niño Peña'), isNull);
      expect(Validators.fullName('A'), isNotNull);
      expect(Validators.fullName('Ana123'), isNotNull);
    });

    test('Philippine and other mobile numbers', () {
      expect(Validators.phone('917 123 4567', country: 'Philippines'), isNull);
      expect(Validators.phone('817 123 4567', country: 'Philippines'), isNotNull);
      expect(Validators.phone('91712345', country: 'Philippines'), isNotNull);
      expect(Validators.phone('81234567', country: 'Singapore'), isNull);
      expect(Validators.phone('123', country: 'Singapore'), isNotNull);
    });

    test('username', () {
      expect(Validators.username('ana.makes'), isNull);
      expect(Validators.username('ana_makes_2026'), isNull);
      expect(Validators.username('Ana.Makes'), isNotNull);
      expect(Validators.username('abc'), isNotNull);
      expect(Validators.username('ana makes'), isNotNull);
      expect(Validators.username('.anamakes'), isNotNull);
      expect(Validators.username('a' * 21), isNotNull);
    });

    test('new password', () {
      expect(Validators.newPassword('craftlover8'), isNull);
      expect(Validators.newPassword('short1'), isNotNull);
      expect(Validators.newPassword('allletters'), isNotNull);
      expect(Validators.newPassword('12345678'), isNotNull);
    });

    test('stored phone keeps digits with the country code', () {
      expect(Validators.storedPhone('+63', '917 123 4567'), '639171234567');
      expect(formatPhone('639171234567'), '+63 917 123 4567');
    });
  });

  group('Catalog mapping', () {
    Map<String, dynamic> row(String id, {double rating = 4.5, int reviews = 2, int sold = 3, String store = 's1'}) => {
          'product_id': id,
          'store_id': store,
          'category_id': 'c1',
          'title': 'Item $id',
          'description': null,
          'price': 350,
          'stock_quantity': 4,
          'lead_time_days': 2,
          'has_custom_option': true,
          'is_draft': false,
          'is_archived': false,
          'rating': rating,
          'review_count': reviews,
          'sold_count': sold,
          'image_paths': ['s1/$id/1.jpg'],
          'custom_options': ['Color', 'Size'],
        };

    test('a product row becomes a Product', () {
      final p = productFromRow(row('p1'), sellerId: 's1', imageUrl: (path) => 'https://cdn/$path');
      expect(p.price, 350.0);
      expect(p.description, '');
      expect(p.customOptions, ['Color', 'Size']);
      expect(p.imageUrls, ['https://cdn/s1/p1/1.jpg']);
      expect(p.status, ListingStatus.active);
      expect(p.acceptsCustom, isTrue);
    });

    test('drafts and archived listings get the right status', () {
      expect(productFromRow({...row('p2'), 'is_draft': true}, sellerId: 's1', imageUrl: (p) => p).status, ListingStatus.hidden);
      expect(productFromRow({...row('p3'), 'is_archived': true}, sellerId: 's1', imageUrl: (p) => p).status, ListingStatus.archived);
    });

    test('featured = best rated from other makers, at most five', () {
      final products = [
        for (var i = 0; i < 8; i++) productFromRow(row('p$i', rating: 4.0 + i / 10), sellerId: 's1', imageUrl: (p) => p),
        productFromRow(row('mine', rating: 5), sellerId: 'me', imageUrl: (p) => p),
        productFromRow(row('unrated', rating: 0, reviews: 0), sellerId: 's2', imageUrl: (p) => p),
      ];
      final featured = markFeatured(products).where((p) => p.isFeatured).map((p) => p.id).toList();
      expect(featured.length, featuredCount);
      expect(featured, isNot(contains('mine')));
      expect(featured, isNot(contains('unrated')));
      expect(featured, contains('p7'));
    });

    test('store initials', () {
      expect(initialsOf('Narra Craft Co.'), 'NC');
      expect(initialsOf('Petal & Twine'), 'PT');
      expect(initialsOf('layerlab'), 'LA');
    });

    test('the signed-in user\'s store is marked "me"', () {
      final s = sellerFromRow({'store_id': 's9', 'store_name': 'My Shop', 'city': 'Cebu City', 'verification_status': 'verified', 'rating': 4.8, 'items_sold_count': 12}, isMine: true);
      expect(s.id, 'me');
      expect(s.isVerified, isTrue);
      expect(s.sold, 12);
    });
  });
}

import 'package:crafthive/core/utils/fuzzy.dart';
import 'package:crafthive/core/utils/geo.dart';
import 'package:crafthive/data/models.dart';
import 'package:crafthive/data/search.dart';
import 'package:flutter/material.dart';
import 'package:crafthive/data/repositories/fake_repositories.dart';
import 'package:flutter_test/flutter_test.dart';

import 'test_helpers.dart';

Seller _seller(String id, String name, String city, {double? lat, double? lng}) => Seller(
    id: id, name: name, initials: 'XX', color: Colors.brown, location: city, isVerified: true, rating: 4.5, sold: 1, replyTime: '', bio: '', latitude: lat, longitude: lng);

Product _product(String id, String title, String sellerId,
        {double price = 300, int stock = 5, int leadDays = 3, bool custom = false, String description = '', double rating = 4.5, String categoryId = 'c1'}) =>
    Product(
        id: id, title: title, sellerId: sellerId, categoryId: categoryId, price: price, description: description, stock: stock, leadDays: leadDays, acceptsCustom: custom, rating: rating);

void main() {
  final sellers = [
    _seller('cebu', 'Ana Makes Crochet', 'Cebu City', lat: 10.3157, lng: 123.8854),
    _seller('mandaue', 'Island Candles', 'Mandaue'), // no coordinates: city centre is used
    _seller('narra', 'Narra Craft Co.', 'Baguio City', lat: 16.41, lng: 120.60),
    _seller('davao', 'Clayfolk Studio', 'Davao City', lat: 7.07, lng: 125.61),
    _seller('nowhere', 'Mystery Shop', 'Philippines'),
  ];
  final products = [
    _product('p1', 'Hand-tied Sunflower Bouquet', 'cebu', description: 'Fresh sunflowers wrapped in kraft paper.'),
    _product('p2', 'Hand-carved Wooden Spoon', 'narra', stock: 0, leadDays: 6, custom: true, description: 'Carved from narra.'),
    _product('p3', 'Crochet Tote Bag', 'cebu', price: 680, custom: true, description: 'Roomy tote, pairs well with a bouquet.'),
    _product('p4', 'Soy Candle, Calamansi', 'mandaue', stock: 10),
    _product('p5', 'Stoneware Mug', 'davao', stock: 0, leadDays: 6, price: 2500),
    _product('p6', 'Lucky Keychain', 'nowhere'),
  ];
  final today = DateTime(2026, 11, 17);
  List<String> ids(SearchFilters f) => [for (final p in searchProducts(products, sellers, f, today: today)) p.id];

  group('Fuzzy matching', () {
    test('typos, swapped letters and accents', () {
      expect(Fuzzy.distance('candel', 'candle'), 1);
      expect(Fuzzy.distance('boquet', 'bouquet'), 1);
      expect(Fuzzy.distance('keychian', 'keychain'), 1);
      expect(Fuzzy.normalize('Niño Peña, 3D-Printed!'), 'nino pena 3d printed');
    });

    test('short words must match exactly', () {
      expect(Fuzzy.wordScore('mug', 'bag'), 0);
      expect(Fuzzy.wordScore('mug', 'mugs'), greaterThan(0));
    });

    test('a misspelled query still finds the listing', () {
      expect(ids(const SearchFilters(query: 'boquet')), containsAll(['p1', 'p3']));
      expect(ids(const SearchFilters(query: 'sunflwer')), ['p1']);
      expect(ids(const SearchFilters(query: 'candel')), ['p4']);
      expect(ids(const SearchFilters(query: 'keychian')), ['p6']);
      expect(ids(const SearchFilters(query: 'stonewear mug')), ['p5']);
    });

    test('partial words, joined words, store names and stop words', () {
      expect(ids(const SearchFilters(query: 'bouq')), containsAll(['p1', 'p3']));
      expect(ids(const SearchFilters(query: 'handcarved')), ['p2']);
      expect(ids(const SearchFilters(query: 'narra')), ['p2']);
      expect(ids(const SearchFilters(query: 'bouquet for mom')), isEmpty);
      expect(ids(const SearchFilters(query: 'a bouquet')), containsAll(['p1', 'p3']));
    });

    test('best match puts title matches before description matches', () {
      expect(ids(const SearchFilters(query: 'bouquet')), ['p1', 'p3']);
    });

    test('unrelated words find nothing', () {
      expect(ids(const SearchFilters(query: 'laptop')), isEmpty);
    });
  });

  group('Places', () {
    test('city names, addresses and nicknames', () {
      expect(Geo.resolveCity('Cebu City'), 'Cebu City');
      expect(Geo.resolveCity('cebu'), 'Cebu City');
      expect(Geo.resolveCity('12 Mango Avenue, Cebu City'), 'Cebu City');
      expect(Geo.resolveCity('QC'), 'Quezon City');
      expect(Geo.resolveCity('Las Pinas'), 'Las Piñas');
      expect(Geo.resolveCity('Philippines'), isNull);
    });

    test('distance between cities', () {
      final d = Geo.distanceKm(Geo.cities['Manila']!, Geo.cities['Cebu City']!);
      expect(d, inInclusiveRange(550, 600));
    });
  });

  group('Distance filter', () {
    test('only stores within the distance; unknown places are left out', () {
      expect(ids(const SearchFilters(nearCity: 'Cebu City', maxDistanceKm: 25)), ['p1', 'p3', 'p4']);
      expect(ids(const SearchFilters(nearCity: 'Cebu City', maxDistanceKm: 500)), ['p1', 'p3', 'p4', 'p5']);
    });

    test('a city with no distance does not filter', () {
      expect(ids(const SearchFilters(nearCity: 'Cebu City')), hasLength(6));
    });

    test('nearest first', () {
      expect(ids(const SearchFilters(nearCity: 'Baguio City', sort: SortBy.nearest)), ['p2', 'p1', 'p3', 'p4', 'p5', 'p6']);
    });
  });

  group('Delivered by', () {
    test('arrival = pack or make days + courier days', () {
      expect(estimateArrival(products[0], distanceKm: 3, today: today), DateTime(2026, 11, 19)); // 1 + 1
      expect(estimateArrival(products[1], distanceKm: 900, today: today), DateTime(2026, 11, 28)); // 6 + 5
      expect(estimateArrival(products[0], today: today), DateTime(2026, 11, 23)); // unknown distance: 1 + 5
      expect(estimateArrival(products[2], distanceKm: 3, custom: true, today: today), DateTime(2026, 11, 21)); // custom: 3 + 1
      expect(estimateArrival(_product('x', 'Sold out', 'cebu', stock: 0, leadDays: 0), today: today), isNull);
    });

    test('items that cannot arrive in time are left out', () {
      final by = DateTime(2026, 11, 20);
      expect(ids(SearchFilters(nearCity: 'Cebu City', neededBy: by)), ['p1', 'p3', 'p4']);
      expect(ids(SearchFilters(nearCity: 'Cebu City', neededBy: by, customOnly: true)), isEmpty);
      expect(ids(SearchFilters(neededBy: by)), isEmpty); // no city: nationwide courier time
    });
  });

  group('Recent searches (Firestore)', () {
    test('the saved filters include distance and needed-by date', () {
      final m = recentSearchFilters(SearchFilters(query: 'mug', nearCity: 'Cebu City', maxDistanceKm: 25, neededBy: DateTime(2026, 12, 3), customOnly: true));
      expect(m['nearCity'], 'Cebu City');
      expect(m['maxDistanceKm'], 25);
      expect(m['neededBy'], '2026-12-03');
      expect(m['customOnly'], true);
      expect(recentSearchFilters(const SearchFilters())['neededBy'], isNull);
    });
  });

  group('Other filters', () {
    test('price "any" includes items above the slider', () {
      expect(ids(const SearchFilters()), contains('p5'));
      expect(ids(const SearchFilters(maxPrice: 1000)), isNot(contains('p5')));
    });

    test('active filter count and reset', () {
      final f = SearchFilters(query: 'mug', maxPrice: 500, customOnly: true, nearCity: 'Cebu City', maxDistanceKm: 25, neededBy: today);
      expect(f.activeCount, 4);
      final r = f.reset();
      expect(r.activeCount, 0);
      expect(r.query, 'mug');
      expect(r.nearCity, 'Cebu City');
    });
  });

  group('Search screen', () {
    testWidgets('TC-SR01 a misspelled word still finds the item', (tester) async {
      await pumpApp(tester, auth: FakeAuthRepository(signedIn: true));
      await tester.tap(find.text('Flowers').first);
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).first, 'sunflwer boquet');
      await tester.pumpAndSettle();
      expect(find.text('Hand-tied Sunflower Bouquet'), findsWidgets);
      expect(find.text('Graduation Bouquet'), findsNothing);
    });

    testWidgets('TC-SR02 distance and delivery filters start from the profile city', (tester) async {
      await pumpApp(tester, auth: FakeAuthRepository(signedIn: true));
      await tester.tap(find.text('Flowers').first);
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Filters'));
      await tester.pumpAndSettle();
      expect(find.text('Cebu City'), findsOneWidget); // demo user's city
      expect(find.text('Any date'), findsOneWidget);
      // The flower shop is in Quezon City, far from Cebu.
      await tester.ensureVisible(find.text('Within 25 km'));
      await tester.tap(find.text('Within 25 km'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Show results'));
      await tester.tap(find.text('Show results'));
      await tester.pumpAndSettle();
      expect(find.text('No items found'), findsOneWidget);
      expect(find.text('1'), findsOneWidget); // filter badge
    });
  });
}

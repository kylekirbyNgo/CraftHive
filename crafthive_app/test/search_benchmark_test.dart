import 'dart:math';

import 'package:crafthive/data/models.dart';
import 'package:crafthive/data/search.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Milestone II: search must tolerate typos "while maintaining target
/// performance benchmarks across ten thousand catalog entries".
void main() {
  const vocab = [
    'crochet', 'tote', 'bag', 'bouquet', 'sunflower', 'candle', 'soy', 'calamansi', 'mug', 'stoneware', 'wooden', 'spoon',
    'carved', 'narra', 'acacia', 'keychain', 'planter', 'printed', 'shirt', 'custom', 'name', 'bracelet', 'beaded', 'graduation',
    'gift', 'handmade', 'small', 'large', 'blue', 'green', 'pastel', 'set', 'engraved', 'pottery', 'bowl', 'vase', 'scented',
    'sampaguita', 'barako', 'embroidered', 'pouch', 'wallet', 'coaster', 'tray', 'frame', 'lamp', 'dragon', 'flexible', 'resin',
  ];
  final rnd = Random(7);
  String words(int n) => [for (var i = 0; i < n; i++) vocab[rnd.nextInt(vocab.length)]].join(' ');

  final sellers = [
    for (var s = 0; s < 200; s++)
      Seller(
        id: 's$s', name: 'Store ${words(2)}', initials: 'ST', color: Colors.brown, location: s.isEven ? 'Cebu City' : 'Quezon City',
        isVerified: s % 3 == 0, rating: 4.5, sold: 10, replyTime: '', bio: '',
      ),
  ];
  final products = [
    for (var i = 0; i < 10000; i++)
      Product(
        id: 'p$i', title: words(3), sellerId: 's${i % 200}', categoryId: 'c${i % 8}', price: 100.0 + i % 1900,
        description: words(25), stock: i % 4, leadDays: 1 + i % 7, acceptsCustom: i.isEven, customOptions: [words(1), words(1)],
      ),
  ];

  test('fuzzy search with every filter on 10,000 listings', () {
    final queries = [
      const SearchFilters(query: 'boquet'),
      const SearchFilters(query: 'stonewear mug'),
      const SearchFilters(query: 'handmade crochet tote', sort: SortBy.rating),
      SearchFilters(query: 'candel', nearCity: 'Cebu City', maxDistanceKm: 25, neededBy: DateTime(2026, 11, 25), customOnly: true),
    ];
    searchProducts(products, sellers, queries.first); // warm-up
    // Best of 3, so other tests running at the same time don't fail this one.
    var best = double.infinity;
    var found = 0;
    for (var round = 0; round < 3; round++) {
      final watch = Stopwatch()..start();
      found = 0;
      for (final f in queries) {
        found += searchProducts(products, sellers, f, today: DateTime(2026, 11, 17)).length;
      }
      final perSearch = watch.elapsedMilliseconds / queries.length;
      if (perSearch < best) best = perSearch;
    }
    // ignore: avoid_print
    print('10,000 listings: ${best.toStringAsFixed(1)} ms per search ($found results)');
    expect(found, greaterThan(0));
    expect(best, lessThan(400), reason: 'search should stay fast while typing');
  });
}

import '../core/utils/fuzzy.dart';
import '../core/utils/geo.dart';
import 'models.dart';

/// Search: typo-tolerant text matching plus filters for category, price,
/// custom orders, stock, distance from the buyer and the date they need it by.

enum SortBy { relevance, priceLow, priceHigh, rating, nearest }

/// Highest value of the price slider; at this value price is not filtered.
const anyPrice = 2000.0;

class SearchFilters {
  const SearchFilters({
    this.query = '',
    this.categoryId,
    this.maxPrice = anyPrice,
    this.customOnly = false,
    this.inStockOnly = false,
    this.sort = SortBy.relevance,
    this.nearCity,
    this.maxDistanceKm,
    this.neededBy,
  });

  final String query;
  final String? categoryId;
  final double maxPrice;
  final bool customOnly;
  final bool inStockOnly;
  final SortBy sort;

  /// The buyer's city (a name from [Geo.cities]). Used for distance and delivery estimates.
  final String? nearCity;

  /// Only stores within this many km of [nearCity]; null = any distance.
  final double? maxDistanceKm;

  /// Only items expected to arrive on or before this day.
  final DateTime? neededBy;

  SearchFilters copyWith({
    String? query,
    String? categoryId,
    bool clearCategory = false,
    double? maxPrice,
    bool? customOnly,
    bool? inStockOnly,
    SortBy? sort,
    String? nearCity,
    bool clearNearCity = false,
    double? maxDistanceKm,
    bool clearDistance = false,
    DateTime? neededBy,
    bool clearNeededBy = false,
  }) =>
      SearchFilters(
        query: query ?? this.query,
        categoryId: clearCategory ? null : (categoryId ?? this.categoryId),
        maxPrice: maxPrice ?? this.maxPrice,
        customOnly: customOnly ?? this.customOnly,
        inStockOnly: inStockOnly ?? this.inStockOnly,
        sort: sort ?? this.sort,
        nearCity: clearNearCity ? null : (nearCity ?? this.nearCity),
        maxDistanceKm: clearDistance ? null : (maxDistanceKm ?? this.maxDistanceKm),
        neededBy: clearNeededBy ? null : (neededBy ?? this.neededBy),
      );

  /// Same filters with the sheet's options cleared (query, category, sort and city kept).
  SearchFilters reset() => SearchFilters(query: query, categoryId: categoryId, sort: sort, nearCity: nearCity);

  bool get filtersByDistance => nearCity != null && maxDistanceKm != null;

  int get activeCount =>
      (maxPrice < anyPrice ? 1 : 0) + (customOnly ? 1 : 0) + (inStockOnly ? 1 : 0) + (filtersByDistance ? 1 : 0) + (neededBy != null ? 1 : 0);
}

/// The filters saved with a recent search (Firestore users/{uid}/recentSearches,
/// "filters" field), so the Search and Browse Report can show the filters
/// applied, distance and needed-by date.
Map<String, Object?> recentSearchFilters(SearchFilters f) => {
      'categoryId': f.categoryId,
      'maxPrice': f.maxPrice,
      'customOnly': f.customOnly,
      'inStockOnly': f.inStockOnly,
      'sort': f.sort.name,
      'nearCity': f.nearCity,
      'maxDistanceKm': f.maxDistanceKm,
      'neededBy': f.neededBy == null
          ? null
          : '${f.neededBy!.year}-${f.neededBy!.month.toString().padLeft(2, '0')}-${f.neededBy!.day.toString().padLeft(2, '0')}',
    };

// ---------------------------------------------------------------------------
// Delivery estimate
// ---------------------------------------------------------------------------

/// Days to pack a ready-made item and hand it to the courier.
const packDays = 1;

/// Courier days by distance. Unknown distance assumes a nationwide shipment.
int shippingDays(double? km) {
  if (km == null) return 5;
  if (km < 25) return 1;
  if (km < 150) return 2;
  if (km < 500) return 3;
  return 5;
}

/// When the item should reach the buyer if ordered [today]; null when sold out.
/// Custom orders, and items not in stock, take the listing's days to make.
DateTime? estimateArrival(Product p, {double? distanceKm, bool custom = false, DateTime? today}) {
  final makeDays = p.leadDays > 0 ? p.leadDays : null;
  final prep = (custom || p.stock == 0) ? makeDays : packDays;
  if (prep == null) return null;
  final t = today ?? DateTime.now();
  return DateTime(t.year, t.month, t.day + prep + shippingDays(distanceKm));
}

/// Store position: its own coordinates, else the centre of its city.
LatLng? sellerCoords(Seller s) =>
    s.latitude != null && s.longitude != null ? (lat: s.latitude!, lng: s.longitude!) : Geo.cityCoords(s.location);

// ---------------------------------------------------------------------------
// Matching
// ---------------------------------------------------------------------------

/// How much a match in each part of a listing counts.
const _wTitle = 1.0, _wTag = 0.8, _wBody = 0.6;

/// A listing's words, prepared once and reused for every search (the catalog
/// is kept in memory, so typing does not re-split thousands of descriptions).
class _Doc {
  _Doc(Product p) {
    final t = Fuzzy.words(p.title);
    // "handcarved" should find "Hand-carved": also try neighbouring title words joined.
    title = {...t, for (var i = 0; i + 1 < t.length; i++) t[i] + t[i + 1]}.toList();
    titleText = t.join(' ');
    body = {...Fuzzy.words(p.description), for (final o in p.customOptions) ...Fuzzy.words(o)}.toList();
  }
  late final List<String> title;
  late final String titleText;
  late final List<String> body;
}

final _docs = Expando<_Doc>('search words');
_Doc _docFor(Product p) => _docs[p] ??= _Doc(p);

/// Remembers each word's score for one query word, so a word that appears in
/// many listings is compared only once per search.
class _Scorer {
  _Scorer(this.q);
  final String q;
  final _memo = <String, double>{};

  double best(List<String> words) {
    var best = 0.0;
    for (final w in words) {
      final s = _memo[w] ??= Fuzzy.wordScore(q, w);
      if (s > best) {
        best = s;
        if (best == 1) break;
      }
    }
    return best;
  }
}

double _score(List<_Scorer> scorers, String phrase, _Doc doc, List<String> tags) {
  if (scorers.isEmpty) return 1;
  var total = 0.0;
  for (final s in scorers) {
    var best = s.best(doc.title) * _wTitle;
    if (best < _wTag) best = _max(best, s.best(tags) * _wTag);
    if (best < _wBody) best = _max(best, s.best(doc.body) * _wBody);
    if (best == 0) return 0;
    total += best;
  }
  var score = total / scorers.length;
  if (phrase.length >= 3 && doc.titleText.contains(phrase)) score += 0.5;
  return score;
}

/// 0 when some query word matches nothing, else roughly 0..1.5 (higher = better).
double matchScore(List<String> queryWords, String normalizedQuery, {required String title, String seller = '', String category = '', String description = '', List<String> options = const []}) {
  final doc = _Doc(Product(id: '', title: title, sellerId: '', categoryId: '', price: 0, description: description, customOptions: options));
  return _score([for (final q in queryWords) _Scorer(q)], normalizedQuery, doc, [...Fuzzy.words(seller), ...Fuzzy.words(category)]);
}

double _max(double a, double b) => a > b ? a : b;

typedef _Hit = ({Product p, double score, double? km, int order});

List<Product> searchProducts(List<Product> all, List<Seller> sellers, SearchFilters f, {List<Category> categories = const [], DateTime? today}) {
  final words = Fuzzy.queryWords(f.query);
  final phrase = Fuzzy.normalize(f.query);
  final scorers = [for (final q in words) _Scorer(q)];
  final sellerById = {for (final s in sellers) s.id: s};
  final categoryName = {for (final c in categories) c.id: c.name};
  // Store and category words, split once per search.
  final tagCache = <String, List<String>>{};
  List<String> tagsFor(Product p, Seller? s) => tagCache['${p.sellerId}|${p.categoryId}'] ??=
      {...Fuzzy.words(s?.name ?? ''), ...Fuzzy.words(categoryName[p.categoryId] ?? '')}.toList();
  final here = f.nearCity == null ? null : Geo.cityCoords(f.nearCity!);
  final neededBy = f.neededBy == null ? null : DateTime(f.neededBy!.year, f.neededBy!.month, f.neededBy!.day);

  final hits = <_Hit>[];
  for (var i = 0; i < all.length; i++) {
    final p = all[i];
    // Published listings only; the user's own are included so they can find them too.
    if (p.status != ListingStatus.active) continue;
    if (f.categoryId != null && p.categoryId != f.categoryId) continue;
    if (f.maxPrice < anyPrice && p.price > f.maxPrice) continue;
    if (f.customOnly && !p.acceptsCustom) continue;
    if (f.inStockOnly && p.stock == 0) continue;

    final seller = sellerById[p.sellerId];
    final there = seller == null ? null : sellerCoords(seller);
    final km = here == null || there == null ? null : Geo.distanceKm(here, there);
    if (f.filtersByDistance && (km == null || km > f.maxDistanceKm!)) continue;

    if (neededBy != null) {
      final arrives = estimateArrival(p, distanceKm: km, custom: f.customOnly, today: today);
      if (arrives == null || arrives.isAfter(neededBy)) continue;
    }

    final score = scorers.isEmpty ? 1.0 : _score(scorers, phrase, _docFor(p), tagsFor(p, seller));
    if (score == 0) continue;
    hits.add((p: p, score: score, km: km, order: i));
  }

  int byOrder(_Hit a, _Hit b) => a.order.compareTo(b.order);
  switch (f.sort) {
    case SortBy.priceLow:
      hits.sort((a, b) => a.p.price != b.p.price ? a.p.price.compareTo(b.p.price) : byOrder(a, b));
    case SortBy.priceHigh:
      hits.sort((a, b) => a.p.price != b.p.price ? b.p.price.compareTo(a.p.price) : byOrder(a, b));
    case SortBy.rating:
      hits.sort((a, b) => a.p.rating != b.p.rating ? b.p.rating.compareTo(a.p.rating) : byOrder(a, b));
    case SortBy.nearest:
      hits.sort((a, b) {
        final ka = a.km ?? double.infinity, kb = b.km ?? double.infinity;
        return ka != kb ? ka.compareTo(kb) : byOrder(a, b);
      });
    case SortBy.relevance:
      if (words.isNotEmpty) hits.sort((a, b) => a.score != b.score ? b.score.compareTo(a.score) : byOrder(a, b));
  }
  return [for (final h in hits) h.p];
}

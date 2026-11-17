import 'dart:math' as math;

import 'fuzzy.dart';

typedef LatLng = ({double lat, double lng});

/// Distances for Search. Stores carry their own coordinates (store.latitude,
/// store.longitude); when a store has none, and for the buyer's "near" city,
/// the city centre from [cities] is used.
abstract final class Geo {
  /// Great-circle distance in kilometres (haversine).
  static double distanceKm(LatLng a, LatLng b) {
    const r = 6371.0;
    double rad(double d) => d * math.pi / 180;
    final dLat = rad(b.lat - a.lat);
    final dLng = rad(b.lng - a.lng);
    final h = math.pow(math.sin(dLat / 2), 2) + math.cos(rad(a.lat)) * math.cos(rad(b.lat)) * math.pow(math.sin(dLng / 2), 2);
    return 2 * r * math.asin(math.sqrt(h));
  }

  /// City centres in the Philippines (approximate).
  static const cities = <String, LatLng>{
    'Angeles City': (lat: 15.1450, lng: 120.5887),
    'Antipolo': (lat: 14.5860, lng: 121.1761),
    'Bacolod': (lat: 10.6765, lng: 122.9509),
    'Bacoor': (lat: 14.4590, lng: 120.9290),
    'Baguio City': (lat: 16.4023, lng: 120.5960),
    'Batangas City': (lat: 13.7565, lng: 121.0583),
    'Butuan': (lat: 8.9475, lng: 125.5406),
    'Cabanatuan': (lat: 15.4865, lng: 120.9667),
    'Cagayan de Oro': (lat: 8.4542, lng: 124.6319),
    'Cainta': (lat: 14.5786, lng: 121.1222),
    'Calamba': (lat: 14.2117, lng: 121.1653),
    'Caloocan': (lat: 14.6507, lng: 120.9668),
    'Cebu City': (lat: 10.3157, lng: 123.8854),
    'Cotabato City': (lat: 7.2236, lng: 124.2464),
    'Dagupan': (lat: 16.0433, lng: 120.3333),
    'Dasmariñas': (lat: 14.3294, lng: 120.9367),
    'Davao City': (lat: 7.1907, lng: 125.4553),
    'Dumaguete': (lat: 9.3068, lng: 123.3054),
    'General Santos': (lat: 6.1164, lng: 125.1716),
    'Iligan': (lat: 8.2280, lng: 124.2452),
    'Iloilo City': (lat: 10.7202, lng: 122.5621),
    'Imus': (lat: 14.4297, lng: 120.9367),
    'Laoag': (lat: 18.1960, lng: 120.5927),
    'Lapu-Lapu City': (lat: 10.3103, lng: 123.9494),
    'Las Piñas': (lat: 14.4445, lng: 120.9939),
    'Legazpi': (lat: 13.1391, lng: 123.7438),
    'Lipa': (lat: 13.9411, lng: 121.1631),
    'Lucena': (lat: 13.9373, lng: 121.6170),
    'Makati City': (lat: 14.5547, lng: 121.0244),
    'Malolos': (lat: 14.8527, lng: 120.8160),
    'Mandaluyong': (lat: 14.5794, lng: 121.0359),
    'Mandaue': (lat: 10.3236, lng: 123.9221),
    'Manila': (lat: 14.5995, lng: 120.9842),
    'Marikina': (lat: 14.6507, lng: 121.1029),
    'Muntinlupa': (lat: 14.4081, lng: 121.0415),
    'Naga': (lat: 13.6218, lng: 123.1948),
    'Olongapo': (lat: 14.8386, lng: 120.2842),
    'Parañaque': (lat: 14.4793, lng: 121.0198),
    'Pasay': (lat: 14.5378, lng: 121.0014),
    'Pasig City': (lat: 14.5764, lng: 121.0851),
    'Puerto Princesa': (lat: 9.7392, lng: 118.7353),
    'Quezon City': (lat: 14.6760, lng: 121.0437),
    'San Fernando, Pampanga': (lat: 15.0286, lng: 120.6898),
    'San Juan': (lat: 14.6019, lng: 121.0355),
    'Santa Rosa': (lat: 14.3122, lng: 121.1114),
    'Tacloban': (lat: 11.2443, lng: 125.0039),
    'Tagbilaran': (lat: 9.6500, lng: 123.8500),
    'Taguig': (lat: 14.5176, lng: 121.0509),
    'Tarlac City': (lat: 15.4802, lng: 120.5979),
    'Tuguegarao': (lat: 17.6132, lng: 121.7270),
    'Valenzuela': (lat: 14.7011, lng: 120.9830),
    'Vigan': (lat: 17.5747, lng: 120.3869),
    'Zamboanga City': (lat: 6.9214, lng: 122.0790),
  };

  static const _aliases = {
    'qc': 'Quezon City',
    'metro manila': 'Manila',
    'ncr': 'Manila',
    'cdo': 'Cagayan de Oro',
    'gensan': 'General Santos',
    'san fernando': 'San Fernando, Pampanga',
    'lapu lapu': 'Lapu-Lapu City',
  };

  static final Map<String, String> _byKey = {
    for (final name in cities.keys) _key(name): name,
    for (final e in _aliases.entries) e.key: e.value,
  };

  /// "Cebu City", "cebu", "City of Cebu" → "cebu".
  static String _key(String s) {
    var k = Fuzzy.normalize(s);
    if (k.startsWith('city of ')) k = k.substring(8);
    if (k.endsWith(' city')) k = k.substring(0, k.length - 5);
    return k.trim();
  }

  /// The known city named in [place] ("Cebu City", "12 Mango Ave, Cebu City"), or null.
  static String? resolveCity(String place) {
    if (place.trim().isEmpty) return null;
    final whole = _byKey[_key(place)];
    if (whole != null) return whole;
    final parts = place.split(',').reversed;
    for (final p in parts) {
      final hit = _byKey[_key(p)];
      if (hit != null) return hit;
    }
    return null;
  }

  static LatLng? cityCoords(String place) {
    final city = resolveCity(place);
    return city == null ? null : cities[city];
  }
}

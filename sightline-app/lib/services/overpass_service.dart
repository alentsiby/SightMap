import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// Queries OpenStreetMap for named places near a coordinate.
///
/// Primary: Overpass API for mountain peaks (natural=peak / natural=mountain)
/// Fallback: Nominatim reverse geocoding for any named place
///
/// Port of backend/overpass.js
class OverpassService {
  static const double _deg = pi / 180;

  /// Haversine distance between two lat/lng points in metres.
  static double _haversineDistance(
      double lat1, double lng1, double lat2, double lng2) {
    final dLat = (lat2 - lat1) * _deg;
    final dLng = (lng2 - lng1) * _deg;
    final a = sin(dLat / 2) * sin(dLat / 2) +
        cos(lat1 * _deg) * cos(lat2 * _deg) * sin(dLng / 2) * sin(dLng / 2);
    return 6371000 * 2 * atan2(sqrt(a), sqrt(1 - a));
  }

  /// Search for mountain peaks near [lat], [lng].
  /// Returns the closest peak, or null if none found.
  Future<Map<String, dynamic>?> getPeakNearby(double lat, double lng,
      {int radiusMetres = 600}) async {
    final radii = [radiusMetres, 2000];

    for (final radius in radii) {
      final query =
          '[out:json][timeout:10];(node["natural"="peak"](around:$radius,$lat,$lng);node["natural"="mountain"](around:$radius,$lat,$lng););out body;';

      try {
        final r = await http
            .get(
              Uri.parse(
                  'https://overpass-api.de/api/interpreter?data=${Uri.encodeComponent(query)}'),
              headers: {'User-Agent': 'SightLine/1.0'},
            )
            .timeout(const Duration(seconds: 10));

        if (r.statusCode != 200) continue;

        final elements = (jsonDecode(r.body)['elements'] as List?) ?? [];
        if (elements.isEmpty) {
          if (radius < 2000) {
            debugPrint(
                '[overpass] No peaks within ${radius}m, widening to 2000m...');
            continue;
          }
          break; // No peaks found even at max radius
        }

        // Sort by distance to hit point — return closest
        elements.sort((a, b) {
          final distA = _haversineDistance(
              lat, lng, (a['lat'] as num).toDouble(), (a['lon'] as num).toDouble());
          final distB = _haversineDistance(
              lat, lng, (b['lat'] as num).toDouble(), (b['lon'] as num).toDouble());
          return distA.compareTo(distB);
        });

        final closest = elements[0];
        final tags = closest['tags'] as Map<String, dynamic>? ?? {};
        final distM = _haversineDistance(
                lat, lng, (closest['lat'] as num).toDouble(), (closest['lon'] as num).toDouble())
            .toStringAsFixed(0);
        debugPrint(
            '[overpass] Found ${elements.length} peaks within ${radius}m, '
            'closest: "${tags['name'] ?? 'Unnamed'}" (${distM}m away)');

        return {
          'name': tags['name'] ?? tags['name:en'] ?? 'Unknown peak',
          'elevation': tags['ele'] != null ? int.tryParse(tags['ele'].toString()) : null,
          'osm_id': closest['id'],
        };
      } catch (e) {
        debugPrint('[overpass] Peak lookup failed (radius=${radius}m): $e');
        return null;
      }
    }

    // No peaks found — fall back to Nominatim reverse geocoding
    debugPrint('[places] No peak found, trying Nominatim reverse geocode...');
    return _reverseGeocode(lat, lng);
  }

  /// Nominatim reverse geocode fallback — finds ANY named place.
  Future<Map<String, dynamic>?> _reverseGeocode(double lat, double lng) async {
    try {
      final r = await http.get(
        Uri.parse(
            'https://nominatim.openstreetmap.org/reverse?format=json&lat=$lat&lon=$lng&zoom=16&addressdetails=1'),
        headers: {'User-Agent': 'SightLine/1.0'},
      ).timeout(const Duration(seconds: 8));

      if (r.statusCode != 200) return null;

      final data = jsonDecode(r.body);
      if (data['error'] != null) return null;

      final address = data['address'] as Map<String, dynamic>? ?? {};
      final name = data['name'] ??
          address['village'] ??
          address['town'] ??
          address['hamlet'] ??
          address['suburb'] ??
          address['city'] ??
          (data['display_name'] as String?)?.split(',').first;

      if (name == null) return null;

      final type = data['type'] ?? data['category'] ?? 'place';
      debugPrint('[nominatim] Found place: "$name" (type: $type)');

      return {
        'name': name,
        'type': type,
        'elevation': null,
        'osm_id': data['osm_id'],
      };
    } catch (e) {
      debugPrint('[nominatim] Reverse geocode failed: $e');
      return null;
    }
  }
}

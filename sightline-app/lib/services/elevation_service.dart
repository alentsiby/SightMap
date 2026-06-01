import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// Fetches terrain elevation data from free DEM APIs.
///
/// Primary:  OpenTopoData (SRTM 30m) — free, no key, global coverage
/// Fallback: Open-Elevation API — free, no key
///
/// Port of backend/dem.js
class ElevationService {
  static const Duration _timeout = Duration(seconds: 15);

  /// Batch-fetch elevations for a list of lat/lng points.
  ///
  /// Returns a list of elevations in metres (null if lookup failed for that point).
  /// OpenTopoData accepts up to 100 points per request.
  Future<List<double?>> getElevationsBatch(
      List<({double lat, double lng})> points) async {
    if (points.isEmpty) return [];

    final locations =
        points.map((p) => '${p.lat.toStringAsFixed(6)},${p.lng.toStringAsFixed(6)}').join('|');

    // Primary: OpenTopoData (most reliable free option)
    try {
      final r = await http
          .get(
            Uri.parse(
                'https://api.opentopodata.org/v1/srtm30m?locations=$locations'),
          )
          .timeout(_timeout);

      if (r.statusCode == 200) {
        final data = jsonDecode(r.body);
        return (data['results'] as List)
            .map<double?>((result) => (result['elevation'] as num?)?.toDouble())
            .toList();
      }

      // Rate-limited (429): wait and retry once
      if (r.statusCode == 429) {
        debugPrint(
            '[elevation] OpenTopoData rate-limited, waiting 1.5s and retrying...');
        await Future.delayed(const Duration(milliseconds: 1500));

        final retry = await http
            .get(
              Uri.parse(
                  'https://api.opentopodata.org/v1/srtm30m?locations=$locations'),
            )
            .timeout(_timeout);

        if (retry.statusCode == 200) {
          final data = jsonDecode(retry.body);
          return (data['results'] as List)
              .map<double?>(
                  (result) => (result['elevation'] as num?)?.toDouble())
              .toList();
        }
      }

      debugPrint('[elevation] OpenTopoData returned ${r.statusCode}');
    } catch (e) {
      debugPrint('[elevation] OpenTopoData failed: $e');
    }

    // Fallback: Open-Elevation
    try {
      final r = await http
          .get(
            Uri.parse(
                'https://api.open-elevation.com/api/v1/lookup?locations=$locations'),
          )
          .timeout(_timeout);

      if (r.statusCode == 200) {
        final data = jsonDecode(r.body);
        return (data['results'] as List)
            .map<double?>((result) => (result['elevation'] as num?)?.toDouble())
            .toList();
      }
    } catch (e) {
      debugPrint('[elevation] Both elevation APIs failed: $e');
    }

    // Both failed — return nulls
    return List.filled(points.length, null);
  }
}

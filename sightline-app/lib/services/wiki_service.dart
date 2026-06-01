import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// Fetches Wikipedia summary data for identified peaks/places.
///
/// Uses the Wikipedia REST API — free, no key, returns clean JSON.
///
/// Port of backend/wiki.js
class WikiService {
  /// Fetch summary, thumbnail, and URL for a named peak/place.
  ///
  /// Returns null if the lookup fails or no article exists.
  Future<Map<String, dynamic>?> getSummary(String peakName) async {
    try {
      final encoded =
          Uri.encodeComponent(peakName.replaceAll(' ', '_'));
      final r = await http.get(
        Uri.parse(
            'https://en.wikipedia.org/api/rest_v1/page/summary/$encoded'),
      ).timeout(const Duration(seconds: 5));

      if (r.statusCode != 200) return null;

      final data = jsonDecode(r.body);
      return {
        'extract': data['extract'],
        'thumbnail': data['thumbnail']?['source'],
        'url': data['content_urls']?['mobile']?['page'],
      };
    } catch (e) {
      debugPrint('[wiki] Wikipedia lookup failed for "$peakName": $e');
      return null;
    }
  }
}

import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/sight_vector.dart';
import '../models/sighting_result.dart';

/// HTTP client for the SightLine backend.
///
/// Sends the 5-variable sensor vector to the backend and receives
/// the identified peak with Wikipedia enrichment.
class ApiService {
  // Laptop's IP on phone hotspot — phone can reach this
  static const String _base =
      'http://localhost:3000'; // static const String _base = 'https://sightline-api.duckdns.org'; // Production

  /// Send a raycast request to the backend.
  ///
  /// The [onProgress] callback receives status messages for progressive
  /// timeout feedback (e.g., "Still working…" after 5s).
  Future<SightingResult> raycast(
    SightVector vector, {
    void Function(String status)? onProgress,
  }) async {
    // Progressive timeout feedback
    final stopwatch = Stopwatch()..start();
    Timer? progressTimer;

    if (onProgress != null) {
      progressTimer = Timer.periodic(const Duration(seconds: 3), (_) {
        final elapsed = stopwatch.elapsed.inSeconds;
        if (elapsed > 15) {
          onProgress('📡 Poor signal — this may take longer…');
        } else if (elapsed > 6) {
          onProgress('⏳ Still working, signal may be slow…');
        }
      });
    }

    try {
      final response = await http
          .post(
            Uri.parse('$_base/raycast'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(vector.toJson()),
          )
          .timeout(const Duration(seconds: 30));

      progressTimer?.cancel();

      if (response.statusCode != 200) {
        throw Exception('Server error ${response.statusCode}');
      }
      return SightingResult.fromJson(jsonDecode(response.body));
    } on TimeoutException {
      progressTimer?.cancel();
      throw Exception('Request timed out — move to an area with better signal');
    } catch (e) {
      progressTimer?.cancel();
      rethrow;
    }
  }
}

import 'dart:math';
import 'package:flutter/foundation.dart';
import '../models/sight_vector.dart';
import '../models/sighting_result.dart';
import 'elevation_service.dart';
import 'overpass_service.dart';
import 'wiki_service.dart';

/// On-device ray-marching engine.
///
/// Replaces the Node.js backend entirely — all computation happens on the phone.
/// Casts a mathematical ray from the user's GPS position along their line of
/// sight and finds where it intersects the Earth's terrain.
///
/// Port of backend/raycast.js
class RaycastService {
  // ─── Constants ──────────────────────────────────────────────────────────
  static const int _stepMetres = 25; // Resolution: one sample every 25m
  static const int _maxSteps = 3200; // 80 km max range (3200 × 25m)
  static const int _minDistMetres = 200; // Ignore hits closer than this
  static const double _earthRadius = 6371000; // Mean Earth radius in metres
  static const double _deg = pi / 180; // Degrees → radians
  static const int _chunkSize = 100; // Elevation API batch size

  final ElevationService _elevation = ElevationService();
  final OverpassService _overpass = OverpassService();
  final WikiService _wiki = WikiService();

  // ─── Magnetic Declination (WMM 2025 Dipole Approximation) ─────────────
  /// Convert magnetic compass heading to True North heading.
  ///
  /// Uses a dipole approximation of the World Magnetic Model (WMM 2025).
  /// This gives ~1-2° accuracy which is sufficient given phone compass
  /// error is typically 5-15°.
  ///
  /// WMM 2025 first-order Gauss coefficients:
  ///   g₁₀ = -29351.8 nT, g₁₁ = -1410.8 nT, h₁₁ = 4590.2 nT
  double _applyDeclination(double azimuthMag, double lat, double lng) {
    // WMM 2025 dipole coefficients
    const double g10 = -29351.8;
    const double g11 = -1410.8;
    const double h11 = 4590.2;

    // Magnetic pole location from dipole coefficients
    final double thetaP = atan2(sqrt(g11 * g11 + h11 * h11), g10.abs());
    final double phiP = atan2(h11, g11);

    // Convert user position to radians (colatitude)
    final double theta = (90.0 - lat) * _deg; // colatitude
    final double phi = lng * _deg;

    // Dipole declination formula
    final double sinD =
        sin(phiP - phi) * sin(thetaP) / sin(theta).clamp(0.001, double.infinity);
    final double cosD =
        (sin(thetaP) * cos(theta) * cos(phiP - phi) -
                cos(thetaP) * sin(theta)) /
            sin(theta).clamp(0.001, double.infinity);

    final double declination = atan2(sinD, cosD) / _deg;
    debugPrint(
        '[raycast] Magnetic declination at ($lat, $lng): ${declination.toStringAsFixed(2)}°');

    return (azimuthMag + declination + 360) % 360;
  }

  // ─── Haversine Step ──────────────────────────────────────────────────────
  /// Move [distance] metres along [bearing] degrees from (lat, lng).
  ({double lat, double lng}) _haversineStep(
      double lat, double lng, double bearing, double distance) {
    final b = bearing * _deg;
    final d = distance / _earthRadius;
    final lat1 = lat * _deg;
    final lng1 = lng * _deg;

    final lat2 = asin(
        sin(lat1) * cos(d) + cos(lat1) * sin(d) * cos(b));
    final lng2 = lng1 +
        atan2(sin(b) * sin(d) * cos(lat1),
            cos(d) - sin(lat1) * sin(lat2));

    return (
      lat: lat2 / _deg,
      lng: ((lng2 / _deg) + 540) % 360 - 180,
    );
  }

  // ─── Atmospheric Refraction ────────────────────────────────────────────
  /// Standard surveying atmospheric refraction correction.
  /// Light bends slightly downward over long distances, making distant
  /// objects appear higher than they are.
  double _refractionCorrection(double pitchDeg) {
    if (pitchDeg <= 0) return 0;
    return 0.87 /
        tan((pitchDeg + 7.31 / (pitchDeg + 4.4)) * _deg) /
        3600;
  }

  // ─── Main Raycast ──────────────────────────────────────────────────────
  /// Cast a ray from the user's position and find the terrain intersection.
  ///
  /// [onProgress] receives status messages for UI feedback.
  Future<SightingResult> raycast(
    SightVector vector, {
    void Function(String status)? onProgress,
  }) async {
    final lat = vector.lat;
    final lng = vector.lng;
    final alt = vector.alt;
    final azimuth = vector.azimuth;
    final pitch = vector.pitch;

    debugPrint('[raycast] Input: lat=$lat, lng=$lng, alt=$alt, '
        'azimuth=$azimuth, pitch=$pitch');

    // 1. Correct azimuth for magnetic declination
    final trueAzimuth = _applyDeclination(azimuth, lat, lng);
    debugPrint('[raycast] Magnetic azimuth ${azimuth.toStringAsFixed(1)}° '
        '→ True azimuth ${trueAzimuth.toStringAsFixed(2)}°');

    // 2. Apply atmospheric refraction to pitch
    final correctedPitch = pitch - _refractionCorrection(pitch);
    final pitchRad = correctedPitch * _deg;

    // 3. Compute theoretical horizon distance
    final horizonKm = 3.57 * sqrt(max(alt, 1));
    final maxSteps = min(
        (horizonKm * 1000 / _stepMetres).floor(), _maxSteps);
    final minStep = (_minDistMetres / _stepMetres).ceil();
    debugPrint('[raycast] Horizon: ${horizonKm.toStringAsFixed(1)} km, '
        'max steps: $maxSteps, skip first $minStep steps');

    // 4. Pre-compute ALL ray positions (pure math, instant)
    final points = <({double lat, double lng, double rayAlt, int step})>[];
    var curLat = lat;
    var curLng = lng;

    for (var i = 1; i <= maxSteps; i++) {
      final next = _haversineStep(curLat, curLng, trueAzimuth, _stepMetres.toDouble());
      curLat = next.lat;
      curLng = next.lng;
      final dist = (i * _stepMetres).toDouble();

      // Earth curvature: surface curves AWAY from straight-line ray
      final curvatureDrop = (dist * dist) / (2 * _earthRadius);
      final rayAlt = alt + dist * tan(pitchRad) + curvatureDrop;

      points.add((lat: curLat, lng: curLng, rayAlt: rayAlt, step: i));
    }

    // 5. Batch fetch elevations in chunks of 100 (API limit)
    final totalChunks = (points.length / _chunkSize).ceil();
    debugPrint('[raycast] Fetching elevations for ${points.length} points '
        'in $totalChunks chunks...');

    for (var chunkIdx = 0; chunkIdx < totalChunks; chunkIdx++) {
      final start = chunkIdx * _chunkSize;
      final end = min(start + _chunkSize, points.length);
      final chunk = points.sublist(start, end);

      // Rate-limit: wait between chunks (skip delay before first)
      if (chunkIdx > 0) {
        await Future.delayed(const Duration(milliseconds: 1100));
      }

      // Progress feedback
      if (onProgress != null && chunkIdx > 0) {
        final pct = ((chunkIdx / totalChunks) * 100).round();
        onProgress('🔍 Scanning terrain… $pct%');
      }

      final elevs = await _elevation.getElevationsBatch(
          chunk.map((p) => (lat: p.lat, lng: p.lng)).toList());

      final validCount = elevs.where((e) => e != null).length;
      debugPrint('[raycast] Chunk ${chunkIdx + 1}/$totalChunks: '
          'got $validCount/${chunk.length} elevations');

      // 6. Check this chunk for intersection (early exit)
      for (var j = 0; j < chunk.length; j++) {
        final globalIdx = start + j;
        final elev = elevs[j];
        if (elev == null) continue;

        // Skip near-range hits (flat terrain noise)
        if (globalIdx + 1 < minStep) continue;

        if (points[globalIdx].rayAlt <= elev) {
          final hitLat = points[globalIdx].lat;
          final hitLng = points[globalIdx].lng;
          final distKm =
              ((globalIdx + 1) * _stepMetres / 1000).toStringAsFixed(2);

          debugPrint('[raycast] HIT at step ${globalIdx + 1}: '
              'lat=${hitLat.toStringAsFixed(5)}, '
              'lng=${hitLng.toStringAsFixed(5)}, '
              'dist=$distKm km, terrain=${elev}m, '
              'ray=${points[globalIdx].rayAlt.toStringAsFixed(1)}m');

          onProgress?.call('📍 Found terrain hit — identifying…');

          // 7. Enrich with OSM peak name and Wikipedia description
          final peak = await _overpass.getPeakNearby(hitLat, hitLng);
          final wiki = peak != null
              ? await _wiki.getSummary(peak['name'] as String)
              : null;

          return SightingResult(
            hit: true,
            lat: hitLat,
            lng: hitLng,
            elevation: elev,
            distanceKm: double.tryParse(distKm),
            peak: peak != null
                ? PeakInfo(
                    name: peak['name'] as String,
                    elevation: peak['elevation'] as int?,
                    osmId: peak['osm_id'] as int?,
                  )
                : null,
            wiki: wiki != null
                ? WikiInfo(
                    extract: wiki['extract'] as String? ?? '',
                    thumbnail: wiki['thumbnail'] as String?,
                    url: wiki['url'] as String?,
                  )
                : null,
          );
        }
      }
    }

    // Ray never hit terrain — user is aiming too high
    debugPrint('[raycast] No intersection found — ray missed all terrain');
    return const SightingResult(
      hit: false,
      reason: 'aim_lower',
    );
  }
}

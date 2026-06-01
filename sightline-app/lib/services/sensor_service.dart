import 'dart:async';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'package:flutter_compass/flutter_compass.dart';
import '../models/sight_vector.dart';

/// Manages phone sensor streams (GPS, compass, accelerometer) and provides
/// a fused, filtered snapshot of the user's position and orientation.
///
/// Uses a complementary filter (α = 0.92) to merge:
/// - Accelerometer (stable but noisy) → pitch angle
/// - Compass/magnetometer → azimuth (with circular smoothing)
///
/// The [snapshot] method freezes all values at the moment the user taps Lock.
class SensorService {
  // Complementary filter coefficients:
  // Higher α = smoother but slower to respond
  static const double _alphaPitch = 0.96;
  static const double _alphaAzimuth = 0.92; // Slightly more responsive for heading

  double _pitch = 0.0;
  double _azimuth = 0.0;
  double _rawAzimuth = 0.0; // Unfiltered for debug display
  double _rawPitch = 0.0;   // Unfiltered pitch for debug
  double _azimuthOffset = 0.0; // Manual correction for metal interference
  double _compassAccuracy = -1; // Magnetometer accuracy (-1 = unknown)
  bool _azimuthInitialized = false;
  Position? _position;

  double get pitch => _pitch;
  double get azimuth => _azimuth;
  double get rawAzimuth => _rawAzimuth;
  double get rawPitch => _rawPitch;
  double get azimuthOffset => _azimuthOffset;
  double get compassAccuracy => _compassAccuracy;
  Position? get position => _position;

  final _pitchController = StreamController<double>.broadcast();
  final _azimuthController = StreamController<double>.broadcast();

  Stream<double> get pitchStream => _pitchController.stream;
  Stream<double> get azimuthStream => _azimuthController.stream;

  StreamSubscription? _accelSub;
  StreamSubscription? _compassSub;
  StreamSubscription? _gpsSub;

  /// Set manual azimuth offset (±15°) for compass drift near metal objects
  void setAzimuthOffset(double offset) {
    _azimuthOffset = offset.clamp(-15.0, 15.0);
  }

  /// Start all sensor streams. Call once after permissions are granted.
  void start() {
    // Pitch from accelerometer gravity vector
    // Phone in portrait: y=9.8 when vertical, z changes as you tilt up/down
    _accelSub = accelerometerEventStream().listen((e) {
      _rawPitch = _calcPitch(e.x, e.y, e.z);
      _pitch = _alphaPitch * _pitch + (1 - _alphaPitch) * _rawPitch;
      _pitchController.add(_pitch);
    });

    // Azimuth from compass with circular complementary filter
    _compassSub = FlutterCompass.events?.listen((e) {
      if (e.heading != null) {
        _rawAzimuth = e.heading!;

        // Track compass accuracy (lower = better, -1 = unknown)
        if (e.accuracy != null) {
          _compassAccuracy = e.accuracy!;
        }

        if (!_azimuthInitialized) {
          // First reading: accept as-is (no previous value to blend with)
          _azimuth = _rawAzimuth;
          _azimuthInitialized = true;
        } else {
          // Circular complementary filter:
          // Normal linear blending breaks at the 0°/360° boundary
          // (e.g., blending 350° and 10° gives 180° instead of 0°).
          // We compute the shortest angular difference and blend that.
          double diff = _rawAzimuth - _azimuth;

          // Normalize diff to [-180, +180] range
          if (diff > 180) diff -= 360;
          if (diff < -180) diff += 360;

          _azimuth = (_azimuth + (1 - _alphaAzimuth) * diff + 360) % 360;
        }

        _azimuthController.add(_azimuth);
      }
    });

    // High-precision GPS stream
    _gpsSub = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.best,
      ),
    ).listen((pos) => _position = pos);
  }

  /// Calculate pitch angle from accelerometer XYZ values.
  /// Returns degrees above/below horizontal.
  ///
  /// In portrait mode (phone held upright):
  ///   - y ≈ 9.8 when vertical (camera horizontal, pitch = 0°)
  ///   - As phone tilts backward (camera points up), y decreases, z changes
  ///   - atan2(-z, y) gives the elevation angle above horizontal
  ///
  /// Previous bug: was using atan2(-x, ...) which measures ROLL (left-right
  /// tilt), not PITCH (up-down tilt). x stays ~0 when tilting up/down,
  /// so pitch was always ~0° causing the ray to go horizontal.
  double _calcPitch(double x, double y, double z) {
    return atan2(-z, y) * 180 / pi;
  }

  /// Capture a frozen snapshot of all sensor values at this exact moment.
  /// Returns null if GPS position hasn't been acquired yet.
  SightVector? snapshot() {
    if (_position == null) return null;

    final vec = SightVector(
      lat: _position!.latitude,
      lng: _position!.longitude,
      alt: _position!.altitude,
      azimuth: (_azimuth + _azimuthOffset + 360) % 360,
      pitch: _pitch,
    );

    // Debug log — helps diagnose direction issues in the field
    debugPrint('[SensorService] SNAPSHOT: '
        'lat=${vec.lat.toStringAsFixed(6)}, '
        'lng=${vec.lng.toStringAsFixed(6)}, '
        'alt=${vec.alt.toStringAsFixed(1)}m, '
        'azimuth=${vec.azimuth.toStringAsFixed(1)}° '
        '(raw=${_rawAzimuth.toStringAsFixed(1)}°, offset=${_azimuthOffset.toStringAsFixed(1)}°), '
        'pitch=${vec.pitch.toStringAsFixed(1)}° (raw=${_rawPitch.toStringAsFixed(1)}°), '
        'gpsAccuracy=±${_position!.accuracy.toStringAsFixed(0)}m, '
        'compassAccuracy=${_compassAccuracy.toStringAsFixed(0)}');

    return vec;
  }

  void dispose() {
    _accelSub?.cancel();
    _compassSub?.cancel();
    _gpsSub?.cancel();
    _pitchController.close();
    _azimuthController.close();
  }
}

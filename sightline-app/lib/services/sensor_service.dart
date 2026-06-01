import 'dart:async';
import 'dart:math';
import 'package:geolocator/geolocator.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'package:flutter_compass/flutter_compass.dart';
import '../models/sight_vector.dart';

/// Manages phone sensor streams (GPS, compass, accelerometer) and provides
/// a fused, filtered snapshot of the user's position and orientation.
///
/// Uses a complementary filter (α = 0.96) to merge:
/// - Accelerometer (stable but noisy) → pitch angle
/// - Compass/magnetometer (handled internally by flutter_compass) → azimuth
///
/// The [snapshot] method freezes all values at the moment the user taps Lock.
class SensorService {
  // Complementary filter coefficient:
  // 96% previous value (smooth) + 4% new reading (responsive)
  static const double _alpha = 0.96;

  double _pitch = 0.0;
  double _azimuth = 0.0;
  double _azimuthOffset = 0.0; // Manual correction for metal interference
  Position? _position;

  double get pitch => _pitch;
  double get azimuth => _azimuth;
  double get azimuthOffset => _azimuthOffset;
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
    _accelSub = accelerometerEventStream().listen((e) {
      final rawPitch = _calcPitch(e.x, e.y, e.z);
      _pitch = _alpha * _pitch + (1 - _alpha) * rawPitch;
      _pitchController.add(_pitch);
    });

    // Azimuth from compass (flutter_compass handles sensor fusion internally)
    _compassSub = FlutterCompass.events?.listen((e) {
      if (e.heading != null) {
        _azimuth = e.heading!;
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
  double _calcPitch(double x, double y, double z) {
    return atan2(-x, sqrt(y * y + z * z)) * 180 / pi;
  }

  /// Capture a frozen snapshot of all sensor values at this exact moment.
  /// Returns null if GPS position hasn't been acquired yet.
  SightVector? snapshot() {
    if (_position == null) return null;
    return SightVector(
      lat: _position!.latitude,
      lng: _position!.longitude,
      alt: _position!.altitude,
      azimuth: (_azimuth + _azimuthOffset + 360) % 360,
      pitch: _pitch,
    );
  }

  void dispose() {
    _accelSub?.cancel();
    _compassSub?.cancel();
    _gpsSub?.cancel();
    _pitchController.close();
    _azimuthController.close();
  }
}

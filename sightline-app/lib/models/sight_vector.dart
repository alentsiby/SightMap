/// Represents the 5-variable sensor vector captured at the moment
/// the user taps "Lock" in the viewfinder.
///
/// All values come directly from phone sensors:
/// - [lat], [lng], [alt] from GPS
/// - [azimuth] from magnetometer (raw magnetic, corrected server-side)
/// - [pitch] from accelerometer
class SightVector {
  final double lat;
  final double lng;
  final double alt;
  final double azimuth;
  final double pitch;

  const SightVector({
    required this.lat,
    required this.lng,
    required this.alt,
    required this.azimuth,
    required this.pitch,
  });

  Map<String, dynamic> toJson() => {
        'lat': lat,
        'lng': lng,
        'alt': alt,
        'azimuth': azimuth,
        'pitch': pitch,
      };

  @override
  String toString() =>
      'SightVector(lat: ${lat.toStringAsFixed(5)}, lng: ${lng.toStringAsFixed(5)}, '
      'alt: ${alt.toStringAsFixed(1)}, azimuth: ${azimuth.toStringAsFixed(1)}, '
      'pitch: ${pitch.toStringAsFixed(1)})';
}

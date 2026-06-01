/// Information about a mountain peak from OpenStreetMap.
class PeakInfo {
  final String name;
  final int? elevation;
  final int? osmId;

  const PeakInfo({required this.name, this.elevation, this.osmId});

  factory PeakInfo.fromJson(Map<String, dynamic> j) => PeakInfo(
        name: j['name'] ?? 'Unknown peak',
        elevation: j['elevation'],
        osmId: j['osm_id'],
      );
}

/// Wikipedia summary data for an identified peak.
class WikiInfo {
  final String extract;
  final String? thumbnail;
  final String? url;

  const WikiInfo({required this.extract, this.thumbnail, this.url});

  factory WikiInfo.fromJson(Map<String, dynamic> j) => WikiInfo(
        extract: j['extract'] ?? '',
        thumbnail: j['thumbnail'],
        url: j['url'],
      );
}

/// Result of a raycast operation — either a terrain hit with peak info
/// or a miss with a reason string.
class SightingResult {
  final bool hit;
  final double? lat;
  final double? lng;
  final double? elevation;
  final double? distanceKm;
  final PeakInfo? peak;
  final WikiInfo? wiki;
  final String? reason;

  const SightingResult({
    required this.hit,
    this.lat,
    this.lng,
    this.elevation,
    this.distanceKm,
    this.peak,
    this.wiki,
    this.reason,
  });

  factory SightingResult.fromJson(Map<String, dynamic> j) => SightingResult(
        hit: j['hit'] ?? false,
        lat: (j['lat'] as num?)?.toDouble(),
        lng: (j['lng'] as num?)?.toDouble(),
        elevation: (j['elevation'] as num?)?.toDouble(),
        distanceKm: double.tryParse(j['distance_km']?.toString() ?? ''),
        peak: j['peak'] != null ? PeakInfo.fromJson(j['peak']) : null,
        wiki: j['wiki'] != null ? WikiInfo.fromJson(j['wiki']) : null,
        reason: j['reason'],
      );
}

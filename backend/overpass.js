const axios = require('axios');

const DEG = Math.PI / 180;

/**
 * Haversine distance between two lat/lng points in metres.
 * Used to sort Overpass results by proximity to the ray hit point.
 */
function haversineDistance(lat1, lng1, lat2, lng2) {
  const dLat = (lat2 - lat1) * DEG;
  const dLng = (lng2 - lng1) * DEG;
  const a =
    Math.sin(dLat / 2) ** 2 +
    Math.cos(lat1 * DEG) * Math.cos(lat2 * DEG) * Math.sin(dLng / 2) ** 2;
  return 6371000 * 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
}

/**
 * Query OpenStreetMap Overpass API for mountain peaks near a coordinate.
 * No API key required — free forever.
 *
 * Searches for nodes tagged natural=peak or natural=mountain
 * within the specified radius of the hit point.
 * Results are sorted by distance — the CLOSEST peak is returned.
 *
 * Uses GET with query parameter (more reliable than POST across regions).
 *
 * @param {number} lat - Latitude of ray-terrain intersection
 * @param {number} lng - Longitude of ray-terrain intersection
 * @param {number} radiusMetres - Search radius (default 600m, widens to 2000m on retry)
 * @returns {Promise<{name: string, elevation: number|null, osm_id: number}|null>}
 */
async function getPeakNearby(lat, lng, radiusMetres = 600) {
  // Try with the default radius first, then widen if nothing found
  const radii = [radiusMetres, 2000];

  for (const radius of radii) {
    const query = `[out:json][timeout:10];(node["natural"="peak"](around:${radius},${lat},${lng});node["natural"="mountain"](around:${radius},${lat},${lng}););out body;`;

    try {
      const r = await axios.get(
        `https://overpass-api.de/api/interpreter?data=${encodeURIComponent(query)}`,
        {
          headers: { 'User-Agent': 'SightLine/1.0' },
          timeout: 10000,
        }
      );

      const elements = r.data.elements;
      if (!elements.length) {
        if (radius < 2000) {
          console.log(`[overpass] No peaks within ${radius}m, widening to 2000m...`);
          continue;
        }
        return null;
      }

      // Sort by distance to the hit point and return the closest
      elements.sort((a, b) => {
        const distA = haversineDistance(lat, lng, a.lat, a.lon);
        const distB = haversineDistance(lat, lng, b.lat, b.lon);
        return distA - distB;
      });

      const closest = elements[0];
      const distM = haversineDistance(lat, lng, closest.lat, closest.lon).toFixed(0);
      console.log(`[overpass] Found ${elements.length} peaks within ${radius}m, closest: "${closest.tags?.name || 'Unnamed'}" (OSM ${closest.id}, ${distM}m away)`);
      return {
        name: closest.tags?.name || closest.tags?.['name:en'] || 'Unknown peak',
        elevation: closest.tags?.ele ? parseInt(closest.tags.ele) : null,
        osm_id: closest.id,
      };
    } catch (err) {
      console.error(`[overpass] Peak lookup failed (radius=${radius}m):`, err.message);
      return null;
    }
  }

  return null;
}

// ─── Nominatim Reverse Geocode (fallback) ────────────────────────────────────
/**
 * When no peak is found via Overpass, fall back to Nominatim reverse geocoding
 * to identify ANY named place (village, town, landmark, building, etc.).
 * Free, no API key — just needs a User-Agent header.
 *
 * @param {number} lat
 * @param {number} lng
 * @returns {Promise<{name: string, type: string, elevation: number|null}|null>}
 */
async function reverseGeocode(lat, lng) {
  try {
    const r = await axios.get('https://nominatim.openstreetmap.org/reverse', {
      params: {
        format: 'json',
        lat,
        lon: lng,
        zoom: 16,       // ~village/neighbourhood level detail
        addressdetails: 1,
      },
      headers: { 'User-Agent': 'SightLine/1.0' },
      timeout: 8000,
    });

    if (!r.data || r.data.error) {
      console.log('[nominatim] No result for coordinates');
      return null;
    }

    const name = r.data.name
      || r.data.address?.village
      || r.data.address?.town
      || r.data.address?.hamlet
      || r.data.address?.suburb
      || r.data.address?.city
      || r.data.display_name?.split(',')[0]
      || null;

    if (!name) return null;

    const type = r.data.type || r.data.category || 'place';
    console.log(`[nominatim] Found place: "${name}" (type: ${type})`);

    return {
      name,
      type,
      elevation: null,
      osm_id: r.data.osm_id || null,
    };
  } catch (err) {
    console.error('[nominatim] Reverse geocode failed:', err.message);
    return null;
  }
}

// ─── Combined Lookup ─────────────────────────────────────────────────────────
/**
 * Primary: search for mountain peaks via Overpass.
 * Fallback: reverse geocode via Nominatim for any named place.
 *
 * @param {number} lat
 * @param {number} lng
 * @returns {Promise<{name: string, elevation: number|null, osm_id: number|null, type?: string}|null>}
 */
async function getPlaceNearby(lat, lng) {
  // 1. Try peaks first (primary focus)
  const peak = await getPeakNearby(lat, lng);
  if (peak) return peak;

  // 2. Fallback: any named place via Nominatim
  console.log('[places] No peak found, trying Nominatim reverse geocode...');
  return reverseGeocode(lat, lng);
}

module.exports = { getPeakNearby, getPlaceNearby };

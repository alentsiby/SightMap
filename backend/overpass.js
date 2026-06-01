const axios = require('axios');

/**
 * Query OpenStreetMap Overpass API for mountain peaks near a coordinate.
 * No API key required — free forever.
 *
 * Searches for nodes tagged natural=peak or natural=mountain
 * within the specified radius of the hit point.
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

      // Return the closest peak
      const closest = elements[0];
      console.log(`[overpass] Found peak: "${closest.tags?.name || 'Unnamed'}" (OSM ${closest.id}) within ${radius}m`);
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

module.exports = { getPeakNearby };

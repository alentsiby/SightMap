const axios = require('axios');

/**
 * Query OpenStreetMap Overpass API for mountain peaks near a coordinate.
 * No API key required — free forever.
 *
 * Searches for nodes tagged natural=peak or natural=mountain
 * within the specified radius of the hit point.
 *
 * @param {number} lat - Latitude of ray-terrain intersection
 * @param {number} lng - Longitude of ray-terrain intersection
 * @param {number} radiusMetres - Search radius (default 600m)
 * @returns {Promise<{name: string, elevation: number|null, osm_id: number}|null>}
 */
async function getPeakNearby(lat, lng, radiusMetres = 600) {
  const query = `
    [out:json][timeout:10];
    (
      node["natural"="peak"](around:${radiusMetres},${lat},${lng});
      node["natural"="mountain"](around:${radiusMetres},${lat},${lng});
    );
    out body;
  `;

  try {
    const r = await axios.post(
      'https://overpass-api.de/api/interpreter',
      query,
      { headers: { 'Content-Type': 'text/plain' }, timeout: 8000 }
    );

    const elements = r.data.elements;
    if (!elements.length) return null;

    // Return the closest peak (Overpass returns sorted by distance)
    const closest = elements[0];
    return {
      name: closest.tags.name || closest.tags['name:en'] || 'Unknown peak',
      elevation: closest.tags.ele ? parseInt(closest.tags.ele) : null,
      osm_id: closest.id,
    };
  } catch (err) {
    console.error('[overpass] Peak lookup failed:', err.message);
    return null;
  }
}

module.exports = { getPeakNearby };

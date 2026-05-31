const axios = require('axios');

/**
 * Batch fetch elevations for multiple lat/lng points.
 *
 * Primary:  OpenTopoData (SRTM 30m) — free, no key, global coverage
 * Fallback: Open-Elevation API — free, no key
 *
 * OpenTopoData rate limit: ~1 request/second for free tier.
 * We add a delay between retries and between batch calls from the caller.
 *
 * @param {Array<{lat: number, lng: number}>} points
 * @returns {Promise<Array<number|null>>} elevations in metres (null if lookup failed)
 */
async function getElevationsBatch(points) {
  if (!points.length) return [];

  const locations = points
    .map(p => `${p.lat.toFixed(6)},${p.lng.toFixed(6)}`)
    .join('|');

  // Primary: OpenTopoData (most reliable free option)
  try {
    const r = await axios.get(
      `https://api.opentopodata.org/v1/srtm30m?locations=${locations}`,
      { timeout: 15000 }
    );
    return r.data.results.map(result => result.elevation);
  } catch (e1) {
    // If rate-limited (429), wait and retry once before falling back
    if (e1.response?.status === 429) {
      console.warn('[dem] OpenTopoData rate-limited, waiting 1.5s and retrying...');
      await sleep(1500);
      try {
        const r = await axios.get(
          `https://api.opentopodata.org/v1/srtm30m?locations=${locations}`,
          { timeout: 15000 }
        );
        return r.data.results.map(result => result.elevation);
      } catch (retryErr) {
        console.warn('[dem] OpenTopoData retry failed:', retryErr.message);
      }
    } else {
      console.warn('[dem] OpenTopoData failed:', e1.message);
    }

    // Fallback: Open-Elevation
    try {
      const r = await axios.get(
        `https://api.open-elevation.com/api/v1/lookup?locations=${locations}`,
        { timeout: 15000 }
      );
      return r.data.results.map(result => result.elevation);
    } catch (e2) {
      console.error('[dem] Both elevation APIs failed:', e2.message);
      return points.map(() => null);
    }
  }
}

function sleep(ms) {
  return new Promise(resolve => setTimeout(resolve, ms));
}

module.exports = { getElevationsBatch, sleep };

const geomagnetism = require('geomagnetism');
const { getElevationsBatch, sleep } = require('./dem');
const { getPeakNearby } = require('./overpass');
const { getWikiSummary } = require('./wiki');

// ─── Constants ───────────────────────────────────────────────────────────────
const STEP_METRES = 25;         // Resolution: one sample every 25 metres
const MAX_STEPS = 3200;         // 80 km max range (3200 × 25m)
const EARTH_RADIUS = 6371000;   // Mean Earth radius in metres
const DEG = Math.PI / 180;      // Degrees → radians multiplier

// ─── Magnetic Declination ────────────────────────────────────────────────────
/**
 * Convert magnetic compass heading to True North heading.
 * Uses the World Magnetic Model (WMM) via geomagnetism package.
 * Declination varies by location: ~1° in Kerala, ~11° in London.
 */
function applyDeclination(azimuthMag, lat, lng) {
  const model = geomagnetism.model();
  const info = model.point([lat, lng]);
  return (azimuthMag + info.decl + 360) % 360;
}

// ─── Haversine Step ──────────────────────────────────────────────────────────
/**
 * Move `distance` metres along `bearing` degrees from (lat, lng).
 * Uses the Haversine formula for great-circle navigation.
 * Returns the new lat/lng after the step.
 */
function haversineStep(lat, lng, bearing, distance) {
  const b = bearing * DEG;
  const d = distance / EARTH_RADIUS;
  const lat1 = lat * DEG;
  const lng1 = lng * DEG;

  const lat2 = Math.asin(
    Math.sin(lat1) * Math.cos(d) +
    Math.cos(lat1) * Math.sin(d) * Math.cos(b)
  );
  const lng2 = lng1 + Math.atan2(
    Math.sin(b) * Math.sin(d) * Math.cos(lat1),
    Math.cos(d) - Math.sin(lat1) * Math.sin(lat2)
  );

  return {
    lat: lat2 / DEG,
    lng: ((lng2 / DEG) + 540) % 360 - 180,
  };
}

// ─── Atmospheric Refraction ──────────────────────────────────────────────────
/**
 * Standard surveying atmospheric refraction correction.
 * Light bends slightly downward over long distances through the atmosphere,
 * making distant objects appear higher than they are.
 * At 10 km, this can shift the apparent position by 10–30 metres.
 */
function refractionCorrection(pitchDeg) {
  if (pitchDeg <= 0) return 0;
  return 0.87 / Math.tan((pitchDeg + 7.31 / (pitchDeg + 4.4)) * DEG) / 3600;
}

// ─── Main Raycast Function ───────────────────────────────────────────────────
/**
 * Cast a ray from the user's position along their line of sight and find
 * where it intersects the Earth's terrain.
 *
 * Algorithm:
 * 1. Correct magnetic azimuth → True North
 * 2. Apply atmospheric refraction to pitch
 * 3. Compute horizon distance from altitude
 * 4. Pre-compute ALL ray step positions (pure math, instant)
 * 5. Batch-fetch terrain elevations from API (chunked, 100 per call)
 * 6. Walk the ray: first point where rayAlt ≤ terrainElevation = HIT
 * 7. Enrich hit with OSM peak name + Wikipedia description
 *
 * @param {{lat: number, lng: number, alt: number, azimuth: number, pitch: number}} input
 * @returns {Promise<Object>} Result with hit info or aim_lower reason
 */
async function raycast({ lat, lng, alt, azimuth, pitch }) {
  console.log(`[raycast] Input: lat=${lat}, lng=${lng}, alt=${alt}, azimuth=${azimuth}, pitch=${pitch}`);

  // 1. Correct azimuth for magnetic declination
  const trueAzimuth = applyDeclination(azimuth, lat, lng);
  console.log(`[raycast] Magnetic azimuth ${azimuth}° → True azimuth ${trueAzimuth.toFixed(2)}°`);

  // 2. Apply atmospheric refraction to pitch
  const correctedPitch = pitch - refractionCorrection(pitch);
  const pitchRad = correctedPitch * DEG;

  // 3. Compute theoretical horizon distance based on altitude
  //    Formula: d = 3.57 × √h (km), where h = altitude in metres
  const horizonKm = 3.57 * Math.sqrt(Math.max(alt, 1));
  const maxSteps = Math.min(
    Math.floor((horizonKm * 1000) / STEP_METRES),
    MAX_STEPS
  );
  console.log(`[raycast] Horizon: ${horizonKm.toFixed(1)} km, max steps: ${maxSteps}`);

  // 4. Pre-compute ALL ray positions in one pass (pure math, instant)
  const points = [];
  let curLat = lat, curLng = lng;

  for (let i = 1; i <= maxSteps; i++) {
    const next = haversineStep(curLat, curLng, trueAzimuth, STEP_METRES);
    curLat = next.lat;
    curLng = next.lng;
    const dist = i * STEP_METRES;

    // Earth curvature: the surface curves AWAY from a straight-line ray.
    // At 10 km, the ground has dropped ~7.8 m below the ray's straight path.
    // This means the ray is HIGHER above sea level than flat-Earth geometry
    // would suggest — so we ADD curvatureDrop to the ray altitude.
    const curvatureDrop = (dist ** 2) / (2 * EARTH_RADIUS);

    // Ray altitude at this step (above sea level at that ground point)
    // = starting alt + rise from pitch + Earth curving away beneath the ray
    const rayAlt = alt + dist * Math.tan(pitchRad) + curvatureDrop;

    points.push({ lat: curLat, lng: curLng, rayAlt, step: i });
  }

  // 5. Batch fetch elevations in chunks of 100 (API limit)
  //    Check for hits after each chunk (early exit = fewer API calls)
  //    Delay 1.1s between chunks to respect OpenTopoData rate limit (~1 req/sec)
  const CHUNK = 100;
  const totalChunks = Math.ceil(points.length / CHUNK);
  console.log(`[raycast] Fetching elevations for ${points.length} points in ${totalChunks} chunks...`);

  for (let chunkIdx = 0; chunkIdx < totalChunks; chunkIdx++) {
    const start = chunkIdx * CHUNK;
    const chunk = points.slice(start, start + CHUNK);

    // Rate-limit: wait between chunks (skip delay before first)
    if (chunkIdx > 0) {
      await sleep(1100);
    }

    const elevs = await getElevationsBatch(chunk);
    console.log(`[raycast] Chunk ${chunkIdx + 1}/${totalChunks}: got ${elevs.filter(e => e != null).length}/${chunk.length} elevations`);

    // 6. Check this chunk for intersection (early exit)
    for (let j = 0; j < chunk.length; j++) {
      const globalIdx = start + j;
      const elev = elevs[j];
      if (elev == null) continue;

      if (points[globalIdx].rayAlt <= elev) {
        const hitLat = points[globalIdx].lat;
        const hitLng = points[globalIdx].lng;
        const distKm = ((globalIdx + 1) * STEP_METRES / 1000).toFixed(2);

        console.log(`[raycast] HIT at step ${globalIdx + 1}: lat=${hitLat.toFixed(5)}, lng=${hitLng.toFixed(5)}, dist=${distKm} km, terrain=${elev}m, ray=${points[globalIdx].rayAlt.toFixed(1)}m`);

        // 7. Enrich with OSM peak name and Wikipedia description
        const peak = await getPeakNearby(hitLat, hitLng);
        const wiki = peak ? await getWikiSummary(peak.name) : null;

        return {
          hit: true,
          lat: hitLat,
          lng: hitLng,
          elevation: elev,
          distance_km: distKm,
          peak,
          wiki,
        };
      }
    }
  }

  // Ray never hit terrain — user is aiming too high
  console.log('[raycast] No intersection found — ray missed all terrain');
  return { hit: false, reason: 'aim_lower' };
}

module.exports = { raycast };

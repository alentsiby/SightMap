const express = require('express');
const cors = require('cors');
const { raycast } = require('./raycast');

const app = express();
const PORT = process.env.PORT || 3000;

// ─── Middleware ──────────────────────────────────────────────────────────────
app.use(cors());
app.use(express.json());

// ─── Request Logging ─────────────────────────────────────────────────────────
app.use((req, res, next) => {
  const start = Date.now();
  res.on('finish', () => {
    const duration = Date.now() - start;
    console.log(`[${req.method}] ${req.path} → ${res.statusCode} (${duration}ms)`);
  });
  next();
});

// ─── Routes ──────────────────────────────────────────────────────────────────

/**
 * POST /raycast
 * Main endpoint — receives a 5-variable sensor vector and returns
 * the identified mountain/peak at the ray-terrain intersection.
 *
 * Body: { lat, lng, alt, azimuth, pitch }
 * Returns: { hit, lat, lng, elevation, distance_km, peak, wiki }
 *       or { hit: false, reason: "aim_lower" }
 */
app.post('/raycast', async (req, res) => {
  const { lat, lng, alt, azimuth, pitch } = req.body;

  // Validate all 5 fields are present
  if ([lat, lng, alt, azimuth, pitch].some(v => v == null)) {
    return res.status(400).json({
      error: 'Missing vector fields. Required: lat, lng, alt, azimuth, pitch',
    });
  }

  // Validate numeric types
  if ([lat, lng, alt, azimuth, pitch].some(v => typeof v !== 'number' || isNaN(v))) {
    return res.status(400).json({
      error: 'All vector fields must be valid numbers',
    });
  }

  // Validate reasonable ranges
  if (lat < -90 || lat > 90) {
    return res.status(400).json({ error: 'Latitude must be between -90 and 90' });
  }
  if (lng < -180 || lng > 180) {
    return res.status(400).json({ error: 'Longitude must be between -180 and 180' });
  }
  if (azimuth < 0 || azimuth > 360) {
    return res.status(400).json({ error: 'Azimuth must be between 0 and 360' });
  }

  try {
    const result = await raycast({ lat, lng, alt, azimuth, pitch });
    return res.json(result);
  } catch (err) {
    console.error('[server] Raycast error:', err);
    return res.status(500).json({ error: 'Internal server error: ' + err.message });
  }
});

/**
 * GET /health
 * Simple health check endpoint.
 */
app.get('/health', (_, res) => {
  res.json({
    status: 'ok',
    service: 'sightline-backend',
    uptime: process.uptime(),
  });
});

// ─── Start Server ────────────────────────────────────────────────────────────
app.listen(PORT, '0.0.0.0', () => {
  console.log(`\n🏔️  SightLine backend running on port ${PORT}`);
  console.log(`   Health: http://localhost:${PORT}/health`);
  console.log(`   Raycast: POST http://localhost:${PORT}/raycast`);
  console.log(`   Listening on all interfaces (0.0.0.0)\n`);
});

# SightLine Backend Documentation

This document outlines the architecture, setup, and key algorithmic details of the SightLine backend as implemented.

## Overview

The SightLine backend is a Node.js Express application that receives a 5-variable sensor vector from a mobile client (latitude, longitude, altitude, azimuth, pitch) and casts a mathematical ray to find where the user's line of sight intersects the Earth's terrain. It then identifies the mountain/peak at that location and enriches it with Wikipedia data.

## File Structure (under `backend/`)

- `package.json`: Project dependencies (`express`, `axios`, `geomagnetism`, `cors`).
- `server.js`: The Express API server handling routes and validation.
- `raycast.js`: The core ray-marching engine.
- `dem.js`: Elevation data fetcher (Digital Elevation Model).
- `overpass.js`: OpenStreetMap peak lookup module.
- `wiki.js`: Wikipedia summary fetcher.

## Core Algorithm: Ray-Marching (`raycast.js`)

The ray-marching algorithm determines the terrain intersection through these steps:

1.  **Magnetic Declination Correction:**
    *   Converts the mobile device's magnetic compass heading to True North using the World Magnetic Model (via the `geomagnetism` package).
2.  **Atmospheric Refraction Correction:**
    *   Applies a standard surveying correction to the pitch angle. Light bends downwards over long distances, making distant objects appear higher.
3.  **Horizon Distance Computation:**
    *   Calculates theoretical maximum visibility based on user altitude: `distance (km) = 3.57 × √(altitude in meters)`.
    *   Limits calculations to a maximum of 80 km (3200 steps of 25m).
4.  **Path Pre-computation (Haversine & Curvature):**
    *   Calculates the ray's trajectory in 25-meter steps using the Haversine formula for great-circle navigation.
    *   **Crucial Physics Implementation (Curvature Fix):** Because the Earth is a sphere, the ground curves *away* (downward) from a straight line of sight. To calculate the true altitude of the ray relative to sea level at distance `d`, the Earth's curvature drop `(d² / (2 × R))` is **added** to the ray's altitude.
    *   Formula: `rayAlt = alt + dist * Math.tan(pitchRad) + curvatureDrop`
5.  **Batch Elevation Fetching & Early Exit:**
    *   Fetches terrain elevation data for the pre-computed points in chunks of 100 to respect API limits.
    *   Implements an early exit strategy: it checks for a terrain intersection (ray altitude ≤ terrain elevation) after fetching each chunk. If a hit is found, it stops fetching further chunks to save API calls and time.
6.  **Enrichment:**
    *   Once a hit coordinates are found, queries OSM for nearby peaks and Wikipedia for descriptions.

## Data Modules & Rate Limiting

### Elevation Fetcher (`dem.js`)
*   **Primary Source:** OpenTopoData API (SRTM 30m dataset). Free, no key required.
*   **Fallback Source:** Open-Elevation API.
*   **Rate Limiting:** OpenTopoData enforces a limit of ~1 request per second. The module implements a 1.5-second delay and retry mechanism on `429 Too Many Requests` errors. The calling loop in `raycast.js` also introduces a 1.1s delay between chunk requests.

### Peak Lookup (`overpass.js`)
*   **Source:** OpenStreetMap Overpass API (`overpass-api.de`).
*   **Method:** Uses `GET` requests with a form-encoded `data` parameter to avoid `406 Not Acceptable` errors encountered with raw text `POST` requests.
*   **Progressive Radius:** Searches for `natural=peak` or `natural=mountain` nodes within a 600m radius of the hit point. If no peak is found, it automatically widens the search radius to 2000m.

### Wikipedia Enrichment (`wiki.js`)
*   **Source:** Wikipedia REST API (`/page/summary`).
*   **Action:** Fetches the text extract and thumbnail URL for the identified peak name.

## API Endpoints

### `POST /raycast`
*   **Payload:** `{ lat: Number, lng: Number, alt: Number, azimuth: Number, pitch: Number }`
*   **Response (Hit):** `{ hit: true, lat, lng, elevation, distance_km, peak: { name, elevation, osm_id }, wiki: { extract, thumbnail, url } }`
*   **Response (Miss):** `{ hit: false, reason: "aim_lower" }`

### `GET /health`
*   **Response:** `{ status: "ok", service: "sightline-backend", uptime: Number }`

## Known Limitations Addressed in Backend
*   **Rate Limits:** Handled via sleep delays between API calls.
*   **Overpass API Restrictions:** Handled by using `GET` with specific headers (`User-Agent`) and form encoding.
*   **Earth Curvature Physics:** Correctly modeled by *adding* the curvature drop to the ray's altitude relative to sea level.

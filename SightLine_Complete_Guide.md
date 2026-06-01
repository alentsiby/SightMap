# SightLine — Complete App Documentation

> Point your phone at a distant mountain. Get its name, description, and turn-by-turn directions. Entirely free to build and run.

---

## Table of Contents

1. [App Concept](#1-app-concept)
2. [User Experience Flow](#2-user-experience-flow)
3. [System Architecture](#3-system-architecture)
4. [Free Stack Overview](#4-free-stack-overview)
5. [Edge Cases and Engineering Challenges](#5-edge-cases-and-engineering-challenges)
6. [Part 1 — Oracle Cloud VM Setup](#6-part-1--oracle-cloud-vm-setup)
7. [Part 2 — Firebase Studio Setup](#7-part-2--firebase-studio-setup)
8. [Part 3 — Backend Code](#8-part-3--backend-code)
9. [Part 4 — Flutter App Code](#9-part-4--flutter-app-code)
10. [Part 5 — Build and Deploy](#10-part-5--build-and-deploy)
11. [MVP Roadmap](#11-mvp-roadmap)
12. [Extra Free Features](#12-extra-free-features)

---

## 1. App Concept

**SightLine** is an Android app that uses your phone's sensors (GPS, compass, accelerometer) to cast a mathematical ray from your location toward wherever you are pointing the camera. It finds where that ray intersects the Earth's terrain using elevation data, then identifies the mountain or landmark at that point and opens Google Maps for navigation.

**Core value proposition:** The user points their phone at a distant geographical feature → the app calculates its exact coordinates using sensor vectors → hands routing off to Google Maps — all at zero cost.

---

## 2. User Experience Flow

### Step 1 — Sensor Calibration
The user opens the app. Before the camera enables, the app checks the magnetometer's accuracy. If the sensor is uncalibrated, an on-screen prompt asks the user to move their phone in a **figure-8 motion** to eliminate magnetic interference.

### Step 2 — Target Acquisition
The camera viewfinder opens with a centre crosshair (HUD). Overlay text displays live telemetry:
- GPS accuracy (e.g. ±3 metres)
- Compass heading (0°–360°)
- Pitch angle (degrees above/below horizon)

### Step 3 — Data Capture (The Lock)
The user centres the crosshair on a distant object (e.g. aiming at Agasthyarkoodam peak from the city) and taps the **Lock** button. The app freezes the frame and captures the 5-variable vector:

| Variable | Description |
|---|---|
| Latitude | User's GPS latitude |
| Longitude | User's GPS longitude |
| Altitude | User's GPS altitude in metres |
| Azimuth | Compass heading (magnetic, corrected server-side) |
| Pitch | Tilt angle above or below horizontal |

### Step 4 — Vector Processing
A loading animation plays. The app transmits the 5-variable vector to the backend, which calculates where that line of sight intersects the Earth's topography.

### Step 5 — Results
A bottom sheet slides up showing:
- Identified peak name (from OpenStreetMap)
- Distance from user
- Elevation of the peak
- Wikipedia description and thumbnail
- Navigate and Share buttons

### Step 6 — Handoff to Google Maps
The user taps **Navigate**. The app fires a native URI intent (`google.navigation:q=<Lat>,<Long>`), opening Google Maps with the destination pre-loaded and routing started — completely free via deep link.

---

## 3. System Architecture

```
PHONE (Flutter App)
│
│  Sensors: GPS + IMU + Camera
│       ↓
│  Kalman / Complementary Filter
│       ↓
│  5-Variable Vector (Lat, Long, Alt, Azimuth, Pitch)
│       ↓
│  POST to backend
│
ORACLE CLOUD VM (Node.js + Nginx + HTTPS)
│
│  1. Apply magnetic declination correction
│  2. Pre-compute all ray step positions (Haversine math)
│  3. Batch fetch terrain elevation (OpenTopoData API)
│  4. Find first ray-terrain intersection
│  5. Query OSM Overpass API → peak name
│  6. Query Wikipedia REST API → description + thumbnail
│       ↓
│  Return JSON result
│
PHONE
│
│  Display bottom sheet with peak info
│       ↓
│  url_launcher → Google Maps navigation (free deep link)
```

---

## 4. Free Stack Overview

| Layer | Tool | Free Tier |
|---|---|---|
| Mobile framework | Flutter | Unlimited |
| IDE | Firebase Studio (Project IDX) | Free |
| Backend hosting | Oracle Cloud Always Free VM | Free forever |
| HTTPS + domain | DuckDNS + Certbot + Nginx | Free forever |
| Elevation data | OpenTopoData API (SRTM 30m) | Free, no key |
| Elevation fallback | Open-Elevation API | Free, no key |
| Peak names | OSM Overpass API | Free, no key |
| Descriptions | Wikipedia REST API | Free, no key |
| Visual fallback | Google Cloud Vision API | 1000 calls/month free |
| Navigation | Google Maps deep link (url_launcher) | Free, no API key |
| **Total monthly cost** | | **₹0** |

> **No NASA key needed.** OpenTopoData wraps the same SRTM data NASA published and is free without any registration.

---

## 5. Edge Cases and Engineering Challenges

| Challenge | Solution |
|---|---|
| **Noisy IMU data** | Kalman / complementary filter merges gyroscope (fast, drifts) with magnetometer (stable, noisy) to produce a smooth heading |
| **Magnetic vs True North** | Server applies magnetic declination offset using the `geomagnetism` npm package (WMM model) |
| **Earth's curvature** | Haversine formula used at every step. At 10 km, Earth curves ~8 metres — flat geometry would give wrong results |
| **Atmospheric refraction** | Surveying correction applied to pitch angle: light bends slightly over long distances shifting apparent target by 10–30 m |
| **Ray shoots into sky** | If pitch is too high, ray never hits terrain. Server has max 80 km range limit and returns `aim_lower` error |
| **API call count** | All ray step positions pre-computed in one pass, then elevations fetched in a single batch API call — not one call per step |
| **Cold starts on free hosting** | Oracle VM runs 24/7 with PM2 — no cold starts unlike serverless options |

---

## 6. Part 1 — Oracle Cloud VM Setup

### Step 1: Create Oracle Free Account

1. Go to **cloud.oracle.com**
2. Click **Start for free**
3. Fill in name and email
4. Set home region to **India South (Hyderabad)** — closest to Kerala
5. Add a card for identity verification (no charge ever made)
6. Verify your phone number

### Step 2: Create the VM Instance

1. In Oracle Console → **Compute → Instances → Create Instance**
2. Name it `sightline-backend`
3. Click **Change Image** → select **Ubuntu 22.04**
4. Click **Change Shape** → select **VM.Standard.A1.Flex** (this is the always-free ARM shape)
   - Set OCPU count: **1**
   - Set Memory: **6 GB**
5. Under **Add SSH keys** → click **Generate a key pair**
   - Download both the private key (`.key` file) and public key
   - Save the private key safely
6. Click **Create**
7. Wait 2 minutes. Note the **Public IP address**

### Step 3: Open Firewall Ports

Oracle blocks all ports by default. Open the ones needed:

1. Click your instance → **Subnet** → **Security List**
2. Click **Add Ingress Rules** and add:

| Source CIDR | Protocol | Destination Port |
|---|---|---|
| 0.0.0.0/0 | TCP | 3000 |
| 0.0.0.0/0 | TCP | 443 |
| 0.0.0.0/0 | TCP | 80 |

Also open ports inside the VM's own firewall:

```bash
sudo iptables -I INPUT -p tcp --dport 3000 -j ACCEPT
sudo iptables -I INPUT -p tcp --dport 80 -j ACCEPT
sudo iptables -I INPUT -p tcp --dport 443 -j ACCEPT
sudo netfilter-persistent save
```

### Step 4: SSH Into the VM and Install Software

```bash
# Connect from your laptop terminal
ssh -i ~/Downloads/your-key.key ubuntu@YOUR_ORACLE_IP

# Update system packages
sudo apt update && sudo apt upgrade -y

# Install Node.js 20
curl -fsSL https://deb.nodesource.com/setup_20.x | sudo -E bash -
sudo apt install -y nodejs

# Install PM2 (keeps server running forever, auto-restarts on reboot)
sudo npm install -g pm2

# Install Nginx (web server for HTTPS termination)
sudo apt install -y nginx

# Verify installations
node --version    # should show v20.x
npm --version
pm2 --version
```

### Step 5: Get a Free HTTPS Domain via DuckDNS

1. Go to **duckdns.org** → log in with Google
2. Type `sightline-api` in the subdomain box → click **Add Domain**
3. Copy your **token** shown on the page
4. Enter your Oracle VM public IP in the IP field → click **Update IP**
5. Your backend URL will be: `https://sightline-api.duckdns.org`

### Step 6: Configure Nginx and Get SSL Certificate

```bash
# Create Nginx config
sudo nano /etc/nginx/sites-available/sightline
```

Paste this content:

```nginx
server {
    listen 80;
    server_name sightline-api.duckdns.org;

    location / {
        proxy_pass http://localhost:3000;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host $host;
        proxy_cache_bypass $http_upgrade;
        proxy_read_timeout 30s;
    }
}
```

```bash
# Save (Ctrl+X, Y, Enter), then enable the site
sudo ln -s /etc/nginx/sites-available/sightline /etc/nginx/sites-enabled/
sudo nginx -t
sudo systemctl restart nginx

# Install Certbot and get free SSL certificate
sudo apt install -y certbot python3-certbot-nginx
sudo certbot --nginx -d sightline-api.duckdns.org
# Follow prompts: enter email, agree to terms
# Certbot auto-edits Nginx config for HTTPS
```

Your backend is now permanently reachable at `https://sightline-api.duckdns.org`.

---

## 7. Part 2 — Firebase Studio Setup

### Step 1: Open Firebase Studio

1. Go to **studio.firebase.google.com**
2. Sign in with your Google account
3. Click **Create a new project**
4. Choose **Flutter** from the templates list
5. Name it `sightline`
6. Wait ~2 minutes while the workspace boots

You now have a complete Linux + Flutter development environment running in your browser.

### Step 2: Create Project Structure

In the Firebase Studio terminal (bottom panel):

```bash
mkdir -p lib/screens lib/services lib/models
touch lib/screens/calibration_screen.dart
touch lib/screens/viewfinder_screen.dart
touch lib/screens/result_sheet.dart
touch lib/services/sensor_service.dart
touch lib/services/api_service.dart
touch lib/models/sight_vector.dart
touch lib/models/sighting_result.dart
```

### Step 3: Add Android Permissions

Open `android/app/src/main/AndroidManifest.xml`. Add inside `<manifest>` before `<application>`:

```xml
<uses-permission android:name="android.permission.CAMERA"/>
<uses-permission android:name="android.permission.ACCESS_FINE_LOCATION"/>
<uses-permission android:name="android.permission.ACCESS_COARSE_LOCATION"/>
<uses-permission android:name="android.permission.INTERNET"/>
<uses-permission android:name="android.permission.VIBRATE"/>
<uses-feature android:name="android.hardware.camera" android:required="true"/>
<uses-feature android:name="android.hardware.location.gps" android:required="true"/>
<uses-feature android:name="android.hardware.sensor.accelerometer" android:required="true"/>
<uses-feature android:name="android.hardware.sensor.compass" android:required="true"/>
```

Inside `<activity>` add:

```xml
android:screenOrientation="portrait"
```

---

## 8. Part 3 — Backend Code

All files go inside `~/sightline-backend/` on your Oracle VM.

### `package.json`

```json
{
  "name": "sightline-backend",
  "version": "1.0.0",
  "main": "server.js",
  "scripts": { "start": "node server.js" },
  "dependencies": {
    "express": "^4.18.2",
    "axios": "^1.6.0",
    "geomagnetism": "^4.0.0",
    "cors": "^2.8.5"
  }
}
```

### `server.js`

```javascript
const express = require('express');
const cors = require('cors');
const { raycast } = require('./raycast');

const app = express();
app.use(cors());
app.use(express.json());

app.post('/raycast', async (req, res) => {
  const { lat, lng, alt, azimuth, pitch } = req.body;

  if ([lat, lng, alt, azimuth, pitch].some(v => v == null)) {
    return res.status(400).json({ error: 'Missing vector fields' });
  }

  try {
    const result = await raycast({ lat, lng, alt, azimuth, pitch });
    return res.json(result);
  } catch (err) {
    return res.status(500).json({ error: err.message });
  }
});

app.get('/health', (_, res) => res.json({ status: 'ok' }));

app.listen(3000, () => console.log('SightLine backend running on port 3000'));
```

### `dem.js` — Elevation Data (No API Key Required)

```javascript
const axios = require('axios');

// Batch fetch elevations for multiple points in one API call
// OpenTopoData: free, no key, SRTM 30m global data
// Max 100 points per request — chunk larger arrays
async function getElevationsBatch(points) {
  const locations = points
    .map(p => `${p.lat.toFixed(6)},${p.lng.toFixed(6)}`)
    .join('|');

  // Primary: OpenTopoData (most reliable free option)
  try {
    const r = await axios.get(
      `https://api.opentopodata.org/v1/srtm30m?locations=${locations}`,
      { timeout: 15000 }
    );
    return r.data.results.map(r => r.elevation);
  } catch (e1) {
    // Fallback: Open-Elevation
    try {
      const r = await axios.get(
        `https://api.open-elevation.com/api/v1/lookup?locations=${locations}`,
        { timeout: 15000 }
      );
      return r.data.results.map(r => r.elevation);
    } catch (e2) {
      return points.map(() => null);
    }
  }
}

module.exports = { getElevationsBatch };
```

### `raycast.js` — Core Ray-March Engine

```javascript
const geomagnetism = require('geomagnetism');
const { getElevationsBatch } = require('./dem');
const { getPeakNearby } = require('./overpass');
const { getWikiSummary } = require('./wiki');

const STEP_METRES = 25;
const MAX_STEPS = 3200;        // 80 km max range
const EARTH_RADIUS = 6371000;  // metres
const DEG = Math.PI / 180;

// Apply magnetic declination: Magnetic North → True North
function applyDeclination(azimuthMag, lat, lng) {
  const model = geomagnetism.model();
  const info = model.point([lat, lng]);
  return (azimuthMag + info.decl + 360) % 360;
}

// Move `distance` metres along `bearing` from (lat, lng) using Haversine
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
    lng: ((lng2 / DEG) + 540) % 360 - 180
  };
}

// Standard surveying atmospheric refraction correction
function refractionCorrection(pitchDeg) {
  if (pitchDeg <= 0) return 0;
  return 0.87 / Math.tan((pitchDeg + 7.31 / (pitchDeg + 4.4)) * DEG) / 3600;
}

async function raycast({ lat, lng, alt, azimuth, pitch }) {
  // 1. Correct azimuth for magnetic declination
  const trueAzimuth = applyDeclination(azimuth, lat, lng);

  // 2. Apply atmospheric refraction to pitch
  const correctedPitch = pitch - refractionCorrection(pitch);
  const pitchRad = correctedPitch * DEG;

  // 3. Compute theoretical horizon distance
  const horizonKm = 3.57 * Math.sqrt(Math.max(alt, 1));
  const maxSteps = Math.min(
    Math.floor((horizonKm * 1000) / STEP_METRES),
    MAX_STEPS
  );

  // 4. Pre-compute ALL ray positions in one pass (pure math, instant)
  const points = [];
  let curLat = lat, curLng = lng;

  for (let i = 1; i <= maxSteps; i++) {
    const next = haversineStep(curLat, curLng, trueAzimuth, STEP_METRES);
    curLat = next.lat;
    curLng = next.lng;
    const dist = i * STEP_METRES;
    const curvatureDrop = (dist ** 2) / (2 * EARTH_RADIUS);
    const rayAlt = alt + dist * Math.tan(pitchRad) - curvatureDrop;
    points.push({ lat: curLat, lng: curLng, rayAlt, step: i });
  }

  // 5. Batch fetch elevations in chunks of 100 (API limit)
  const CHUNK = 100;
  const allElevations = [];
  for (let i = 0; i < points.length; i += CHUNK) {
    const chunk = points.slice(i, i + CHUNK);
    const elevs = await getElevationsBatch(chunk);
    allElevations.push(...elevs);
  }

  // 6. Find first intersection (ray goes underground = hit)
  for (let i = 0; i < points.length; i++) {
    const elev = allElevations[i];
    if (elev == null) continue;

    if (points[i].rayAlt <= elev) {
      const hitLat = points[i].lat;
      const hitLng = points[i].lng;
      const distKm = ((i + 1) * STEP_METRES / 1000).toFixed(2);

      // Enrich with OSM peak name and Wikipedia description
      const peak = await getPeakNearby(hitLat, hitLng);
      const wiki = peak ? await getWikiSummary(peak.name) : null;

      return {
        hit: true,
        lat: hitLat,
        lng: hitLng,
        elevation: elev,
        distance_km: distKm,
        peak,
        wiki
      };
    }
  }

  // Ray never hit terrain
  return { hit: false, reason: 'aim_lower' };
}

module.exports = { raycast };
```

### `overpass.js` — Free Peak Names from OpenStreetMap

```javascript
const axios = require('axios');

// Query OSM Overpass API for mountain peaks near a coordinate
// No API key required — free forever
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

    const closest = elements[0];
    return {
      name: closest.tags.name || closest.tags['name:en'] || 'Unknown peak',
      elevation: closest.tags.ele ? parseInt(closest.tags.ele) : null,
      osm_id: closest.id
    };
  } catch {
    return null;
  }
}

module.exports = { getPeakNearby };
```

### `wiki.js` — Free Descriptions from Wikipedia

```javascript
const axios = require('axios');

// Wikipedia REST API — no key, free, returns clean JSON summary
async function getWikiSummary(peakName) {
  try {
    const encoded = encodeURIComponent(peakName.replace(/ /g, '_'));
    const r = await axios.get(
      `https://en.wikipedia.org/api/rest_v1/page/summary/${encoded}`,
      { timeout: 5000 }
    );
    return {
      extract: r.data.extract,
      thumbnail: r.data.thumbnail?.source || null,
      url: r.data.content_urls?.mobile?.page || null
    };
  } catch {
    return null;
  }
}

module.exports = { getWikiSummary };
```

### Start the Backend

```bash
cd ~/sightline-backend
npm install
pm2 start server.js --name sightline
pm2 save
pm2 startup    # run the command it prints to enable auto-restart

# Test health endpoint
curl https://sightline-api.duckdns.org/health
# Expected: {"status":"ok"}

# Test a full raycast
curl -X POST https://sightline-api.duckdns.org/raycast \
  -H "Content-Type: application/json" \
  -d '{
    "lat": 8.7139,
    "lng": 77.1025,
    "alt": 120,
    "azimuth": 315,
    "pitch": 4.2
  }'
```

---

## 9. Part 4 — Flutter App Code

All files go inside `lib/` in your Firebase Studio project.

### `pubspec.yaml`

```yaml
name: sightline
description: Point your phone at a mountain. Get directions.
version: 1.0.0+1

environment:
  sdk: ">=3.0.0 <4.0.0"

dependencies:
  flutter:
    sdk: flutter
  camera: ^0.10.5+9
  geolocator: ^10.1.0
  sensors_plus: ^4.0.2
  flutter_compass: ^0.8.0
  url_launcher: ^6.2.4
  http: ^1.1.0
  share_plus: ^7.2.2
  screenshot: ^2.1.0
  provider: ^6.1.1

dev_dependencies:
  flutter_test:
    sdk: flutter
  flutter_lints: ^3.0.0

flutter:
  uses-material-design: true
```

```bash
flutter pub get
```

### `lib/models/sight_vector.dart`

```dart
class SightVector {
  final double lat;
  final double lng;
  final double alt;
  final double azimuth;  // raw magnetic — corrected server-side
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
}
```

### `lib/models/sighting_result.dart`

```dart
class PeakInfo {
  final String name;
  final int? elevation;
  const PeakInfo({required this.name, this.elevation});

  factory PeakInfo.fromJson(Map<String, dynamic> j) =>
      PeakInfo(name: j['name'], elevation: j['elevation']);
}

class WikiInfo {
  final String extract;
  final String? thumbnail;
  final String? url;
  const WikiInfo({required this.extract, this.thumbnail, this.url});

  factory WikiInfo.fromJson(Map<String, dynamic> j) => WikiInfo(
    extract: j['extract'],
    thumbnail: j['thumbnail'],
    url: j['url'],
  );
}

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
    hit: j['hit'],
    lat: j['lat']?.toDouble(),
    lng: j['lng']?.toDouble(),
    elevation: j['elevation']?.toDouble(),
    distanceKm: double.tryParse(j['distance_km']?.toString() ?? ''),
    peak: j['peak'] != null ? PeakInfo.fromJson(j['peak']) : null,
    wiki: j['wiki'] != null ? WikiInfo.fromJson(j['wiki']) : null,
    reason: j['reason'],
  );
}
```

### `lib/services/sensor_service.dart`

```dart
import 'dart:async';
import 'dart:math';
import 'package:geolocator/geolocator.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'package:flutter_compass/flutter_compass.dart';
import '../models/sight_vector.dart';

class SensorService {
  // Complementary filter: 96% gyroscope, 4% accelerometer correction
  static const double _alpha = 0.96;

  double _pitch = 0.0;
  double _azimuth = 0.0;
  Position? _position;

  double get pitch => _pitch;
  double get azimuth => _azimuth;
  Position? get position => _position;

  final _pitchController = StreamController<double>.broadcast();
  final _azimuthController = StreamController<double>.broadcast();

  Stream<double> get pitchStream => _pitchController.stream;
  Stream<double> get azimuthStream => _azimuthController.stream;

  StreamSubscription? _accelSub;
  StreamSubscription? _compassSub;
  StreamSubscription? _gpsSub;

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

  double _calcPitch(double x, double y, double z) {
    return atan2(-x, sqrt(y * y + z * z)) * 180 / pi;
  }

  // Capture a snapshot of all sensor values at this exact moment
  SightVector? snapshot() {
    if (_position == null) return null;
    return SightVector(
      lat: _position!.latitude,
      lng: _position!.longitude,
      alt: _position!.altitude,
      azimuth: _azimuth,
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
```

### `lib/services/api_service.dart`

```dart
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/sight_vector.dart';
import '../models/sighting_result.dart';

class ApiService {
  // Replace with your actual DuckDNS subdomain
  static const String _base = 'https://sightline-api.duckdns.org';

  Future<SightingResult> raycast(SightVector vector) async {
    final response = await http.post(
      Uri.parse('$_base/raycast'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(vector.toJson()),
    ).timeout(const Duration(seconds: 25));

    if (response.statusCode != 200) {
      throw Exception('Server error ${response.statusCode}');
    }
    return SightingResult.fromJson(jsonDecode(response.body));
  }
}
```

### `lib/screens/calibration_screen.dart`

```dart
import 'package:flutter/material.dart';
import 'viewfinder_screen.dart';

class CalibrationScreen extends StatefulWidget {
  const CalibrationScreen({super.key});
  @override
  State<CalibrationScreen> createState() => _CalibrationScreenState();
}

class _CalibrationScreenState extends State<CalibrationScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _rotation;
  bool _done = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    )..repeat();
    _rotation = Tween(begin: 0.0, end: 6.28).animate(_controller);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              AnimatedBuilder(
                animation: _rotation,
                builder: (_, child) => Transform.rotate(
                  angle: _rotation.value,
                  child: child,
                ),
                child: const Icon(Icons.explore, color: Colors.white, size: 80),
              ),
              const SizedBox(height: 40),
              const Text(
                'Calibrate compass',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'Move your phone slowly in a figure-8 motion until the indicator is stable.',
                style: TextStyle(color: Colors.white60, fontSize: 15, height: 1.6),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 48),
              if (!_done)
                OutlinedButton(
                  onPressed: () => setState(() => _done = true),
                  style: OutlinedButton.styleFrom(foregroundColor: Colors.white),
                  child: const Text('Done — looks stable'),
                ),
              if (_done)
                FilledButton(
                  onPressed: () => Navigator.pushReplacement(
                    context,
                    MaterialPageRoute(builder: (_) => const ViewfinderScreen()),
                  ),
                  child: const Text('Open camera'),
                ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }
}
```

### `lib/screens/viewfinder_screen.dart`

```dart
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import '../services/sensor_service.dart';
import '../services/api_service.dart';
import '../models/sighting_result.dart';
import 'result_sheet.dart';

class ViewfinderScreen extends StatefulWidget {
  const ViewfinderScreen({super.key});
  @override
  State<ViewfinderScreen> createState() => _ViewfinderScreenState();
}

class _ViewfinderScreenState extends State<ViewfinderScreen> {
  CameraController? _cam;
  final SensorService _sensors = SensorService();
  final ApiService _api = ApiService();
  bool _locking = false;
  String _status = '';

  @override
  void initState() {
    super.initState();
    _initCamera();
    _sensors.start();
  }

  Future<void> _initCamera() async {
    final cameras = await availableCameras();
    _cam = CameraController(cameras[0], ResolutionPreset.high);
    await _cam!.initialize();
    if (mounted) setState(() {});
  }

  Future<void> _lock() async {
    if (_locking) return;
    final vector = _sensors.snapshot();
    if (vector == null) {
      setState(() => _status = 'Waiting for GPS fix…');
      return;
    }

    setState(() { _locking = true; _status = 'Calculating…'; });

    try {
      final result = await _api.raycast(vector);
      if (!mounted) return;

      if (!result.hit) {
        setState(() {
          _status = 'Target not found — aim lower at the mountain';
          _locking = false;
        });
        return;
      }

      setState(() { _status = ''; _locking = false; });
      _showResult(result);
    } catch (e) {
      setState(() { _status = 'Connection error — check internet'; _locking = false; });
    }
  }

  void _showResult(SightingResult result) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => ResultSheet(result: result),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // Camera preview fills screen
          if (_cam?.value.isInitialized == true)
            CameraPreview(_cam!),

          // HUD overlay
          SafeArea(
            child: Column(
              children: [
                // Telemetry bar at top
                StreamBuilder<double>(
                  stream: _sensors.azimuthStream,
                  builder: (_, azSnap) => StreamBuilder<double>(
                    stream: _sensors.pitchStream,
                    builder: (_, pitchSnap) {
                      final az = azSnap.data?.toStringAsFixed(1) ?? '--';
                      final pt = pitchSnap.data?.toStringAsFixed(1) ?? '--';
                      final acc = _sensors.position?.accuracy.toStringAsFixed(0) ?? '--';
                      return Container(
                        margin: const EdgeInsets.all(12),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black54,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceAround,
                          children: [
                            _telemetryItem('GPS', '±${acc}m'),
                            _telemetryItem('HDG', '${az}°'),
                            _telemetryItem('PITCH', '${pt}°'),
                          ],
                        ),
                      );
                    },
                  ),
                ),

                const Spacer(),

                // Centre crosshair
                const Icon(Icons.add, color: Colors.white, size: 48),

                // Status message
                if (_status.isNotEmpty)
                  Container(
                    margin: const EdgeInsets.only(top: 12),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black54,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      _status,
                      style: const TextStyle(color: Colors.white70, fontSize: 13),
                    ),
                  ),

                const Spacer(),

                // Lock button
                GestureDetector(
                  onTap: _lock,
                  child: Container(
                    margin: const EdgeInsets.only(bottom: 48),
                    width: 72,
                    height: 72,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 3),
                      color: _locking ? Colors.white24 : Colors.transparent,
                    ),
                    child: _locking
                      ? const CircularProgressIndicator(
                          color: Colors.white, strokeWidth: 2,
                        )
                      : const Icon(Icons.my_location, color: Colors.white, size: 30),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _telemetryItem(String label, String value) => Column(
    children: [
      Text(label, style: const TextStyle(color: Colors.white38, fontSize: 10)),
      Text(value, style: const TextStyle(
        color: Colors.white, fontSize: 13, fontWeight: FontWeight.w500,
      )),
    ],
  );

  @override
  void dispose() {
    _cam?.dispose();
    _sensors.dispose();
    super.dispose();
  }
}
```

### `lib/screens/result_sheet.dart`

```dart
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:share_plus/share_plus.dart';
import '../models/sighting_result.dart';

class ResultSheet extends StatelessWidget {
  final SightingResult result;
  const ResultSheet({super.key, required this.result});

  Future<void> _navigate() async {
    final uri = Uri.parse('google.navigation:q=${result.lat},${result.lng}');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    }
  }

  Future<void> _share() async {
    final name = result.peak?.name ?? 'Unknown peak';
    final lat = result.lat?.toStringAsFixed(5);
    final lng = result.lng?.toStringAsFixed(5);
    await Share.share(
      '📍 $name — ${result.distanceKm} km away\n'
      'Coordinates: $lat, $lng\n\n'
      'Identified with SightLine',
    );
  }

  @override
  Widget build(BuildContext context) {
    final peak = result.peak;
    final wiki = result.wiki;

    return DraggableScrollableSheet(
      initialChildSize: 0.52,
      minChildSize: 0.3,
      maxChildSize: 0.9,
      builder: (_, controller) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: ListView(
          controller: controller,
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
          children: [
            // Drag handle
            Center(
              child: Container(
                width: 40, height: 4,
                decoration: BoxDecoration(
                  color: Colors.black12,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 20),

            // Wikipedia thumbnail
            if (wiki?.thumbnail != null)
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.network(
                  wiki!.thumbnail!,
                  height: 160,
                  width: double.infinity,
                  fit: BoxFit.cover,
                ),
              ),

            const SizedBox(height: 16),

            // Peak name
            Text(
              peak?.name ?? 'Identified location',
              style: const TextStyle(
                fontSize: 22, fontWeight: FontWeight.w600,
              ),
            ),

            // Distance and elevation chips
            const SizedBox(height: 8),
            Row(
              children: [
                if (result.distanceKm != null)
                  _chip('${result.distanceKm} km away'),
                const SizedBox(width: 8),
                if (peak?.elevation != null)
                  _chip('${peak!.elevation} m elevation'),
              ],
            ),

            // Wikipedia description
            if (wiki?.extract != null) ...[
              const SizedBox(height: 16),
              Text(
                wiki!.extract,
                style: const TextStyle(
                  fontSize: 14, color: Colors.black54, height: 1.6,
                ),
              ),
            ],

            const SizedBox(height: 24),

            // Navigate button
            FilledButton.icon(
              onPressed: _navigate,
              icon: const Icon(Icons.directions),
              label: const Text('Navigate with Google Maps'),
              style: FilledButton.styleFrom(
                minimumSize: const Size(double.infinity, 50),
              ),
            ),

            const SizedBox(height: 12),

            // Share button
            OutlinedButton.icon(
              onPressed: _share,
              icon: const Icon(Icons.share),
              label: const Text('Share this sighting'),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size(double.infinity, 50),
              ),
            ),

            // Coordinates footnote
            const SizedBox(height: 16),
            Text(
              '${result.lat?.toStringAsFixed(5)}, ${result.lng?.toStringAsFixed(5)}',
              style: const TextStyle(fontSize: 11, color: Colors.black26),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _chip(String label) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
    decoration: BoxDecoration(
      color: Colors.black.withOpacity(0.06),
      borderRadius: BorderRadius.circular(20),
    ),
    child: Text(
      label,
      style: const TextStyle(fontSize: 12, color: Colors.black54),
    ),
  );
}
```

### `lib/main.dart`

```dart
import 'package:flutter/material.dart';
import 'screens/calibration_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const SightLineApp());
}

class SightLineApp extends StatelessWidget {
  const SightLineApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SightLine',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: Colors.deepOrange,
      ),
      home: const CalibrationScreen(),
    );
  }
}
```

---

## 10. Part 5 — Build and Deploy

### Build the APK in Firebase Studio

```bash
# In the Firebase Studio terminal

# Get all packages
flutter pub get

# Check for any issues
flutter analyze

# Build release APK
flutter build apk --release

# APK location:
# build/app/outputs/flutter-apk/app-release.apk
```

In Firebase Studio's file panel, navigate to `build/app/outputs/flutter-apk/`, right-click `app-release.apk`, and click **Download**.

On your Android phone:
1. Settings → Security → enable **Install from unknown sources**
2. Open the downloaded APK and install

### Update the backend after changes

```bash
# SSH into your Oracle VM
ssh -i ~/your-key.key ubuntu@YOUR_ORACLE_IP

# Pull changes or edit files, then restart
pm2 restart sightline
pm2 logs sightline    # watch live logs
```

---

## 11. MVP Roadmap

Build in this order to isolate the hardest variables first:

| Step | What to Build | How to Verify |
|---|---|---|
| 1 | Sensor readout screen — print pitch, azimuth, GPS live | Walk outside, compare heading with a physical compass |
| 2 | Node.js raycaster — hardcode a known location and vector | Check if output matches the hill you know you're pointing at |
| 3 | Connect Flutter to backend — full loop with Lock button | Stand at a viewpoint, lock on a known peak, verify coordinates |
| 4 | Add OSM + Wikipedia enrichment | Check that peak name and description are correct |
| 5 | Add Share and Navigate buttons | Confirm Google Maps opens with correct destination |

---

## 12. Extra Free Features

These can all be added post-MVP at zero cost:

### AR Distance Readout
Once the hit coordinates are returned, compute great-circle distance and display it live on the HUD:
```
📍 Agasthyarkoodam — 34.2 km
```
Pure Haversine math. No API.

### Horizon Distance Estimator
Display the theoretical max visibility based on user altitude as a live HUD element:
```dart
double horizonKm = 3.57 * sqrt(altitudeMetres);
```

### Sighting Cards — Save and Share
Use the `screenshot` package to export the camera frame + HUD overlay as a PNG, then share via `share_plus`. No cost, native share sheet.

### Crowd-sourced Corrections
Add a **"Report a correction"** button. If the user knows the app got the name wrong, they submit:
```json
{ "vector": {...}, "correct_name": "Meesapulimala", "correct_coords": {...} }
```
Store in Firebase Firestore (50,000 reads/day free). Over time you build a correction layer specific to Kerala's terrain that no commercial app has.

### Self-hosted SRTM Tiles (Remove External Dependency)
Download the Kerala SRTM tile once (~40 MB) to your Oracle VM and serve elevation lookups locally — zero external API dependency, instant response:

```bash
# On Oracle VM
pip3 install elevation --break-system-packages
eio clip --bounds 76.0 8.0 78.0 12.0 --output kerala.tif
```

Then read it with the `geotiff` npm package for sub-millisecond elevation lookups.

---

## Accounts Needed — Complete List

| Account | Purpose | Cost |
|---|---|---|
| Google (Firebase Studio) | IDE | Free — you already have one |
| Oracle Cloud | Always-free VM | Free — card for verification only, never charged |
| DuckDNS | Free HTTPS subdomain | Free — log in with Google |

**That is all.** No paid API keys, no monthly subscriptions, no hidden costs.

---

*SightLine — Built entirely free. Runs entirely free. Forever.*
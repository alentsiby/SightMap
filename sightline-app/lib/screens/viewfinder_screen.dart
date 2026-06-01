import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:permission_handler/permission_handler.dart';
import '../services/sensor_service.dart';
import '../services/api_service.dart';
import '../models/sighting_result.dart';
import 'result_sheet.dart';

/// Main screen — full-screen camera with HUD overlay, Lock button,
/// and optional azimuth offset slider for compass drift correction.
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
  bool _showOffsetSlider = false;
  double _offsetValue = 0.0;

  @override
  void initState() {
    super.initState();
    _requestPermissionsAndStart();
  }

  Future<void> _requestPermissionsAndStart() async {
    // Request camera and location permissions
    final statuses = await [
      Permission.camera,
      Permission.locationWhenInUse,
    ].request();

    if (statuses[Permission.camera]!.isGranted &&
        statuses[Permission.locationWhenInUse]!.isGranted) {
      _sensors.start();
      await _initCamera();
    } else {
      if (mounted) {
        setState(() => _status = 'Camera & location permissions required');
      }
    }
  }

  Future<void> _initCamera() async {
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        setState(() => _status = 'No camera found');
        return;
      }
      _cam = CameraController(cameras[0], ResolutionPreset.high);
      await _cam!.initialize();
      if (mounted) setState(() {});
    } catch (e) {
      if (mounted) setState(() => _status = 'Camera error: $e');
    }
  }

  Future<void> _lock() async {
    if (_locking) return;
    final vector = _sensors.snapshot();
    if (vector == null) {
      setState(() => _status = 'Waiting for GPS fix…');
      return;
    }

    setState(() {
      _locking = true;
      _status = 'Calculating…';
    });

    try {
      final result = await _api.raycast(
        vector,
        onProgress: (msg) {
          if (mounted) setState(() => _status = msg);
        },
      );
      if (!mounted) return;

      if (!result.hit) {
        setState(() {
          _status = 'Target not found — aim lower at the mountain';
          _locking = false;
        });
        return;
      }

      setState(() {
        _status = '';
        _locking = false;
      });
      _showResult(result);
    } catch (e) {
      if (mounted) {
        setState(() {
          _status = e.toString().replaceAll('Exception: ', '');
          _locking = false;
        });
      }
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
          // Camera preview
          if (_cam?.value.isInitialized == true)
            CameraPreview(_cam!)
          else
            const Center(
              child: CircularProgressIndicator(color: Colors.white24),
            ),

          // HUD overlay
          SafeArea(
            child: Column(
              children: [
                // ─── Telemetry Bar ───────────────────────────────────
                StreamBuilder<double>(
                  stream: _sensors.azimuthStream,
                  builder: (_, azSnap) => StreamBuilder<double>(
                    stream: _sensors.pitchStream,
                    builder: (_, pitchSnap) {
                      final az = azSnap.data?.toStringAsFixed(1) ?? '--';
                      final pt = pitchSnap.data?.toStringAsFixed(1) ?? '--';
                      final acc = _sensors.position?.accuracy
                              .toStringAsFixed(0) ??
                          '--';

                      // Compass accuracy: lower = better
                      // FlutterCompass accuracy is in degrees of error
                      final compassAcc = _sensors.compassAccuracy;
                      Color compassColor;
                      if (compassAcc < 0) {
                        compassColor = Colors.grey; // Unknown
                      } else if (compassAcc <= 15) {
                        compassColor = Colors.green; // Good
                      } else if (compassAcc <= 30) {
                        compassColor = Colors.amber; // Fair
                      } else {
                        compassColor = Colors.red; // Poor — recalibrate
                      }

                      return Container(
                        margin: const EdgeInsets.all(12),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 10,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.6),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.08),
                          ),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceAround,
                          children: [
                            _telemetryItem('GPS', '±${acc}m'),
                            Container(
                              width: 1,
                              height: 24,
                              color: Colors.white12,
                            ),
                            // Heading with accuracy dot
                            Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      'HDG',
                                      style: TextStyle(
                                        color: Colors.white.withValues(alpha: 0.35),
                                        fontSize: 10,
                                        fontWeight: FontWeight.w600,
                                        letterSpacing: 1,
                                      ),
                                    ),
                                    const SizedBox(width: 4),
                                    Container(
                                      width: 6,
                                      height: 6,
                                      decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        color: compassColor,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  '$az°',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 14,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
                            ),
                            Container(
                              width: 1,
                              height: 24,
                              color: Colors.white12,
                            ),
                            _telemetryItem('PITCH', '$pt°'),
                          ],
                        ),
                      );
                    },
                  ),
                ),

                const Spacer(),

                // ─── Centre Crosshair ────────────────────────────────
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.4),
                      width: 1.5,
                    ),
                  ),
                  child: Icon(
                    Icons.add,
                    color: Colors.white.withValues(alpha: 0.8),
                    size: 28,
                  ),
                ),

                // Status message
                if (_status.isNotEmpty)
                  Container(
                    margin: const EdgeInsets.only(top: 16),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.7),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      _status,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.7),
                        fontSize: 13,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),

                const Spacer(),

                // ─── Azimuth Offset Slider ───────────────────────────
                if (_showOffsetSlider)
                  Container(
                    margin: const EdgeInsets.symmetric(horizontal: 24),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.7),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      children: [
                        Text(
                          '🧭 Heading Offset: ${_offsetValue.toStringAsFixed(1)}°',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.7),
                            fontSize: 12,
                          ),
                        ),
                        SliderTheme(
                          data: SliderThemeData(
                            activeTrackColor: Colors.deepOrange,
                            thumbColor: Colors.deepOrange,
                            inactiveTrackColor:
                                Colors.white.withValues(alpha: 0.15),
                            overlayColor:
                                Colors.deepOrange.withValues(alpha: 0.2),
                          ),
                          child: Slider(
                            value: _offsetValue,
                            min: -15,
                            max: 15,
                            divisions: 60,
                            onChanged: (v) {
                              setState(() => _offsetValue = v);
                              _sensors.setAzimuthOffset(v);
                            },
                          ),
                        ),
                      ],
                    ),
                  ),

                // ─── Bottom Controls ─────────────────────────────────
                Padding(
                  padding: const EdgeInsets.only(bottom: 40, top: 8),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      // Offset toggle
                      _iconButton(
                        icon: Icons.explore,
                        label: 'Adjust',
                        active: _showOffsetSlider,
                        onTap: () => setState(
                          () => _showOffsetSlider = !_showOffsetSlider,
                        ),
                      ),

                      // Lock button (main action)
                      GestureDetector(
                        onTap: _lock,
                        child: Container(
                          width: 76,
                          height: 76,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: Colors.white,
                              width: 3,
                            ),
                            color: _locking
                                ? Colors.white.withValues(alpha: 0.15)
                                : Colors.transparent,
                          ),
                          child: _locking
                              ? const Padding(
                                  padding: EdgeInsets.all(20),
                                  child: CircularProgressIndicator(
                                    color: Colors.white,
                                    strokeWidth: 2.5,
                                  ),
                                )
                              : const Icon(
                                  Icons.my_location,
                                  color: Colors.white,
                                  size: 32,
                                ),
                        ),
                      ),

                      // Placeholder for symmetry
                      _iconButton(
                        icon: Icons.info_outline,
                        label: 'Info',
                        onTap: () => _showInfoDialog(),
                      ),
                    ],
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
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.35),
              fontSize: 10,
              fontWeight: FontWeight.w600,
              letterSpacing: 1,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      );

  Widget _iconButton({
    required IconData icon,
    required String label,
    bool active = false,
    required VoidCallback onTap,
  }) =>
      GestureDetector(
        onTap: onTap,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              color: active
                  ? Colors.deepOrange
                  : Colors.white.withValues(alpha: 0.5),
              size: 24,
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                color: active
                    ? Colors.deepOrange
                    : Colors.white.withValues(alpha: 0.4),
                fontSize: 10,
              ),
            ),
          ],
        ),
      );

  void _showInfoDialog() {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1A),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          'How to Use',
          style: TextStyle(color: Colors.white),
        ),
        content: Text(
          '1. Point your phone at a distant mountain\n'
          '2. Centre the crosshair on the peak\n'
          '3. Tap the Lock button\n'
          '4. Wait for identification\n\n'
          '🧭 Use "Adjust" if the compass seems off\n'
          '📡 Works best with good mobile signal',
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.6),
            height: 1.6,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Got it'),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _cam?.dispose();
    _sensors.dispose();
    super.dispose();
  }
}

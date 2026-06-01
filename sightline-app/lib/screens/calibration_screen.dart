import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_compass/flutter_compass.dart';
import 'viewfinder_screen.dart';

/// First screen shown on app launch.
///
/// Monitors the phone's magnetometer via FlutterCompass and automatically
/// proceeds to the viewfinder once compass readings stabilize (low variance
/// over a rolling window). The user can also skip calibration manually.
class CalibrationScreen extends StatefulWidget {
  const CalibrationScreen({super.key});

  @override
  State<CalibrationScreen> createState() => _CalibrationScreenState();
}

class _CalibrationScreenState extends State<CalibrationScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _animController;
  late Animation<double> _rotation;

  StreamSubscription? _compassSub;
  final List<double> _headingWindow = []; // Rolling window of recent headings
  static const int _windowSize = 30; // ~30 readings ≈ 3 seconds
  static const double _stableThreshold = 8.0; // Variance below this = stable

  bool _stable = false;
  bool _autoProceeding = false;
  double _variance = 999;
  int _stableCount = 0; // How many consecutive stable readings

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    )..repeat();
    _rotation = Tween(begin: 0.0, end: 6.2832).animate(
      CurvedAnimation(parent: _animController, curve: Curves.linear),
    );
    _startCompassMonitoring();
  }

  void _startCompassMonitoring() {
    _compassSub = FlutterCompass.events?.listen((event) {
      if (event.heading == null) return;

      _headingWindow.add(event.heading!);
      if (_headingWindow.length > _windowSize) {
        _headingWindow.removeAt(0);
      }

      if (_headingWindow.length >= _windowSize) {
        _variance = _circularVariance(_headingWindow);

        if (_variance < _stableThreshold) {
          _stableCount++;
        } else {
          _stableCount = 0;
        }

        // Stable for ~30 consecutive readings ≈ 3 seconds
        final nowStable = _stableCount >= _windowSize;
        if (nowStable && !_stable) {
          _stable = true;
          _animController.stop();
          // Auto-proceed after a brief moment
          _autoProceeding = true;
          Future.delayed(const Duration(milliseconds: 800), () {
            if (mounted && _autoProceeding) _goToViewfinder();
          });
        }

        if (mounted) setState(() {});
      }
    });
  }

  /// Circular variance for heading values (handles 0°/360° wrap).
  double _circularVariance(List<double> headings) {
    double sinSum = 0, cosSum = 0;
    for (final h in headings) {
      sinSum += sin(h * pi / 180);
      cosSum += cos(h * pi / 180);
    }
    sinSum /= headings.length;
    cosSum /= headings.length;
    // R = mean resultant length; variance = 1 - R (scaled to degrees)
    final r = sqrt(sinSum * sinSum + cosSum * cosSum);
    return (1 - r) * 360; // Higher = more scattered
  }

  void _goToViewfinder() {
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => const ViewfinderScreen()),
    );
  }

  String get _statusText {
    if (_stable) return '✅ Compass calibrated!';
    if (_headingWindow.length < _windowSize) return 'Reading compass…';
    if (_variance > 50) return '🔴 Move phone in figure-8 pattern';
    if (_variance > 20) return '🟡 Getting better… keep going';
    return '🟢 Almost stable…';
  }

  Color get _statusColor {
    if (_stable) return Colors.green;
    if (_variance > 50) return Colors.red;
    if (_variance > 20) return Colors.amber;
    return Colors.lightGreen;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D0D0D),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 36),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Animated compass icon (stops spinning when stable)
              AnimatedBuilder(
                animation: _rotation,
                builder: (_, child) => Transform.rotate(
                  angle: _stable ? 0 : _rotation.value,
                  child: child,
                ),
                child: Container(
                  width: 100,
                  height: 100,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: _stable
                          ? Colors.green.withValues(alpha: 0.5)
                          : Colors.deepOrange.withValues(alpha: 0.3),
                      width: 2,
                    ),
                  ),
                  child: Icon(
                    _stable ? Icons.check_circle : Icons.explore,
                    color: _stable ? Colors.green : Colors.deepOrange,
                    size: 56,
                  ),
                ),
              ),

              const SizedBox(height: 48),

              const Text(
                'Calibrate Compass',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 24,
                  fontWeight: FontWeight.w600,
                  letterSpacing: -0.5,
                ),
              ),

              const SizedBox(height: 16),

              Text(
                'Move your phone slowly in a figure-8 motion.\n'
                'The screen will auto-proceed when stable.',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.5),
                  fontSize: 15,
                  height: 1.6,
                ),
                textAlign: TextAlign.center,
              ),

              const SizedBox(height: 24),

              // Live status indicator
              AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: _statusColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: _statusColor.withValues(alpha: 0.3),
                  ),
                ),
                child: Text(
                  _statusText,
                  style: TextStyle(
                    color: _statusColor,
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),

              const SizedBox(height: 12),

              Text(
                'Avoid standing near metal objects or electronics.',
                style: TextStyle(
                  color: Colors.deepOrange.withValues(alpha: 0.6),
                  fontSize: 13,
                  height: 1.6,
                ),
                textAlign: TextAlign.center,
              ),

              const SizedBox(height: 56),

              // Open Camera button (always visible, more prominent when stable)
              FilledButton.icon(
                onPressed: _goToViewfinder,
                icon: const Icon(Icons.camera_alt),
                label: Text(_stable ? 'Open Camera' : 'Skip & Open Camera'),
                style: FilledButton.styleFrom(
                  backgroundColor: _stable
                      ? Colors.green
                      : Colors.white.withValues(alpha: 0.1),
                  foregroundColor: _stable
                      ? Colors.white
                      : Colors.white.withValues(alpha: 0.5),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 32,
                    vertical: 14,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _compassSub?.cancel();
    _animController.dispose();
    super.dispose();
  }
}


import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'screens/calibration_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Lock to portrait mode — sensor math assumes portrait orientation
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
  ]);

  // Dark status bar for immersive camera experience
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
    ),
  );

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
        brightness: Brightness.dark,
        scaffoldBackgroundColor: Colors.black,
      ),
      home: const CalibrationScreen(),
    );
  }
}

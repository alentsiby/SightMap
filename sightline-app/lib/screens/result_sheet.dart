import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:share_plus/share_plus.dart';
import '../models/sighting_result.dart';

/// Bottom sheet that displays the identified peak information.
///
/// Shows: Wikipedia thumbnail, peak name, distance, elevation,
/// Wikipedia description, Navigate button, and Share button.
class ResultSheet extends StatelessWidget {
  final SightingResult result;
  const ResultSheet({super.key, required this.result});

  Future<void> _navigate() async {
    final uri = Uri.parse(
      'google.navigation:q=${result.lat},${result.lng}',
    );
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
      'Elevation: ${result.elevation?.toStringAsFixed(0) ?? "?"} m\n'
      'Coordinates: $lat, $lng\n\n'
      'Identified with SightLine',
    );
  }

  @override
  Widget build(BuildContext context) {
    final peak = result.peak;
    final wiki = result.wiki;

    return DraggableScrollableSheet(
      initialChildSize: 0.55,
      minChildSize: 0.3,
      maxChildSize: 0.9,
      builder: (_, controller) => Container(
        decoration: const BoxDecoration(
          color: Color(0xFF1A1A1A),
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: ListView(
          controller: controller,
          padding: const EdgeInsets.fromLTRB(24, 12, 24, 36),
          children: [
            // Drag handle
            Center(
              child: Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 20),
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),

            // Wikipedia thumbnail
            if (wiki?.thumbnail != null)
              ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: Image.network(
                  wiki!.thumbnail!,
                  height: 180,
                  width: double.infinity,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                ),
              ),

            if (wiki?.thumbnail != null) const SizedBox(height: 20),

            // Peak name
            Text(
              peak?.name ?? 'Identified Location',
              style: const TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w700,
                color: Colors.white,
                letterSpacing: -0.5,
              ),
            ),

            const SizedBox(height: 12),

            // Distance and elevation chips
            Wrap(
              spacing: 8,
              children: [
                if (result.distanceKm != null)
                  _chip('📍 ${result.distanceKm} km away'),
                if (result.elevation != null)
                  _chip('⛰️ ${result.elevation!.toStringAsFixed(0)} m'),
                if (peak?.elevation != null)
                  _chip('🏔️ Peak: ${peak!.elevation} m'),
              ],
            ),

            // Wikipedia description
            if (wiki?.extract != null) ...[
              const SizedBox(height: 20),
              Text(
                wiki!.extract,
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.white.withValues(alpha: 0.6),
                  height: 1.7,
                ),
              ),
            ],

            const SizedBox(height: 28),

            // Navigate button
            FilledButton.icon(
              onPressed: _navigate,
              icon: const Icon(Icons.directions),
              label: const Text('Navigate with Google Maps'),
              style: FilledButton.styleFrom(
                backgroundColor: Colors.deepOrange,
                foregroundColor: Colors.white,
                minimumSize: const Size(double.infinity, 52),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
            ),

            const SizedBox(height: 12),

            // Share button
            OutlinedButton.icon(
              onPressed: _share,
              icon: const Icon(Icons.share),
              label: const Text('Share this sighting'),
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.white70,
                side: const BorderSide(color: Colors.white24),
                minimumSize: const Size(double.infinity, 52),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
            ),

            // Coordinates
            const SizedBox(height: 20),
            Text(
              '${result.lat?.toStringAsFixed(5)}, ${result.lng?.toStringAsFixed(5)}',
              style: TextStyle(
                fontSize: 11,
                color: Colors.white.withValues(alpha: 0.25),
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _chip(String label) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: Colors.white.withValues(alpha: 0.7),
          ),
        ),
      );
}

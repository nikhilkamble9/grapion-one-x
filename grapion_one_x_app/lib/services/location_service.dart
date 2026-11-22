// //Added By Nikhil 22Nov26 20:53 For location check-in (members + staff): one place that asks permission and reads GPS
import 'package:geolocator/geolocator.dart';

/// Result of one location read: either a position or a message the user can act on.
class GpsFix {
  const GpsFix({this.lat, this.lng, this.accuracy, this.error});
  final double? lat;
  final double? lng;
  final double? accuracy;
  final String? error;

  /// Body for the check-in API ({} when there is no position).
  Map<String, dynamic> toJson() => lat == null ? {} : {'lat': lat, 'lng': lng, 'accuracy_m': accuracy};
}

class LocationService {
  /// Asks for "while using the app" permission if needed, then reads the current position (max 20 s).
  /// Never runs in the background. The server decides whether the position is close enough.
  static Future<GpsFix> current() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        return const GpsFix(error: 'Turn on Location on your phone, then tap Check In again.');
      }
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) perm = await Geolocator.requestPermission();
      if (perm == LocationPermission.denied) {
        return const GpsFix(error: 'Allow location so the app can confirm you are at the gym.');
      }
      if (perm == LocationPermission.deniedForever) {
        return const GpsFix(error: 'Location is blocked for this app. Allow it in your phone settings, then try again.');
      }
      final p = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.high, timeLimit: Duration(seconds: 20)),
      );
      return GpsFix(lat: p.latitude, lng: p.longitude, accuracy: p.accuracy);
    } catch (_) {
      return const GpsFix(error: 'Could not read your location. Move near a window or outdoors and try again.');
    }
  }
}

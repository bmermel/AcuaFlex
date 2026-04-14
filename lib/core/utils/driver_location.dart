import 'package:geolocator/geolocator.dart';

/// Intenta obtener la posición actual del dispositivo (conductor).
/// Devuelve null si el servicio está apagado, sin permiso o hay error.
Future<({double lat, double lng})?> tryCaptureDriverLocation() async {
  try {
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) return null;

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) return null;
    }
    if (permission == LocationPermission.deniedForever) return null;

    final position = await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        timeLimit: Duration(seconds: 20),
      ),
    );
    return (lat: position.latitude, lng: position.longitude);
  } catch (_) {
    return null;
  }
}

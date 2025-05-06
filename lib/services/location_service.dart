import 'package:location/location.dart';
import 'package:flutter/foundation.dart'; // For debugPrint

class LocationService {
  final Location _location = Location();

  Future<void> requestInitialLocationPermission() async {
    bool serviceEnabled;
    PermissionStatus permissionGranted;

    // Check if location service is enabled
    serviceEnabled = await _location.serviceEnabled();
    if (!serviceEnabled) {
      serviceEnabled = await _location.requestService();
      if (!serviceEnabled) {
        debugPrint("LocationService: Location services not enabled by user.");
        return; // Exit if service not enabled
      }
    }

    // Check for location permission
    permissionGranted = await _location.hasPermission();
    if (permissionGranted == PermissionStatus.denied) {
      permissionGranted = await _location.requestPermission();
      if (permissionGranted == PermissionStatus.denied) {
        debugPrint("LocationService: Location permission denied by user.");
        return; // Exit if permission denied
      }
    }

    if (permissionGranted == PermissionStatus.deniedForever) {
      debugPrint("LocationService: Location permission permanently denied.");
      return; // Exit if permission permanently denied
    }

    // If we reach here, permission is granted (or was already granted)
    if (permissionGranted == PermissionStatus.granted ||
        permissionGranted == PermissionStatus.grantedLimited) {
      debugPrint("LocationService: Location permission granted.");
    } else {
      debugPrint(
          "LocationService: Location permission status: \$permissionGranted");
    }
  }
}

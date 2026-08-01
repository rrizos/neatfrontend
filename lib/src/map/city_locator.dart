import 'dart:math' as math;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:geolocator/geolocator.dart';

import 'greece_cities.dart';

/// Finds which Greek city the device is in, for the sign-up map.
///
/// This is the one and only place the app touches device location, and it only
/// runs on the sign-up city picker: granting it preselects your city so you
/// just press connect, and refusing it leaves the map exactly as it is. The
/// position is used to pick a name from [greeceCities] and is never stored or
/// sent anywhere.
///
/// Coarse accuracy is deliberate — the answer is a city, so street-level
/// precision would be more intrusive without being more useful.

/// Beyond this, the nearest Greek city is not a meaningful guess — someone
/// abroad should get the plain map rather than a preselected city they have no
/// connection to. Roughly the width of the mainland.
const double _kMaxDistanceMeters = 150000;

/// How long to wait for a fix before giving up and leaving the map alone.
const Duration _kFixTimeout = Duration(seconds: 8);

class CityLocator {
  /// Asks for location permission and resolves the nearest city.
  ///
  /// Returns the city name, or null for every "carry on as before" case: web,
  /// location services switched off, permission refused, no fix in time, or a
  /// position too far from any Greek city. Callers do not need to distinguish
  /// them — each one means "just show the map".
  static Future<String?> detectCity() async {
    if (kIsWeb) return null;
    try {
      if (!await Geolocator.isLocationServiceEnabled()) return null;

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        // The OS prompt appears here, and only here.
        permission = await Geolocator.requestPermission();
      }
      if (permission != LocationPermission.always &&
          permission != LocationPermission.whileInUse) {
        return null;
      }

      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.low,
          timeLimit: _kFixTimeout,
        ),
      );
      return nearestCity(position.latitude, position.longitude)?.name;
    } catch (_) {
      // A refused prompt, a timeout, a device with no location hardware — all
      // of it means the same thing to the caller.
      return null;
    }
  }

  /// The closest city in [greeceCities], or null if the point is further than
  /// [_kMaxDistanceMeters] from all of them.
  static GreeceCity? nearestCity(double latitude, double longitude) {
    GreeceCity? closest;
    var closestDistance = double.infinity;

    for (final city in greeceCities) {
      final distance = _haversineMeters(
        latitude,
        longitude,
        city.latitude,
        city.longitude,
      );
      if (distance < closestDistance) {
        closestDistance = distance;
        closest = city;
      }
    }

    if (closest == null || closestDistance > _kMaxDistanceMeters) return null;
    return closest;
  }
}

const double _kEarthRadiusMeters = 6371000;

double _haversineMeters(double lat1, double lon1, double lat2, double lon2) {
  final dLat = _toRadians(lat2 - lat1);
  final dLon = _toRadians(lon2 - lon1);
  final a = math.pow(math.sin(dLat / 2), 2) +
      math.cos(_toRadians(lat1)) *
          math.cos(_toRadians(lat2)) *
          math.pow(math.sin(dLon / 2), 2);
  return 2 * _kEarthRadiusMeters * math.asin(math.min(1, math.sqrt(a)));
}

double _toRadians(double degrees) => degrees * math.pi / 180;

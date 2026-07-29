import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// A still image of the Greece map overview, for screens that want the map as
/// a backdrop rather than as something to interact with.
///
/// Deliberately not the live map: embedding the interactive platform view
/// behind our own full-screen UI is what left the map unable to pan on iOS. An
/// image has no gestures to lose. The real map is warmed separately
/// (`prewarmCityMap`) and takes over on the screen that actually needs it.
///
/// iOS only — it is backed by MKMapSnapshotter. Everywhere else this returns
/// null and callers fall back to a plain background.
class CityMapSnapshot {
  const CityMapSnapshot._();

  static const _channel = MethodChannel('neat/map_snapshot');

  // One render per size+theme is plenty; the onboarding screen rebuilds often
  // and re-rendering on each build would be pure waste.
  static final Map<String, Uint8List?> _cache = {};
  static final Map<String, Future<Uint8List?>> _inFlight = {};

  static bool get isSupported => !kIsWeb && Platform.isIOS;

  /// Returns PNG bytes, or null when unavailable (unsupported platform, or the
  /// snapshotter failed — offline, for instance, since map tiles are remote).
  static Future<Uint8List?> load({
    required Size size,
    required double devicePixelRatio,
    required bool isDark,
    List<({double latitude, double longitude})> pins = const [],
  }) {
    if (!isSupported || size.width < 2 || size.height < 2) {
      return Future.value();
    }
    final key =
        '${size.width.round()}x${size.height.round()}|$isDark|${pins.length}';
    if (_cache.containsKey(key)) return Future.value(_cache[key]);
    return _inFlight[key] ??= _render(key, size, devicePixelRatio, isDark, pins);
  }

  static Future<Uint8List?> _render(
    String key,
    Size size,
    double devicePixelRatio,
    bool isDark,
    List<({double latitude, double longitude})> pins,
  ) async {
    try {
      final bytes = await _channel.invokeMethod<Uint8List>('snapshot', {
        'width': size.width,
        'height': size.height,
        // Capped: a 3x snapshot of a full screen is a big allocation for a
        // backdrop that ends up dimmed behind text.
        'scale': devicePixelRatio.clamp(1.0, 2.0),
        'isDark': isDark,
        'pins': [
          for (final pin in pins) [pin.latitude, pin.longitude],
        ],
      });
      _cache[key] = bytes;
      return bytes;
    } catch (e) {
      debugPrint('[map_snapshot] $e');
      _cache[key] = null;
      return null;
    } finally {
      _inFlight.remove(key);
    }
  }
}

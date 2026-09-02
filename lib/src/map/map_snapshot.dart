import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'greece_cities.dart';
import 'map_hero_cache.dart';

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
  // and re-rendering on each build would be pure waste. The negative results
  // stay here rather than on disk — a failure is usually "offline right now",
  // which is not worth remembering past this session.
  static final Map<String, Uint8List?> _cache = {};
  static final Map<String, Future<Uint8List?>> _inFlight = {};

  /// Renders the hero ahead of the screen that shows it.
  ///
  /// The snapshot used to be requested when the hero was first built, which is
  /// the one moment it is already too late: the screen is on-screen and the
  /// space where the map goes is empty until the tiles arrive. Called from the
  /// screens before it, the render happens while the user is reading something
  /// else and is already on disk by the time they arrive.
  static Future<void> prewarm({
    required Size size,
    required double devicePixelRatio,
    required bool isDark,
    List<({double latitude, double longitude})> pins = const [],
  }) async {
    await load(
      size: size,
      devicePixelRatio: devicePixelRatio,
      isDark: isDark,
      pins: pins,
    );
  }

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
    // Memory first so a rebuild is synchronous, then disk, then the network.
    final warm = MapHeroCache.memory(key);
    if (warm != null) return Future.value(warm);
    return _inFlight[key] ??= _render(key, size, devicePixelRatio, isDark, pins);
  }

  static Future<Uint8List?> _render(
    String key,
    Size size,
    double devicePixelRatio,
    bool isDark,
    List<({double latitude, double longitude})> pins,
  ) async {
    final stored = await MapHeroCache.read(key);
    if (stored != null) {
      _cache[key] = stored;
      _inFlight.remove(key);
      return stored;
    }
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
      if (bytes != null && bytes.isNotEmpty) {
        unawaited(MapHeroCache.write(key, bytes));
      }
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


/// How much of the screen the onboarding hero takes.
///
/// Shared rather than repeated per screen because the snapshot is cached by
/// the size it was rendered at — a prewarm at a different height is a render
/// nobody ever reads, and the screen still waits.
const double kMapHeroFraction = 0.34;

/// Warms both onboarding heroes for the current theme.
///
/// Two renders, because the two screens ask for different pictures: the
/// city-setup hero has no pins, and the spectator hero has every city dotted
/// on it. They cache separately, so both have to be asked for by name.
///
/// Only the current theme. A render costs a network round trip, and doing all
/// four combinations on a first launch is a lot of somebody's data for a
/// backdrop they may never see in the other theme.
Future<void> prewarmCityMapSnapshot({
  required bool isDark,
  required BuildContext context,
}) async {
  if (!CityMapSnapshot.isSupported) return;
  final media = MediaQuery.of(context);
  final size = Size(media.size.width, media.size.height * kMapHeroFraction);
  await CityMapSnapshot.prewarm(
    size: size,
    devicePixelRatio: media.devicePixelRatio,
    isDark: isDark,
  );
  await CityMapSnapshot.prewarm(
    size: size,
    devicePixelRatio: media.devicePixelRatio,
    isDark: isDark,
    pins: [
      for (final city in greeceCities)
        (latitude: city.latitude, longitude: city.longitude),
    ],
  );
}

import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// The onboarding hero map, kept on disk between launches.
///
/// The hero is a picture of Greece behind the copy on the city-setup and
/// spectator screens. Producing that picture is expensive in a way that is
/// entirely invisible from the widget tree: on iOS it is `MKMapSnapshotter`,
/// which fetches tiles over the network, and on Android it is a WebView
/// booting MapKit JS and fetching the same tiles. Either way the top third of
/// the screen sits empty until the network answers, and it did so on *every*
/// cold start, because the only cache was a static Map that died with the
/// process.
///
/// The picture never changes — it is the same fixed region of the same map at
/// the same two themes — so it only ever needs producing once per device. This
/// keeps it in the cache directory, which makes every launch after the first
/// instant, and lets the OS reclaim the space if it ever needs to.
///
/// Deliberately the *rendered* image rather than a bundled asset: map imagery
/// belongs to the provider and their terms do not allow it to be shipped
/// inside an app. A render the device made for itself, cached where the OS can
/// evict it, is the same thing the app already displays.
class MapHeroCache {
  const MapHeroCache._();

  /// Held in memory too, so a rebuild within one session costs nothing at all.
  static final Map<String, Uint8List> _memory = {};

  static Future<Directory?> _dir() async {
    if (kIsWeb) return null;
    try {
      final base = await getApplicationCacheDirectory();
      final dir = Directory('${base.path}/map_hero');
      if (!await dir.exists()) await dir.create(recursive: true);
      return dir;
    } catch (_) {
      return null;
    }
  }

  /// Filenames are hashed because the key carries sizes and flags, and a
  /// device pixel ratio prints as "3.0" — not something to put in a path.
  static String _fileName(String key) =>
      '${sha1.convert(key.codeUnits)}.png';

  static Uint8List? memory(String key) => _memory[key];

  static Future<Uint8List?> read(String key) async {
    final cached = _memory[key];
    if (cached != null) return cached;
    try {
      final dir = await _dir();
      if (dir == null) return null;
      final file = File('${dir.path}/${_fileName(key)}');
      if (!await file.exists()) return null;
      final bytes = await file.readAsBytes();
      if (bytes.isEmpty) return null;
      _memory[key] = bytes;
      return bytes;
    } catch (_) {
      return null;
    }
  }

  static Future<void> write(String key, Uint8List bytes) async {
    if (bytes.isEmpty) return;
    _memory[key] = bytes;
    try {
      final dir = await _dir();
      if (dir == null) return;
      await File('${dir.path}/${_fileName(key)}').writeAsBytes(bytes);
    } catch (_) {
      // A hero that cannot be cached still renders; it is just slow again
      // next time, which is exactly where this started.
    }
  }
}

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';

// Disk caches for remote media so the feed doesn't re-hit the server every
// time a post scrolls out of view and back in. Entries expire on their own
// (stalePeriod) and the store is capped (maxNrOfCacheObjects), so old media
// gets evicted automatically without any manual "clear cache" step.

final imageCacheManager = CacheManager(
  Config(
    'neatImageCache',
    stalePeriod: const Duration(days: 14),
    maxNrOfCacheObjects: 500,
  ),
);

// Videos are much larger than images, so they get a shorter lifetime and a
// tighter object cap to avoid eating device storage.
final videoCacheManager = CacheManager(
  Config(
    'neatVideoCache',
    stalePeriod: const Duration(days: 3),
    maxNrOfCacheObjects: 25,
  ),
);

/// Resolves [url] to a local cached file. Checks the on-disk cache first so
/// offline playback works without any network attempt when the video was
/// previously downloaded. Falls back to downloading (and caching) when the
/// file isn't cached yet. Returns null on web or on any error.
Future<File?> getCachedVideoFile(String url) async {
  if (kIsWeb) return null;
  try {
    // Local-only lookup — no network request, works offline.
    final cached = await videoCacheManager.getFileFromCache(url);
    if (cached != null) return cached.file;
    // Not cached yet: download and store for future offline use.
    return await videoCacheManager.getSingleFile(url);
  } catch (e) {
    debugPrint('[media_cache] video cache miss for $url: $e');
    return null;
  }
}

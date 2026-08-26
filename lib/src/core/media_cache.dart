import 'dart:async';
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
/// The video's local copy, or null if there isn't one yet.
///
/// Local-only, and deliberately so. This used to fall back to downloading the
/// whole file and returning it, which meant the first view of a video showed
/// nothing at all until every byte had arrived — nine seconds for a six-second
/// clip on a phone connection, when streaming can start playing in about one.
/// A miss now returns null so the caller streams instead, and [warmVideoCache]
/// fills the cache for next time.
Future<File?> getCachedVideoFile(String url) async {
  if (kIsWeb) return null;
  try {
    final cached = await videoCacheManager.getFileFromCache(url);
    return cached?.file;
  } catch (e) {
    debugPrint('[media_cache] video cache lookup failed for $url: $e');
    return null;
  }
}

/// Downloads [url] into the cache in the background, so a later view of the
/// same video plays instantly from disk.
///
/// Costs a second copy of the file on the first view, which is why it is
/// started only once playback is already underway: the bytes are spent while
/// somebody is watching rather than while they wait.
void warmVideoCache(String url) {
  if (kIsWeb || url.isEmpty || url.startsWith('data:')) return;
  unawaited(() async {
    try {
      await videoCacheManager.getSingleFile(url);
    } catch (e) {
      // Nothing to recover: the video already played from the network, and
      // the only cost is that the next view streams again.
      debugPrint('[media_cache] warm failed for $url: $e');
    }
  }());
}

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../core/api.dart';
import '../core/http_client.dart' as http;

/// The bytes behind a photo or voice note in a conversation.
///
/// DM media is base64 inside the message row, so a thread that used to arrive
/// with every picture in it took megabytes and seconds to open. The server now
/// sends the message without its payload and this fetches the bytes when a
/// bubble is actually drawn (or a voice note played) — once per message, then
/// from memory, then from disk on the next launch.
///
/// Never used for "view once" photos: those cost a viewing to open, so they go
/// through the open endpoint instead.
class DmMedia {
  const DmMedia._();

  /// Small enough to keep a scrolled-through conversation snappy without
  /// holding every photo of a long chat in RAM. Disk keeps the rest.
  static const _memoryLimit = 30;

  static final Map<int, Uint8List> _memory = {};
  static final List<int> _order = [];
  static final Map<int, Future<Uint8List?>> _inFlight = {};

  /// Bytes already in memory, if any — lets a bubble paint on its first frame
  /// instead of flashing a placeholder every time it scrolls back into view.
  static Uint8List? cached(int messageId) => _memory[messageId];

  /// Warms the cache for [messageIds] without waiting for their bubbles.
  ///
  /// A photo used to start downloading only when its bubble was first built,
  /// which is a beat *after* the thread has painted — so opening a chat showed
  /// a column of grey squares that filled in one by one. The ids are already
  /// known the moment the thread arrives, so the fetches can start then.
  ///
  /// Deliberately shallow and deliberately serial-ish: [_prefetchLimit] covers
  /// what a reader can reach in the first few flicks, and [_prefetchWidth]
  /// keeps those requests from competing with the one photo the reader is
  /// actually looking at — on a slow connection, four parallel downloads make
  /// every one of them late. Already-cached ids cost nothing, and anything not
  /// covered still loads the old way when its bubble appears.
  static const _prefetchLimit = 12;
  static const _prefetchWidth = 2;

  static void prefetch({
    required String token,
    required int conversationId,
    required Iterable<int> messageIds,
  }) {
    final pending = messageIds
        .where((id) => id > 0)
        .where((id) => !_memory.containsKey(id) && !_inFlight.containsKey(id))
        .take(_prefetchLimit)
        .toList();
    if (pending.isEmpty) return;

    for (var lane = 0; lane < _prefetchWidth; lane++) {
      final ids = <int>[];
      for (var i = lane; i < pending.length; i += _prefetchWidth) {
        ids.add(pending[i]);
      }
      unawaited(_drain(token, conversationId, ids));
    }
  }

  static Future<void> _drain(
    String token,
    int conversationId,
    List<int> ids,
  ) async {
    for (final id in ids) {
      // Re-checked per id: a bubble scrolled into view mid-drain may already
      // have started (or finished) this one.
      if (_memory.containsKey(id)) continue;
      await load(token: token, conversationId: conversationId, messageId: id);
    }
  }

  static Future<Uint8List?> load({
    required String token,
    required int conversationId,
    required int messageId,
  }) {
    final cached = _memory[messageId];
    if (cached != null) return Future.value(cached);
    // One fetch per message even if several widgets ask at once — the bubble
    // and the fullscreen viewer routinely both want it.
    return _inFlight[messageId] ??= _fetch(
      token: token,
      conversationId: conversationId,
      messageId: messageId,
    ).whenComplete(() => _inFlight.remove(messageId));
  }

  static Future<Uint8List?> _fetch({
    required String token,
    required int conversationId,
    required int messageId,
  }) async {
    final onDisk = await _readFile(messageId);
    if (onDisk != null) {
      _remember(messageId, onDisk);
      return onDisk;
    }
    try {
      final res = await http.get(
        messageMediaEndpoint(conversationId, messageId),
        headers: authGetHeaders(token),
      );
      if (res.statusCode != 200) return null;
      final body = jsonDecode(res.body) as Map<String, dynamic>;

      // Two shapes. The server now stores DM media as files and answers with a
      // URL; it still answers older builds with the bytes inline, so both have
      // to be understood here — this same client talks to both while a release
      // is rolling out.
      Uint8List? bytes;
      final url = body['url']?.toString() ?? '';
      if (url.isNotEmpty) {
        final file = await http.get(Uri.parse(url));
        if (file.statusCode != 200 || file.bodyBytes.isEmpty) return null;
        bytes = file.bodyBytes;
      } else {
        bytes = payloadBytes(body['text']?.toString() ?? '');
      }
      if (bytes == null || bytes.isEmpty) return null;
      _remember(messageId, bytes);
      unawaited(_writeFile(messageId, bytes));
      return bytes;
    } catch (e) {
      debugPrint('[dm_media] $messageId: $e');
      return null;
    }
  }

  /// The base64 segment of a `__neat_image__:` / `__neat_voice__:` payload,
  /// decoded. A voice note carries `|<seconds>` after its bytes.
  static Uint8List? payloadBytes(String payload) {
    final colon = payload.indexOf(':');
    if (colon < 0) return null;
    var data = payload.substring(colon + 1);
    final bar = data.lastIndexOf('|');
    if (bar >= 0) data = data.substring(0, bar);
    if (data.isEmpty) return null;
    try {
      return base64Decode(data);
    } catch (_) {
      return null;
    }
  }

  static void _remember(int messageId, Uint8List bytes) {
    if (!_memory.containsKey(messageId)) _order.add(messageId);
    _memory[messageId] = bytes;
    while (_order.length > _memoryLimit) {
      _memory.remove(_order.removeAt(0));
    }
  }

  // ── Disk ───────────────────────────────────────────────────────────────────
  //
  // A message's media never changes, so a hit here is always valid and the
  // cache needs no expiry logic — only the eviction the OS does for us when it
  // reclaims the cache directory.

  static Future<Directory?> _dir() async {
    if (kIsWeb) return null;
    try {
      final base = await getApplicationCacheDirectory();
      final dir = Directory('${base.path}/dm_media');
      if (!await dir.exists()) await dir.create(recursive: true);
      return dir;
    } catch (_) {
      return null;
    }
  }

  static Future<Uint8List?> _readFile(int messageId) async {
    try {
      final dir = await _dir();
      if (dir == null) return null;
      final file = File('${dir.path}/$messageId.bin');
      if (!await file.exists()) return null;
      return await file.readAsBytes();
    } catch (_) {
      return null;
    }
  }

  static Future<void> _writeFile(int messageId, Uint8List bytes) async {
    try {
      final dir = await _dir();
      if (dir == null) return;
      await File('${dir.path}/$messageId.bin').writeAsBytes(bytes, flush: false);
    } catch (_) {}
  }
}

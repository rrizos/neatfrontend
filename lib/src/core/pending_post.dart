import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import 'api.dart';
import 'background_upload.dart';
import 'http_client.dart' as http;

/// A post whose media was handed to the system to upload, kept on disk until
/// the post itself exists on the server.
///
/// The upload surviving the app being killed is only half of it. The bytes
/// land, the system relaunches the app to say so — and without this there is
/// nothing left that remembers a post was meant to be made from them. The
/// caption, the poll and which uploads belong together are written down before
/// the app can be taken away, and the post is finished from that record on
/// whichever launch hears the uploads finish.
///
/// Deliberately narrow: only posts with a background upload in flight go
/// through here. Everything else is delivered inline as it always was, because
/// a post with no large file to move has nothing to survive.
class PendingPostQueue {
  const PendingPostQueue._();

  static const _fileName = 'pending_post.json';

  /// Set by the feed so a post finished from here can be shown at once.
  static void Function()? onPosted;

  static Future<File> _file() async {
    final dir = await getApplicationSupportDirectory();
    return File('${dir.path}/$_fileName');
  }

  /// Writes down a post that is waiting on background uploads.
  ///
  /// [uploads] maps the name each file was enqueued under to its place in the
  /// media list, so a result can be put back where it belongs.
  static Future<void> remember({
    required String token,
    required String text,
    required List<Map<String, dynamic>> media,
    required Map<String, int> uploads,
    List<String> pollOptions = const [],
  }) async {
    try {
      final file = await _file();
      await file.writeAsString(jsonEncode({
        'token': token,
        'text': text,
        'media': media,
        'uploads': uploads,
        'poll': pollOptions,
        'saved': DateTime.now().toIso8601String(),
      }));
      debugPrint('[pending-post] remembered, waiting on ${uploads.length} upload(s)');
    } catch (e) {
      debugPrint('[pending-post] could not remember: $e');
    }
  }

  static Future<void> forget() async {
    try {
      final file = await _file();
      if (await file.exists()) await file.delete();
    } catch (_) {}
  }

  /// Collects any finished uploads and posts if everything has arrived.
  ///
  /// Safe to call as often as convenient — on launch, and whenever the app
  /// comes back to the foreground.
  static Future<void> settle() async {
    if (!BackgroundUpload.supported) return;
    Map<String, dynamic> saved;
    try {
      final file = await _file();
      if (!await file.exists()) {
        // Nothing waiting, but results may still be sitting there from an
        // upload whose post was abandoned; clearing keeps them from piling up.
        await BackgroundUpload.drain();
        return;
      }
      saved = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
    } catch (e) {
      debugPrint('[pending-post] unreadable, dropping: $e');
      await forget();
      return;
    }

    final results = await BackgroundUpload.drain();
    if (results.isEmpty) return;

    final media = (saved['media'] as List).cast<Map>().map(
        (m) => Map<String, dynamic>.from(m)).toList();
    final uploads = Map<String, int>.from(
        (saved['uploads'] as Map).map((k, v) => MapEntry(k.toString(), v as int)));

    for (final r in results) {
      final index = uploads[r.name];
      if (index == null || index >= media.length) continue;
      if (!r.ok) {
        // The file never landed, so the post can never be completed from it.
        debugPrint('[pending-post] upload ${r.name} failed (${r.status}); dropping post');
        await forget();
        return;
      }
      try {
        final id = (jsonDecode(r.body) as Map<String, dynamic>)['id']?.toString();
        if (id == null) throw const FormatException('no id');
        media[index]['upload_id'] = id;
        media[index].remove('file_index');
      } catch (e) {
        debugPrint('[pending-post] unreadable upload reply; dropping post: $e');
        await forget();
        return;
      }
      uploads.remove(r.name);
    }

    if (uploads.isNotEmpty) {
      // Some files are still going; keep what has been resolved so far.
      await remember(
        token: saved['token'] as String,
        text: saved['text'] as String,
        media: media,
        uploads: uploads,
        pollOptions: (saved['poll'] as List).cast<String>(),
      );
      return;
    }

    await _send(saved, media);
  }

  static Future<void> _send(
      Map<String, dynamic> saved, List<Map<String, dynamic>> media) async {
    final token = saved['token'] as String;
    try {
      final request = http.MultipartRequest('POST', postsEndpoint())
        ..headers['Authorization'] = 'Token $token'
        ..fields['text'] = saved['text'] as String
        ..fields['media'] = jsonEncode(media);
      final poll = (saved['poll'] as List).cast<String>();
      if (poll.isNotEmpty) {
        request.fields['poll'] = jsonEncode({'options': poll});
      }
      final res = await http.Response.fromStream(
        await request.send().timeout(const Duration(seconds: 120)),
      );
      if (res.statusCode == 201) {
        debugPrint('[pending-post] posted');
        await forget();
        onPosted?.call();
      } else {
        // A refusal will not become an acceptance on a retry.
        debugPrint('[pending-post] server refused ${res.statusCode}; dropping');
        await forget();
      }
    } catch (e) {
      // Kept for the next attempt: this is a network failure, not a refusal.
      debugPrint('[pending-post] send failed, will retry: $e');
    }
  }
}

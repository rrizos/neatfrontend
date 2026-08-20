import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import 'api.dart';
import 'avatar_store.dart';
import 'http_client.dart' as http;
import 'models.dart';

/// A profile save that keeps trying until the server has it.
///
/// The old flow waited for a 200 before showing anything: pick a picture, press
/// Save, and the app sat on the network before updating a single pixel. On a
/// weak connection that meant one of two bad outcomes — the request died and
/// the change was lost, or it quietly succeeded while the app, never having
/// heard back, went on showing the old photo until the next restart.
///
/// Neither is really about uploading. They are about treating the server round
/// trip as the moment the change becomes true. So it isn't:
///
///  * **The picture is applied locally the instant Save is pressed.** The bytes
///    are already on the device; nothing about showing them needs a network.
///    [AvatarStore] pushes them to the feed, the profile, comments and the chat
///    list on that frame, which is why it now looks identical on a bad
///    connection and a good one.
///  * **The upload is written to disk first, then retried until it lands.**
///    Backoff while the app is open, again when it is reopened. Killing the app
///    mid-upload does not lose the change; it resumes on next launch.
///
/// The server's own copy replaces the local one when it eventually answers —
/// it re-encodes avatars, so its version is the canonical one — but by then the
/// user stopped waiting long ago.
class ProfileSaveQueue {
  const ProfileSaveQueue._();

  static const _fileName = 'pending_profile_save.json';
  static const _imageName = 'pending_profile_avatar.jpg';

  /// True while a save is still owed to the server. UI can show a quiet
  /// "syncing" hint off this; nothing is blocked by it.
  static final ValueNotifier<bool> pending = ValueNotifier<bool>(false);

  static Timer? _retryTimer;
  static bool _sending = false;
  static Future<void>? _inFlight;

  /// Swapped out in tests so the queue's behaviour can be exercised without a
  /// network — and, more importantly, without a test accidentally reaching the
  /// live server, which is exactly what happened the first time this was
  /// written against the real endpoint.
  @visibleForTesting
  static Future<http.Response> Function(String token, String body)? sendOverride;

  /// Deliberately long and finite. A connection that has been unusable for
  /// this many attempts is not going to be fixed by a tighter loop, and the
  /// job survives on disk for the next launch either way.
  static const _backoff = [
    Duration(seconds: 3),
    Duration(seconds: 10),
    Duration(seconds: 30),
    Duration(minutes: 2),
    Duration(minutes: 5),
  ];

  static Future<File> _jobFile() async {
    // Application *support*, not cache: the OS may evict a cache directory
    // whenever it likes, and this is the only copy of a change the user
    // believes they have made.
    final dir = await getApplicationSupportDirectory();
    return File('${dir.path}/$_fileName');
  }

  /// Records a save and starts trying to deliver it. Returns immediately.
  ///
  /// [imageBytes], when given, is uploaded as a binary file rather than
  /// base64 inside the JSON — a third fewer bytes on the largest thing the app
  /// sends, over the connection least able to carry it. Written next to the
  /// job so it survives the app being killed just as the job does.
  static Future<void> enqueue({
    required String token,
    required Map<String, dynamic> body,
    required String username,
    required String previousAvatarUrl,
    Uint8List? imageBytes,
  }) async {
    try {
      final file = await _jobFile();
      String? imagePath;
      if (imageBytes != null && imageBytes.isNotEmpty) {
        final dir = await getApplicationSupportDirectory();
        final image = File('${dir.path}/$_imageName');
        await image.writeAsBytes(imageBytes, flush: true);
        imagePath = image.path;
      }
      await file.writeAsString(jsonEncode({
        'body': body,
        'username': username,
        'previousAvatarUrl': previousAvatarUrl,
        'imagePath': imagePath,
        'queuedAt': DateTime.now().toIso8601String(),
      }));
      pending.value = true;
    } catch (e) {
      debugPrint('[profile-queue] could not persist: $e');
      // Still worth attempting in memory rather than dropping the change.
    }
    _inFlight = _attempt(token, attempt: 0);
    unawaited(_inFlight);
  }

  /// Retries anything still owed. Safe to call on every launch and resume.
  static Future<void> retryPending(String token) async {
    if (_sending) return;
    try {
      final file = await _jobFile();
      if (!await file.exists()) {
        pending.value = false;
        return;
      }
      pending.value = true;
      await _attempt(token, attempt: 0);
    } catch (_) {}
  }

  static Future<void> _attempt(String token, {required int attempt}) async {
    if (_sending) return;
    _sending = true;
    _retryTimer?.cancel();
    try {
      final file = await _jobFile();
      if (!await file.exists()) {
        pending.value = false;
        return;
      }
      final job = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      final body = Map<String, dynamic>.from(job['body'] as Map);

      final imagePath = job['imagePath']?.toString() ?? '';
      http.Response res;
      try {
        final encoded = jsonEncode(body);
        if (sendOverride != null) {
          res = await sendOverride!(token, encoded);
        } else if (imagePath.isNotEmpty && await File(imagePath).exists()) {
          res = await _sendMultipart(token, body, imagePath);
        } else {
          res = await http
              .patch(meEndpoint, headers: authJsonHeaders(token), body: encoded)
              .timeout(const Duration(seconds: 150));
        }
      } catch (e) {
        debugPrint('[profile-queue] attempt ${attempt + 1}: ${e.runtimeType}');
        _scheduleRetry(token, attempt);
        return;
      }

      if (res.statusCode == 200) {
        await _finish(file, res.body, job);
        return;
      }
      // A refusal is an answer: the same request will be refused again, and
      // retrying a 400 forever would keep claiming a save that cannot happen.
      // 401 included — the token is no longer good, and the sign-in flow is
      // what fixes that, not this queue.
      if (res.statusCode >= 400 && res.statusCode < 500) {
        debugPrint('[profile-queue] server refused ${res.statusCode}; dropping');
        await _discard(file);
        return;
      }
      _scheduleRetry(token, attempt);
    } catch (e) {
      debugPrint('[profile-queue] unexpected: $e');
      _scheduleRetry(token, attempt);
    } finally {
      _sending = false;
    }
  }

  static Future<void> _finish(
    File file,
    String responseBody,
    Map<String, dynamic> job,
  ) async {
    try {
      final decoded = jsonDecode(responseBody) as Map<String, dynamic>;
      final userJson = Map<String, dynamic>.from(
        decoded['user'] as Map<String, dynamic>,
      );
      final saved = UserProfile.fromJson(userJson);
      // Swap the local copy for the server's, which is the re-encoded one every
      // other device will see. Usually invisible; it keeps them identical.
      if (saved.avatarUrl.isNotEmpty) {
        AvatarStore.update(
          username: saved.username,
          previousUrl: job['previousAvatarUrl']?.toString() ?? '',
          url: saved.avatarUrl,
        );
      }
      onSaved?.call(saved);
      debugPrint('[profile-queue] delivered');
    } catch (e) {
      debugPrint('[profile-queue] delivered but response unreadable: $e');
    }
    await _discard(file);
  }

  /// PATCHes the profile with the picture as a binary part.
  static Future<http.Response> _sendMultipart(
    String token,
    Map<String, dynamic> body,
    String imagePath,
  ) async {
    final request = http.MultipartRequest('PATCH', meEndpoint)
      ..headers.addAll(authGetHeaders(token));
    body.forEach((key, value) {
      // The avatar travels as the file part, never as a field.
      if (key == 'avatarUrl') return;
      request.fields[key] = value is String ? value : jsonEncode(value);
    });
    request.files.add(
      await http.MultipartFile.fromPath('avatar', imagePath, filename: 'avatar.jpg'),
    );
    final streamed =
        await request.send().timeout(const Duration(seconds: 150));
    return http.Response.fromStream(streamed);
  }

  static Future<void> _discard(File file) async {
    try {
      if (await file.exists()) await file.delete();
      final dir = await getApplicationSupportDirectory();
      final image = File('${dir.path}/$_imageName');
      if (await image.exists()) await image.delete();
    } catch (_) {}
    pending.value = false;
  }

  static void _scheduleRetry(String token, int attempt) {
    if (attempt >= _backoff.length) {
      // Out of attempts for now, but the job stays on disk: reopening the app
      // (or saving anything else) picks it up again.
      debugPrint('[profile-queue] pausing; job kept for next launch');
      return;
    }
    _retryTimer?.cancel();
    _retryTimer = Timer(_backoff[attempt], () {
      unawaited(_attempt(token, attempt: attempt + 1));
    });
  }

  /// Notified when a queued save finally lands, so the session can be updated
  /// from wherever the app keeps it.
  static ValueChanged<UserProfile>? onSaved;

  /// Awaits the attempt currently in flight, if any. Tests only — production
  /// code never waits on this queue, which is the entire point of it.
  @visibleForTesting
  static Future<void> settle() async {
    await _inFlight;
    _inFlight = null;
  }

  @visibleForTesting
  static Future<void> reset() async {
    sendOverride = null;
    _inFlight = null;
    _retryTimer?.cancel();
    _retryTimer = null;
    _sending = false;
    pending.value = false;
    try {
      final file = await _jobFile();
      if (await file.exists()) await file.delete();
    } catch (_) {}
  }
}

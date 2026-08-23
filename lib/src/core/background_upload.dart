import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb, debugPrint;
import 'package:flutter/services.dart';

/// One finished background upload, as the system reported it.
class BackgroundUploadResult {
  const BackgroundUploadResult({
    required this.name,
    required this.status,
    required this.body,
  });

  /// The id the upload was enqueued under.
  final String name;

  /// HTTP status, or -1 when the transfer itself failed.
  final int status;
  final String body;

  bool get ok => status == 200 || status == 201;
}

/// Uploads handed to iOS to finish on its own.
///
/// A request made from inside the app dies when the app is suspended, so
/// leaving mid-post lost the transfer. These are run by the system instead:
/// they continue while the app is in the background, survive it being killed,
/// and the app is relaunched to be told the outcome.
///
/// Results are not delivered as a callback, because there may be nothing
/// running to receive one. They accumulate natively and are collected by
/// [drain] whenever the app next runs.
///
/// iOS only. On Android a process with a live request is not suspended the same
/// way, so the channel is absent and everything here quietly does nothing.
class BackgroundUpload {
  const BackgroundUpload._();

  static const _channel = MethodChannel('com.neat/bgupload');

  static bool get supported => !kIsWeb && Platform.isIOS;

  static final Map<String, void Function(double)> _progress = {};
  static final Map<String, void Function(BackgroundUploadResult)> _done = {};
  static bool _listening = false;

  /// Starts hearing progress and completions for uploads started this launch.
  ///
  /// Only ever an optimisation: everything reported this way is also written
  /// down natively, so an upload that finishes while the app is dead is picked
  /// up by [drain] on the next launch instead.
  static void _listen() {
    if (_listening || !supported) return;
    _listening = true;
    _channel.setMethodCallHandler((call) async {
      final args = (call.arguments as Map?) ?? const {};
      final name = args['name']?.toString() ?? '';
      if (name.isEmpty) return null;
      switch (call.method) {
        case 'progress':
          _progress[name]?.call((args['value'] as num?)?.toDouble() ?? 0);
        case 'done':
          final result = BackgroundUploadResult(
            name: name,
            status: (args['status'] as num?)?.toInt() ?? -1,
            body: args['body']?.toString() ?? '',
          );
          _progress.remove(name);
          _done.remove(name)?.call(result);
      }
      return null;
    });
  }

  /// Watches [name] for as long as this launch lasts.
  static void watch(
    String name, {
    void Function(double)? onProgress,
    void Function(BackgroundUploadResult)? onDone,
  }) {
    if (!supported) return;
    _listen();
    if (onProgress != null) _progress[name] = onProgress;
    if (onDone != null) _done[name] = onDone;
  }

  static void unwatch(String name) {
    _progress.remove(name);
    _done.remove(name);
  }

  /// Hands [filePath] to the system to POST at [url] as multipart.
  ///
  /// Returns false if it could not be started, in which case the caller should
  /// fall back to an ordinary in-app upload.
  static Future<bool> enqueue({
    required String name,
    required Uri url,
    required Map<String, String> headers,
    required String filePath,
    String field = 'file',
    String fileName = 'upload.bin',
    Map<String, String> fields = const {},
  }) async {
    if (!supported) {
      lastFailure = 'unsupported-platform';
      return false;
    }
    try {
      final reason = await _channel.invokeMethod<String>('enqueue', {
        'name': name,
        'url': url.toString(),
        'headers': headers,
        'filePath': filePath,
        'field': field,
        'fileName': fileName,
        'fields': fields,
      });
      if (reason == 'ok') {
        lastFailure = null;
        return true;
      }
      lastFailure = reason ?? 'no-answer';
      debugPrint('[bg-upload] handover refused: $lastFailure');
      return false;
    } on MissingPluginException {
      // The native half is not in this build at all — worth telling apart from
      // a transfer that could not be started, because the cures differ.
      lastFailure = 'channel-missing';
      debugPrint('[bg-upload] channel missing');
      return false;
    } catch (e) {
      lastFailure = 'error: $e';
      debugPrint('[bg-upload] enqueue failed: $e');
      return false;
    }
  }

  /// Why the last handover did not happen. Null after a successful one.
  ///
  /// Kept because the fallback is silent by design — the upload still goes,
  /// just from inside the app — and a silent fallback is indistinguishable
  /// from the feature working until someone walks away mid-post.
  static String? lastFailure;

  /// Everything that has finished since the last call. Collecting also clears.
  static Future<List<BackgroundUploadResult>> drain() async {
    if (!supported) return const [];
    try {
      final raw = await _channel.invokeMethod<List<Object?>>('drain');
      if (raw == null) return const [];
      return raw
          .whereType<Map>()
          .map((m) => BackgroundUploadResult(
                name: m['name']?.toString() ?? '',
                status: (m['status'] as num?)?.toInt() ?? -1,
                body: m['body']?.toString() ?? '',
              ))
          .where((r) => r.name.isNotEmpty)
          .toList();
    } catch (e) {
      debugPrint('[bg-upload] drain failed: $e');
      return const [];
    }
  }
}

import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb, debugPrint;
import 'package:flutter/services.dart';

/// Asks iOS to keep the app running while something is uploading.
///
/// Leaving the app suspends the process, and a suspended process has its
/// sockets torn down — which is why walking away part-way through a post lost
/// the upload and left it to be started again. A background task assertion
/// tells iOS the app has work to finish; it grants roughly thirty seconds
/// after the app leaves the screen, which at this app's measured upload speed
/// (about 1 MB/s) covers a typical compressed video.
///
/// Not a guarantee. A large upload can still be cut short when the assertion
/// expires. The complete answer is a background `URLSession`, which the system
/// continues out of process even if the app is killed, and that is a much
/// larger change than this.
///
/// Android needs none of this: a process with a live network request is not
/// suspended the same way, so the channel simply is not there and every call
/// here does nothing.
class UploadTask {
  const UploadTask._();

  static const _channel = MethodChannel('com.neat/uploadtask');

  static bool get _supported => !kIsWeb && Platform.isIOS;

  /// Holds an assertion under [name] until [end] is called with the same name.
  static Future<void> begin(String name) async {
    if (!_supported) return;
    try {
      await _channel.invokeMethod<bool>('begin', name);
    } catch (e) {
      // Never fatal: without the assertion the upload behaves exactly as it
      // did before, which is to say it stops when the app is put away.
      debugPrint('[upload-task] begin failed: $e');
    }
  }

  /// Releases the assertion. Safe to call when none is held.
  ///
  /// Must always run — iOS terminates an app that leaves assertions
  /// outstanding — so callers put it in a `finally`.
  static Future<void> end(String name) async {
    if (!_supported) return;
    try {
      await _channel.invokeMethod<void>('end', name);
    } catch (e) {
      debugPrint('[upload-task] end failed: $e');
    }
  }
}

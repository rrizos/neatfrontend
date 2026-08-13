import 'package:flutter/foundation.dart';
import 'package:shorebird_code_push/shorebird_code_push.dart';

/// Over-the-air Dart updates (Shorebird).
///
/// Shorebird patches the Dart code of an already-installed build, so a fix
/// reaches people without an App Store or Play review. The rules it works
/// under, and the reason this class is as quiet as it is:
///
///  * A patch only applies to the *release* it was cut from. Ship a new
///    version to the stores and its patch line starts again from zero.
///  * A downloaded patch is booted on the next cold start, never mid-session
///    — there is no way to swap the running Dart code out from under a live
///    screen, so nothing here asks the user to restart. They will get the fix
///    the next time they open the app, which for a social app is soon.
///  * Nothing waits on the network before the first frame. The check runs
///    fire-and-forget from [main], exactly like push and link-preview restore.
///
/// In a build that was not produced by `shorebird release` — a debug run, a
/// plain `flutter build`, the web app — [ShorebirdUpdater] reports itself
/// unavailable and every call below turns into a no-op.
class CodePushService {
  CodePushService._();

  static final CodePushService instance = CodePushService._();

  final _updater = ShorebirdUpdater();

  /// The patch running right now, or null on a release with no patch applied.
  /// Shown in Settings so a bug report can say which code was actually on the
  /// device — the store version number alone no longer answers that.
  Future<int?> currentPatchNumber() async {
    try {
      final patch = await _updater.readCurrentPatch();
      return patch?.number;
    } catch (e) {
      debugPrint('[codepush] readCurrentPatch: $e');
      return null;
    }
  }

  /// Checks for a new patch and downloads it if there is one.
  ///
  /// Safe to call on every launch: it is one small request, and it exits
  /// immediately when the updater is unavailable.
  Future<void> checkForUpdate() async {
    if (!_updater.isAvailable) return;
    try {
      final status = await _updater.checkForUpdate();
      if (status != UpdateStatus.outdated) return;
      await _updater.update();
      debugPrint('[codepush] patch downloaded, live on next launch');
    } on UpdateException catch (e) {
      // A failed download is not worth surfacing: the app on the device is
      // the last good build and the next launch simply tries again.
      debugPrint('[codepush] update failed: ${e.message}');
    } catch (e) {
      debugPrint('[codepush] update failed: $e');
    }
  }
}

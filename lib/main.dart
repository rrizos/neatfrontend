import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:giphy_flutter_sdk/giphy_flutter_sdk.dart';

import 'src/app.dart';
import 'src/core/code_push_service.dart';
import 'src/core/link_preview.dart';
import 'src/core/pinned_http.dart';
import 'src/core/push_service.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  setupPinnedHttpOverrides();
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.white,
      statusBarIconBrightness: Brightness.dark,
      systemNavigationBarColor: Colors.white,
      systemNavigationBarIconBrightness: Brightness.dark,
    ),
  );
  if (!kIsWeb) {
    GiphyFlutterSDK.configure(
      apiKey: Platform.isIOS
          ? 'phQaZvEZeoJTE7GqZ2LnOxUAXWMyEPbM'
          : 'dmecPhhlED6LaEOrcnBOjVGYOQd62EYj',
    );

    // Fire-and-forget: Firebase/push setup must never block the first frame.
    // Requesting notification permission before the app is on screen has
    // also been known to hang the native launch screen on iOS. PushService.
    // init() is the single gate (Firebase.initializeApp() included) that
    // registerForSession() also awaits, so an auto-login racing this on cold
    // start can't hit FirebaseMessaging before Firebase itself is ready.
    unawaited(PushService.instance.init());

    // Also fire-and-forget: reading last session's link cards is a single
    // small file, and it finishes long before the first feed response lands,
    // so cards paint from it rather than re-earning every one over the
    // network. A slow or failed read only means a slower start.
    unawaited(LinkPreviewService.instance.restore());

    // Fire-and-forget for the same reason: a code-push patch is booted on the
    // next cold start, so there is nothing to wait for now — and a slow
    // network must never be something the first frame is behind.
    unawaited(CodePushService.instance.checkForUpdate());
  }
  runApp(const NeatApp());
}

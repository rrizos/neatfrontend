import 'dart:async';
import 'dart:io';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:giphy_flutter_sdk/giphy_flutter_sdk.dart';

import 'src/app.dart';
import 'src/core/push_service.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
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
    // also been known to hang the native launch screen on iOS.
    unawaited(_initPush());
  }
  runApp(const NeatApp());
}

Future<void> _initPush() async {
  try {
    await Firebase.initializeApp();
    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
    await PushService.instance.init();
  } catch (_) {}
}

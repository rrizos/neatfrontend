import 'dart:io';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:giphy_flutter_sdk/giphy_flutter_sdk.dart';

import 'src/app.dart';
import 'src/core/push_service.dart';

void main() async {
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
    await Firebase.initializeApp();
    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
    await PushService.instance.init();
  }
  runApp(const NeatApp());
}

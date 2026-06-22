import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:giphy_flutter_sdk/giphy_flutter_sdk.dart';

import 'src/app.dart';

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
  GiphyFlutterSDK.configure(
    apiKey: Platform.isIOS
        ? 'phQaZvEZeoJTE7GqZ2LnOxUAXWMyEPbM'
        : 'dmecPhhlED6LaEOrcnBOjVGYOQd62EYj',
  );
  runApp(const NeatApp());
}

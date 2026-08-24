import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../l10n/app_localizations.dart';
import 'core/avatar_store.dart';
import 'auth/auth_gate.dart';
import 'core/neat_loader.dart';
import 'core/post_deep_link_page.dart';

class NeatApp extends StatefulWidget {
  const NeatApp({super.key});

  static final navigatorKey = GlobalKey<NavigatorState>();

  // The app's active language. Defaults to Greek; the user can switch it from
  // Settings. The chosen locale is persisted and restored on launch, and the
  // notifier lets Settings flip the whole app without threading a callback
  // through every screen.
  static const _localeKey = 'neat_locale';
  static final ValueNotifier<Locale> localeNotifier =
      ValueNotifier<Locale>(const Locale('el'));

  static Future<void> setLocale(Locale locale) async {
    localeNotifier.value = locale;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_localeKey, locale.languageCode);
  }

  @override
  State<NeatApp> createState() => _NeatAppState();
}

class _NeatAppState extends State<NeatApp> {
  static const _localizationsDelegates = <LocalizationsDelegate<dynamic>>[
    AppLocalizations.delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
  ];

  static const _themeKey = 'neat_theme_mode';
  ThemeMode _themeMode = ThemeMode.dark;
  bool _loading = true;
  int? _deepLinkPostId;
  StreamSubscription<Uri>? _linkSub;

  @override
  void initState() {
    super.initState();
    _restoreTheme();
    if (kIsWeb) {
      final match = RegExp(r'^/post/(\d+)$').firstMatch(Uri.base.path);
      if (match != null) _deepLinkPostId = int.tryParse(match.group(1)!);
    } else {
      _initAppLinks();
    }
  }

  Future<void> _initAppLinks() async {
    final appLinks = AppLinks();
    _linkSub = appLinks.uriLinkStream.listen(_handleUri);
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final uri = await appLinks.getInitialLink();
      if (uri != null) _handleUri(uri);
    });
  }

  void _handleUri(Uri uri) {
    if (uri.scheme != 'neat') return;
    int? postId;
    if (uri.host == 'post' && uri.pathSegments.isNotEmpty) {
      postId = int.tryParse(uri.pathSegments.first);
    }
    if (postId == null) return;
    NeatApp.navigatorKey.currentState?.push(
      MaterialPageRoute(
        builder: (_) => PostDeepLinkPage(postId: postId!, themeMode: _themeMode),
      ),
    );
  }

  @override
  void dispose() {
    _linkSub?.cancel();
    super.dispose();
  }

  Future<void> _restoreTheme() async {
    final prefs = await SharedPreferences.getInstance();
    final value = prefs.getString(_themeKey);
    final localeCode = prefs.getString(NeatApp._localeKey);
    if (localeCode != null && localeCode.isNotEmpty) {
      NeatApp.localeNotifier.value = Locale(localeCode);
    }
    if (!mounted) return;
    setState(() {
      _themeMode = value == 'light' ? ThemeMode.light : ThemeMode.dark;
      _loading = false;
    });
  }

  Future<void> _setTheme(ThemeMode mode) async {
    if (mounted) setState(() => _themeMode = mode);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_themeKey, mode == ThemeMode.light ? 'light' : 'dark');
  }

  ThemeData _darkTheme() {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: const Color(0xff000000),
      colorScheme: const ColorScheme.dark(
        primary: Colors.white,
        secondary: Color(0xff4ea3ff),
        surface: Color(0xff000000),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: Color(0xff000000),
        foregroundColor: Colors.white,
        elevation: 0,
        surfaceTintColor: Color(0xff000000),
      ),
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: Color(0xff000000),
        selectedItemColor: Colors.white,
        unselectedItemColor: Color(0xffa9a9a9),
      ),
      // Subtle top border so dark sheets don't disappear into the black bg.
      bottomSheetTheme: const BottomSheetThemeData(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
          side: BorderSide(color: Color(0xff2a2a2a), width: 0.5),
        ),
      ),
    );
  }

  ThemeData _lightTheme() {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      scaffoldBackgroundColor: Colors.white,
      colorScheme: const ColorScheme.light(
        primary: Colors.black,
        secondary: Color(0xff1479ff),
        surface: Colors.white,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0,
        surfaceTintColor: Colors.white,
      ),
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: Colors.white,
        selectedItemColor: Colors.black,
        unselectedItemColor: Color(0xff6d6d6d),
      ),
      cardColor: Colors.white,
      dividerColor: const Color(0xffd6d9df),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      // Avatars live inside every payload that mentions a person, so a new
      // profile picture has to reach screens that were built before it
      // existed. See AvatarStore.
      valueListenable: AvatarStore.revision,
      builder: (context, _, _) => ValueListenableBuilder<Locale>(
        valueListenable: NeatApp.localeNotifier,
        builder: (context, locale, _) {
        if (_loading) {
          return MaterialApp(
            locale: locale,
            localizationsDelegates: _localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            theme: _lightTheme(),
            darkTheme: _darkTheme(),
            themeMode: _themeMode,
            home: const Scaffold(
              body: NeatLoader(),
            ),
          );
        }
        return MaterialApp(
          title: 'neat',
          locale: locale,
          localizationsDelegates: _localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          navigatorKey: NeatApp.navigatorKey,
          debugShowCheckedModeBanner: false,
          theme: _lightTheme(),
          darkTheme: _darkTheme(),
          themeMode: _themeMode,
          // Tapping away from a field puts the keyboard down, on every screen
          // in the app rather than the handful that remembered to do it.
          //
          // Wrapped here rather than per-screen so a route added later gets it
          // for free. Translucent, so this only ever sees taps that nothing
          // else wanted: a button, a link or a scroll wins the gesture arena
          // first and this never fires for them.
          builder: (context, child) => GestureDetector(
            behavior: HitTestBehavior.translucent,
            onTap: () {
              final focus = FocusManager.instance.primaryFocus;
              if (focus != null && focus.hasFocus) focus.unfocus();
            },
            child: child,
          ),
          home: _deepLinkPostId != null
              ? PostDeepLinkPage(postId: _deepLinkPostId!, themeMode: _themeMode)
              : AuthGate(
                  themeMode: _themeMode,
                  onThemeModeChanged: _setTheme,
                ),
          );
        },
      ),
    );
  }
}

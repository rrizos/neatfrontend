import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'auth/auth_gate.dart';
import 'core/post_deep_link_page.dart';

class NeatApp extends StatefulWidget {
  const NeatApp({super.key});

  @override
  State<NeatApp> createState() => _NeatAppState();
}

class _NeatAppState extends State<NeatApp> {
  static const _themeKey = 'neat_theme_mode';
  ThemeMode _themeMode = ThemeMode.dark;
  bool _loading = true;
  int? _deepLinkPostId;

  @override
  void initState() {
    super.initState();
    _restoreTheme();
    if (kIsWeb) {
      final match = RegExp(r'^/post/(\d+)$').firstMatch(Uri.base.path);
      if (match != null) _deepLinkPostId = int.tryParse(match.group(1)!);
    }
  }

  Future<void> _restoreTheme() async {
    final prefs = await SharedPreferences.getInstance();
    final value = prefs.getString(_themeKey);
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
      scaffoldBackgroundColor: const Color(0xff121212),
      colorScheme: const ColorScheme.dark(
        primary: Colors.white,
        secondary: Color(0xff4ea3ff),
        surface: Color(0xff121212),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: Color(0xff121212),
        foregroundColor: Colors.white,
        elevation: 0,
        surfaceTintColor: Color(0xff121212),
      ),
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: Color(0xff121212),
        selectedItemColor: Colors.white,
        unselectedItemColor: Color(0xffa9a9a9),
      ),
    );
  }

  ThemeData _lightTheme() {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      scaffoldBackgroundColor: const Color(0xfff3f4f6),
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
    if (_loading) {
      return MaterialApp(
        theme: _lightTheme(),
        darkTheme: _darkTheme(),
        themeMode: _themeMode,
        home: const Scaffold(
          body: Center(child: CircularProgressIndicator()),
        ),
      );
    }
    return MaterialApp(
      title: 'neat',
      debugShowCheckedModeBanner: false,
      theme: _lightTheme(),
      darkTheme: _darkTheme(),
      themeMode: _themeMode,
      home: _deepLinkPostId != null
          ? PostDeepLinkPage(postId: _deepLinkPostId!, themeMode: _themeMode)
          : AuthGate(
              themeMode: _themeMode,
              onThemeModeChanged: _setTheme,
            ),
    );
  }
}

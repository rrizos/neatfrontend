import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../core/api.dart';
import '../core/models.dart';
import '../core/push_service.dart';
import '../home/home_page.dart';
import 'landing_page.dart';

class AuthGate extends StatefulWidget {
  const AuthGate({
    super.key,
    required this.themeMode,
    required this.onThemeModeChanged,
  });

  final ThemeMode themeMode;
  final ValueChanged<ThemeMode> onThemeModeChanged;

  // Lets routes pushed outside this widget's subtree (e.g. a DM conversation
  // opened from a tapped push notification, which reads the token straight
  // out of SharedPreferences) trigger the same logout path as an in-tree 401
  // — see push_service.dart / message_deep_link_page usage.
  static Future<void> Function()? _activeForceLogout;
  static Future<void> forceLogout() async => _activeForceLogout?.call();

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  static const _tokenKey = 'neat_auth_token';
  static const _userCacheKey = 'neat_cached_user';
  bool _loading = true;
  AuthSession? _session;

  @override
  void initState() {
    super.initState();
    AuthGate._activeForceLogout = _logout;
    _restore();
  }

  @override
  void dispose() {
    if (identical(AuthGate._activeForceLogout, _logout)) {
      AuthGate._activeForceLogout = null;
    }
    super.dispose();
  }

  Future<void> _restore() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString(_tokenKey);
    if (token == null || token.isEmpty) {
      if (mounted) setState(() => _loading = false);
      return;
    }
    try {
      final res = await http
          .get(meEndpoint, headers: authGetHeaders(token))
          .timeout(const Duration(seconds: 10));
      if (res.statusCode == 401 || res.statusCode == 403) {
        // Token genuinely revoked — clear everything and go to signup.
        await prefs.remove(_tokenKey);
        await prefs.remove(_userCacheKey);
        if (mounted) setState(() => _loading = false);
        return;
      }
      if (res.statusCode != 200) {
        // Non-auth error (server down, captive portal, etc.) — use cache.
        throw Exception('status ${res.statusCode}');
      }
      final decoded = jsonDecode(res.body) as Map<String, dynamic>;
      final userJson = decoded['user'] as Map<String, dynamic>;
      final user = UserProfile.fromJson(userJson);
      await prefs.setString(_userCacheKey, jsonEncode(userJson));
      if (mounted) {
        setState(() {
          _session = AuthSession(token: token, user: user);
          _loading = false;
        });
      }
      if (!kIsWeb) unawaited(PushService.instance.registerForSession(token));
    } catch (_) {
      // Any network failure, timeout, or temporary server error:
      // open into the app with the last-known profile (same as Instagram).
      // On Android the http package wraps SocketException in ClientException,
      // so we catch everything here rather than specific exception types.
      final cachedUserJson = prefs.getString(_userCacheKey);
      if (cachedUserJson != null) {
        try {
          final user = UserProfile.fromJson(
            jsonDecode(cachedUserJson) as Map<String, dynamic>,
          );
          if (mounted) {
            setState(() {
              _session = AuthSession(token: token, user: user);
              _loading = false;
            });
          }
          return;
        } catch (_) {}
      }
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _save(AuthSession session) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_tokenKey, session.token);
    await prefs.setString(_userCacheKey, jsonEncode(session.user.toJson()));
    if (mounted) setState(() => _session = session);
    if (!kIsWeb) unawaited(PushService.instance.registerForSession(session.token));
  }

  Future<void> _logout() async {
    final token = _session?.token;
    if (token != null) {
      if (!kIsWeb) await PushService.instance.unregisterForSession(token);
      await http.post(logoutEndpoint, headers: authJsonHeaders(token));
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_tokenKey);
    await prefs.remove(_userCacheKey);
    if (mounted) setState(() => _session = null);
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      final isLight = widget.themeMode == ThemeMode.light;
      return MaterialApp(
        themeMode: widget.themeMode,
        home: Scaffold(
          backgroundColor: isLight ? Colors.white : const Color(0xff121212),
          body: const Center(child: CircularProgressIndicator()),
        ),
      );
    }
    final session = _session;
    if (session == null) {
      return LandingPage(
        onAuthenticated: _save,
        themeMode: widget.themeMode,
      );
    }
    return HomePage(
      session: session,
      onSessionChanged: (next) => setState(() => _session = next),
      onLogout: _logout,
      themeMode: widget.themeMode,
      onThemeModeChanged: widget.onThemeModeChanged,
    );
  }
}

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../core/api.dart';
import '../core/models.dart';
import '../home/home_page.dart';
import 'auth_screen.dart';

class AuthGate extends StatefulWidget {
  const AuthGate({
    super.key,
    required this.themeMode,
    required this.onThemeModeChanged,
  });

  final ThemeMode themeMode;
  final ValueChanged<ThemeMode> onThemeModeChanged;

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  static const _tokenKey = 'neat_auth_token';
  bool _loading = true;
  AuthSession? _session;

  @override
  void initState() {
    super.initState();
    _restore();
  }

  Future<void> _restore() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString(_tokenKey);
    if (token == null || token.isEmpty) {
      if (mounted) setState(() => _loading = false);
      return;
    }
    try {
      final res = await http.get(meEndpoint, headers: authGetHeaders(token));
      if (res.statusCode != 200) {
        await prefs.remove(_tokenKey);
        if (mounted) setState(() => _loading = false);
        return;
      }
      final decoded = jsonDecode(res.body) as Map<String, dynamic>;
      final user = UserProfile.fromJson(
        decoded['user'] as Map<String, dynamic>,
      );
      if (mounted) {
        setState(() {
          _session = AuthSession(token: token, user: user);
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _save(AuthSession session) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_tokenKey, session.token);
    if (mounted) setState(() => _session = session);
  }

  Future<void> _logout() async {
    final token = _session?.token;
    if (token != null) {
      await http.post(logoutEndpoint, headers: authJsonHeaders(token));
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_tokenKey);
    if (mounted) setState(() => _session = null);
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      final isLight = widget.themeMode == ThemeMode.light;
      return MaterialApp(
        themeMode: widget.themeMode,
        home: Scaffold(
          backgroundColor: isLight ? const Color(0xfff3f4f6) : const Color(0xff121212),
          body: const Center(child: CircularProgressIndicator()),
        ),
      );
    }
    final session = _session;
    if (session == null) {
      return AuthScreen(
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

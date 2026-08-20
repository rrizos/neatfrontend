import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../core/http_client.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../core/api.dart';
import '../core/avatar_store.dart';
import '../core/models.dart';
import '../core/profile_save_queue.dart';
import '../core/push_service.dart';
import '../core/session_tracker.dart';
import '../home/home_page.dart';
import '../map/city_map_view.dart';
import 'city_setup_page.dart';
import 'username_setup_page.dart';
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

class _AuthGateState extends State<AuthGate> with WidgetsBindingObserver {
  static const _tokenKey = 'neat_auth_token';
  static const _userCacheKey = 'neat_cached_user';
  static const _secureStorage = FlutterSecureStorage();
  bool _loading = true;
  AuthSession? _session;

  // Reads a value from Keychain/Keystore-backed secure storage, migrating a
  // legacy plaintext SharedPreferences value (from before this moved off
  // SharedPreferences) on first read so existing sessions aren't logged out.
  Future<String?> _readSecure(SharedPreferences prefs, String key) async {
    final secureValue = await _secureStorage.read(key: key);
    if (secureValue != null && secureValue.isNotEmpty) return secureValue;
    final legacyValue = prefs.getString(key);
    if (legacyValue != null && legacyValue.isNotEmpty) {
      await _secureStorage.write(key: key, value: legacyValue);
      await prefs.remove(key);
    }
    return legacyValue;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // A queued save is delivered on the way back into the app: coming out of
    // a pocket is exactly when a connection returns, and the user has long
    // since moved on from the screen they saved on.
    ProfileSaveQueue.onSaved = _onQueuedSaveLanded;
    AuthGate._activeForceLogout = _logout;
    _restore();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    ProfileSaveQueue.onSaved = null;
    if (identical(AuthGate._activeForceLogout, _logout)) {
      AuthGate._activeForceLogout = null;
    }
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final token = _session?.token;
    if (state == AppLifecycleState.resumed && token != null) {
      // Coming back into the app is exactly when a connection tends to return,
      // and by then the user is nowhere near the screen they saved on.
      unawaited(ProfileSaveQueue.retryPending(token));
    }
  }

  /// A queued save finally reached the server; adopt the copy it sent back so
  /// this device holds the same canonical profile as every other one.
  void _onQueuedSaveLanded(UserProfile user) {
    final token = _session?.token;
    if (token == null || !mounted) return;
    unawaited(_save(AuthSession(token: token, user: user)));
  }

  Future<void> _restore() async {
    final prefs = await SharedPreferences.getInstance();
    // iOS Keychain survives app deletion/reinstall; SharedPreferences don't.
    // On a fresh install, clear any stale Keychain entries so the user sees
    // the landing page instead of being silently auto-logged in.
    const installedKey = 'neat_installed';
    if (prefs.getBool(installedKey) != true) {
      await _secureStorage.deleteAll();
      await prefs.setBool(installedKey, true);
    }
    final token = await _readSecure(prefs, _tokenKey);
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
        await _secureStorage.delete(key: _tokenKey);
        await _secureStorage.delete(key: _userCacheKey);
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
      // Authoritative, and known before the cached feed is drawn — so your own
      // posts show the picture you have now, not the one the cache was saved
      // with. See AvatarStore.seed.
      AvatarStore.seed(username: user.username, url: user.avatarUrl);
      // A profile save that never reached the server last time — including one
      // interrupted by the app being killed — is delivered now.
      unawaited(ProfileSaveQueue.retryPending(token));
      SessionTracker.instance.start(token);
      await _secureStorage.write(key: _userCacheKey, value: jsonEncode(userJson));
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
      final cachedUserJson = await _readSecure(prefs, _userCacheKey);
      if (cachedUserJson != null) {
        try {
          final user = UserProfile.fromJson(
            jsonDecode(cachedUserJson) as Map<String, dynamic>,
          );
          AvatarStore.seed(username: user.username, url: user.avatarUrl);
          unawaited(ProfileSaveQueue.retryPending(token));
          SessionTracker.instance.start(token);
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
    await _secureStorage.write(key: _tokenKey, value: session.token);
    await _secureStorage.write(key: _userCacheKey, value: jsonEncode(session.user.toJson()));
    if (mounted) setState(() => _session = session);
    SessionTracker.instance.start(session.token);
    if (!kIsWeb) unawaited(PushService.instance.registerForSession(session.token));
  }

  Future<void> _logout() async {
    final token = _session?.token;
    if (token != null) {
      if (!kIsWeb) await PushService.instance.unregisterForSession(token);
      await http.post(logoutEndpoint, headers: authJsonHeaders(token));
    }
    await _secureStorage.delete(key: _tokenKey);
    await _secureStorage.delete(key: _userCacheKey);
    SessionTracker.instance.stop();
    if (mounted) setState(() => _session = null);
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      final isLight = widget.themeMode == ThemeMode.light;
      return MaterialApp(
        themeMode: widget.themeMode,
        home: Scaffold(
          backgroundColor: isLight ? Colors.white : const Color(0xff000000),
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
    // Still carrying a username the server invented, which only happens to
    // accounts made through Apple or Google. Asked before the city, because a
    // name is what the rest of the app labels them by from that point on.
    if (session.user.usernamePending) {
      return _UsernameGate(
        session: session,
        themeMode: widget.themeMode,
        onChosen: (next) => setState(() => _session = next),
        persist: _save,
      );
    }

    // Signed in, but sign-up never finished. The account and its token are
    // real — only the city is missing — so this resumes at the step that was
    // interrupted instead of sending the user back to a form that would now
    // reject their own username as taken.
    if (session.user.city.trim().isEmpty) {
      return _CitySetupGate(
        session: session,
        themeMode: widget.themeMode,
        onCompleted: _save,
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

/// Hosts [UsernameSetupPage] and saves the choice.
///
/// Like the city step this is a screen rather than a pushed route, so an app
/// killed here comes back to it instead of to a form that would refuse the
/// account it already created.
class _UsernameGate extends StatefulWidget {
  const _UsernameGate({
    required this.session,
    required this.themeMode,
    required this.onChosen,
    required this.persist,
  });

  final AuthSession session;
  final ThemeMode themeMode;
  final ValueChanged<AuthSession> onChosen;
  final Future<void> Function(AuthSession) persist;

  @override
  State<_UsernameGate> createState() => _UsernameGateState();
}

class _UsernameGateState extends State<_UsernameGate> {
  bool _saving = false;
  String? _error;

  Future<void> _submit(String username) async {
    if (_saving) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final res = await http
          .patch(
            meEndpoint,
            headers: authJsonHeaders(widget.session.token),
            body: jsonEncode({'username': username}),
          )
          .timeout(const Duration(seconds: 20));
      if (res.statusCode != 200) {
        // The server is the only thing that knows whether a name is free, so
        // its wording is shown rather than a guess at what went wrong.
        setState(() {
          _saving = false;
          _error = friendlyHttpError(res);
        });
        return;
      }
      final decoded = jsonDecode(res.body) as Map<String, dynamic>;
      final user = UserProfile.fromJson(decoded['user'] as Map<String, dynamic>);
      if (!mounted) return;
      await widget.persist(AuthSession(token: widget.session.token, user: user));
      if (!mounted) return;
      widget.onChosen(AuthSession(token: widget.session.token, user: user));
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = friendlyError(e);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return UsernameSetupPage(
      themeMode: widget.themeMode,
      busy: _saving,
      serverError: _error,
      onChosen: _submit,
    );
  }
}

/// The last step of sign-up, hosted as a screen rather than pushed on top of
/// the form, so it is reachable on a later launch as well as straight after
/// the account is created.
///
/// The city is only committed once the server has accepted it — a failure here
/// (which on this screen usually means no connection) leaves the user exactly
/// where they were, free to try again, rather than dropping them into an app
/// with no city.
class _CitySetupGate extends StatefulWidget {
  const _CitySetupGate({
    required this.session,
    required this.themeMode,
    required this.onCompleted,
  });

  final AuthSession session;
  final ThemeMode themeMode;
  final ValueChanged<AuthSession> onCompleted;

  @override
  State<_CitySetupGate> createState() => _CitySetupGateState();
}

class _CitySetupGateState extends State<_CitySetupGate> {
  bool _saving = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_prewarmed) return;
    _prewarmed = true;
    // The sign-up form warms the map while the user types; a session resumed
    // straight onto this screen never passed through it, so warm it here too
    // rather than making the resumed flow the slow one. No-op off Android.
    unawaited(prewarmCityMap(
      homeCity: '',
      isDark: Theme.of(context).brightness == Brightness.dark,
    ));
  }

  bool _prewarmed = false;

  Future<void> _submit(String city) async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      final res = await http
          .patch(
            meEndpoint,
            headers: authJsonHeaders(widget.session.token),
            body: jsonEncode({'city': city}),
          )
          .timeout(const Duration(seconds: 20));
      if (res.statusCode != 200) throw Exception(friendlyHttpError(res));
      final decoded = jsonDecode(res.body) as Map<String, dynamic>;
      final user = UserProfile.fromJson(decoded['user'] as Map<String, dynamic>);
      if (!mounted) return;
      widget.onCompleted(AuthSession(token: widget.session.token, user: user));
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(friendlyError(e)),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        CitySetupPage(
          token: widget.session.token,
          themeMode: widget.themeMode,
          onCitySelected: _submit,
        ),
        if (_saving)
          const Positioned.fill(
            child: ColoredBox(
              color: Color(0x66000000),
              child: Center(child: CircularProgressIndicator()),
            ),
          ),
      ],
    );
  }
}

import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import 'api.dart';
import 'http_client.dart' as http;

/// Tells the server the app is open, so sessions can be measured.
///
/// Nothing recorded how long anybody stayed or whether they came back — the
/// only signal was a single `last_active` timestamp that is overwritten every
/// time, which can say "seen recently" and nothing more. Retention and
/// time-in-app cannot be reconstructed from it afterwards, so they only start
/// existing once something like this is running.
///
/// Deliberately cheap and deliberately dumb: a ping every minute while the app
/// is in front, one immediately on resume, and nothing at all in the
/// background. The server decides where sessions begin and end, so a phone
/// that is killed or loses signal cannot leave a session open forever.
class SessionTracker with WidgetsBindingObserver {
  SessionTracker._();
  static final SessionTracker instance = SessionTracker._();

  static const _interval = Duration(minutes: 1);

  String? _token;
  Timer? _timer;
  bool _started = false;

  void start(String token) {
    _token = token;
    if (!_started) {
      _started = true;
      WidgetsBinding.instance.addObserver(this);
    }
    _ping();
    _timer?.cancel();
    _timer = Timer.periodic(_interval, (_) => _ping());
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
    _token = null;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // A ping right away, so a return after hours is recorded as the start of
      // a new session rather than waiting up to a minute for the timer.
      _ping();
      _timer?.cancel();
      _timer = Timer.periodic(_interval, (_) => _ping());
    } else {
      // Nothing while backgrounded: the session should end when the user stops
      // looking, not when the OS finally suspends the process.
      _timer?.cancel();
      _timer = null;
    }
  }

  Future<void> _ping() async {
    final token = _token;
    if (token == null || kIsWeb) return;
    try {
      await http.post(
        sessionPingEndpoint,
        headers: {
          ...authJsonHeaders(token),
          'X-Neat-Platform': Platform.isIOS ? 'ios' : 'android',
        },
      ).timeout(const Duration(seconds: 10));
    } catch (_) {
      // Analytics must never be the reason anything else fails, or retries.
    }
  }
}

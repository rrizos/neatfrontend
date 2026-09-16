import 'dart:async';
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'api.dart';
import 'http_client.dart' as http;

/// Who invited the person holding this phone, between tapping their link and
/// finishing a sign-up.
///
/// Attribution needs the two halves of the journey joined across an App Store
/// visit, and neither platform hands an app the link that led to the install
/// (iOS has no install referrer at all). So the join is credited the next time
/// the link is opened *after* the app exists — which is why the invite page
/// asks for exactly that — and this is where the name waits in between.
///
/// Nothing here decides anything: the server re-checks that the inviter is
/// real, that they are not the new account itself, that the account is new,
/// and that nobody has already been credited with it. See invites/views.py.
class InviteAttribution {
  static const _inviterKey = 'neat_invite_inviter';
  static const _cityKey = 'neat_invite_city';
  static const _whenKey = 'neat_invite_when';

  /// A name older than this is not evidence of anything any more. Someone who
  /// tapped a link a fortnight ago and signs up today did so for their own
  /// reasons.
  static const _maxAge = Duration(days: 7);

  /// Remembers who sent the invitation that just opened the app.
  static Future<void> remember({required String inviter, String city = ''}) async {
    if (inviter.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_inviterKey, inviter);
    await prefs.setString(_cityKey, city);
    await prefs.setInt(_whenKey, DateTime.now().millisecondsSinceEpoch);
  }

  /// Reports a pending invitation, if there is one, for a session that has
  /// just been established.
  ///
  /// Called for every session, not only for sign-ups, because the app cannot
  /// reliably tell the two apart — a sign-up and a sign-in arrive here as the
  /// same object. The server's `date_joined` check is what makes that safe,
  /// and it is the half that cannot be fooled by a stale preference.
  static Future<void> reportIfPending(String token) async {
    if (token.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    final inviter = prefs.getString(_inviterKey) ?? '';
    if (inviter.isEmpty) return;

    final when = prefs.getInt(_whenKey) ?? 0;
    final age = DateTime.now().millisecondsSinceEpoch - when;
    if (when == 0 || age > _maxAge.inMilliseconds) {
      await _clear(prefs);
      return;
    }

    try {
      final res = await http.post(
        inviteJoinedEndpoint,
        headers: authJsonHeaders(token),
        body: jsonEncode({
          'inviter': inviter,
          'city': prefs.getString(_cityKey) ?? '',
        }),
      );
      // 2xx means the server has made its decision — credited or refused, it
      // will not change its mind on a retry, so the name has done its job.
      // Anything else (offline, a 502) leaves it for the next session.
      if (res.statusCode >= 200 && res.statusCode < 300) {
        await _clear(prefs);
      }
    } catch (_) {
      // Left pending on purpose: the next sign-in tries again.
    }
  }

  static Future<void> _clear(SharedPreferences prefs) async {
    await prefs.remove(_inviterKey);
    await prefs.remove(_cityKey);
    await prefs.remove(_whenKey);
  }
}

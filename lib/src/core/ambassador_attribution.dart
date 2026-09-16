import 'dart:async';
import 'dart:convert';

import 'package:android_play_install_referrer/android_play_install_referrer.dart';
import 'package:flutter/foundation.dart' show defaultTargetPlatform, kIsWeb, TargetPlatform;
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'api.dart';
import 'http_client.dart' as http;

/// The paid-referral half of [InviteAttribution], and deliberately not the
/// same code.
///
/// The difference is what the app is trusted to say. An invite is credited on
/// the app's word, because the worst case is a friend getting undeserved
/// credit for a friend. An ambassador is paid, so the app is trusted with
/// nothing: when an ambassador link opens it, it asks the server for a
/// single-use token, and after a sign-up it hands that token back. The code in
/// the link never travels to the claim, and a token the server did not mint
/// cannot be invented.
///
/// Every check that matters — is this account new, was it made after the
/// click, has this token been spent, is this the ambassador crediting
/// themselves — happens on the server. See ambassadors/views.py.
class AmbassadorAttribution {
  static const _tokenKey = 'neat_ambassador_token';
  static const _whenKey = 'neat_ambassador_when';
  static const _methodKey = 'neat_ambassador_method';
  //: Which claim this token belongs to: 'ambassador' or 'invite'.
  static const _kindKey = 'neat_ambassador_kind';
  //: Set once the install has been examined, so the pasteboard is read at most
  //: once per installation — on iOS that read costs the user a system prompt,
  //: and asking twice for something we already have would be rude.
  static const _checkedKey = 'neat_ambassador_install_checked';

  /// The two prefixes, so a token can never be sent to the wrong claim. An
  /// ambassador token is money and an invite token is not, and the server
  /// checks them against different tables.
  static const _ambassadorPrefix = 'neat_ct=';
  static const _invitePrefix = 'neat_it=';

  /// Tokens expire on the server at fourteen days. This is the same window,
  /// so a stale one is dropped here rather than sent to be refused.
  static const _maxAge = Duration(days: 14);

  /// Looks for a token the installation itself carried in, once, at startup.
  ///
  /// This exists because the tap that the token design assumed — following the
  /// link again after installing — is a tap nobody makes. Two ways around it,
  /// and neither is available on both platforms:
  ///
  /// * **Android** has the Play install referrer: whatever was appended to the
  ///   store URL is handed to the app on first launch. Exact, invisible, and
  ///   requires nothing of the reader.
  /// * **iOS** has no install referrer at all, so the download button leaves
  ///   the token on the pasteboard and this reads it back. iOS 16+ shows a
  ///   paste prompt, which is why it happens exactly once.
  ///
  /// Whatever neither finds, the server may still match by address and time —
  /// but that arrives flagged for review rather than counted. See
  /// ambassadors/matching.py.
  static Future<void> bootstrapFromInstall() async {
    if (kIsWeb) return;
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(_checkedKey) == true) return;
    // Marked before the work, not after: a crash mid-read must not turn into a
    // paste prompt on every launch forever.
    await prefs.setBool(_checkedKey, true);

    // A link followed into the app already stored something stronger.
    if ((prefs.getString(_tokenKey) ?? '').isNotEmpty) return;

    String raw = '';
    String method = '';
    try {
      if (defaultTargetPlatform == TargetPlatform.android) {
        final details = await AndroidPlayInstallReferrer.installReferrer;
        raw = details.installReferrer ?? '';
        method = 'referrer';
      } else if (defaultTargetPlatform == TargetPlatform.iOS) {
        final data = await Clipboard.getData(Clipboard.kTextPlain);
        raw = data?.text ?? '';
        method = 'clipboard';
      }
    } catch (_) {
      // No referrer, no permission, no clipboard. The server's own match by
      // address is the last resort, and it needs nothing from here.
      return;
    }

    final ambassador = _extract(raw, _ambassadorPrefix);
    final invite = _extract(raw, _invitePrefix);
    // Ambassador first when both somehow appear: it is the one that pays.
    final token = ambassador.isNotEmpty ? ambassador : invite;
    if (token.isEmpty) return;

    await prefs.setString(_tokenKey, token);
    await prefs.setString(_kindKey, ambassador.isNotEmpty ? 'ambassador' : 'invite');
    await prefs.setString(_methodKey, method);
    await prefs.setInt(_whenKey, DateTime.now().millisecondsSinceEpoch);
  }

  /// Pulls `<prefix><token>` out of a referrer string or a clipboard, either
  /// of which may carry anything at all around it.
  static String _extract(String raw, String prefix) {
    final match =
        RegExp('${RegExp.escape(prefix)}([A-Za-z0-9_-]+)').firstMatch(raw);
    return match?.group(1) ?? '';
  }

  /// Asks the server for a token the moment an ambassador link opens the app.
  ///
  /// Minting now, rather than at sign-up, is the point: the token is recorded
  /// against this device at the moment it actually followed the link, which is
  /// what makes it evidence rather than an assertion.
  static Future<void> remember(String code) async {
    if (code.isEmpty) return;
    try {
      final res = await http.post(
        ambassadorClickEndpoint,
        headers: jsonHeaders,
        body: jsonEncode({'code': code}),
      );
      if (res.statusCode < 200 || res.statusCode >= 300) return;
      final token = (jsonDecode(res.body) as Map<String, dynamic>)['token'];
      // An unknown or disabled code comes back as an empty token, shaped
      // exactly like a real answer so the endpoint cannot be used to test
      // which codes exist. Nothing to store either way.
      if (token is! String || token.isEmpty) return;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_tokenKey, token);
      await prefs.setString(_kindKey, 'ambassador');
      await prefs.setString(_methodKey, 'token');
      await prefs.setInt(_whenKey, DateTime.now().millisecondsSinceEpoch);
    } catch (_) {
      // Offline at the moment of the tap. The link can be opened again.
    }
  }

  /// Presents a pending token for a session that has just been established.
  ///
  /// Called for every session, because the app cannot tell a sign-up from a
  /// sign-in — they arrive here as the same object. The server's own checks on
  /// account age are what make that safe.
  static Future<void> claimIfPending(String token) async {
    if (token.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    final pending = prefs.getString(_tokenKey) ?? '';
    if (pending.isEmpty) return;

    final when = prefs.getInt(_whenKey) ?? 0;
    if (when == 0 ||
        DateTime.now().millisecondsSinceEpoch - when > _maxAge.inMilliseconds) {
      await _clear(prefs);
      return;
    }

    final invite = (prefs.getString(_kindKey) ?? 'ambassador') == 'invite';
    try {
      final res = await http.post(
        invite ? inviteClaimEndpoint : ambassadorClaimEndpoint,
        headers: authJsonHeaders(token),
        body: jsonEncode({
          'token': pending,
          // Recorded on the signup so a reviewer can see what the credit
          // rests on. The server re-checks the token either way, and ignores
          // this on the invite side, where nothing is paid.
          'method': prefs.getString(_methodKey) ?? 'token',
        }),
      );
      // 2xx means the server has ruled — credited or refused, it will not rule
      // differently on a retry, and a spent token is worthless anyway.
      // Anything else (offline, a 502) leaves it for the next session.
      if (res.statusCode >= 200 && res.statusCode < 300) {
        await _clear(prefs);
      }
    } catch (_) {
      // Left pending on purpose: the next sign-in tries again.
    }
  }

  static Future<void> _clear(SharedPreferences prefs) async {
    await prefs.remove(_tokenKey);
    await prefs.remove(_kindKey);
    await prefs.remove(_methodKey);
    await prefs.remove(_whenKey);
  }
}

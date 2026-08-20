import 'dart:convert';
import 'dart:io' show Platform;
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:google_sign_in/google_sign_in.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';

import '../core/api.dart';
import '../core/http_client.dart' as http;
import '../core/models.dart';

/// Signing in through Apple or Google.
///
/// Neither provider is trusted here. Both hand back an ID token, which is
/// forwarded to the server and checked there against the provider's own
/// published signing keys — see `accounts/social_auth.py`. Nothing in this
/// file decides who anybody is; it only collects the evidence.
///
/// The session that comes back is an ordinary neat session, and for somebody
/// signing up it names a user with no city — which is what sends them on to
/// the map, exactly like an email sign-up.

/// The user dismissed the provider's sheet. Not an error worth showing.
class SocialSignInCancelled implements Exception {
  const SocialSignInCancelled();
}

/// Something went wrong that the user should be told about.
class SocialSignInError implements Exception {
  const SocialSignInError(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Whether this build carries the Sign in with Apple capability.
///
/// Offering the button without it produces a provisioning failure at the
/// moment the user taps, which is the worst possible time to find out — so the
/// button is hidden until the capability is really there. Turning it on means
/// both this flag *and* the entitlement in ios/Runner/Runner.entitlements,
/// which additionally needs an Apple ID signed into Xcode so the capability
/// can be registered on the App ID.
const bool appleSignInEnabled = true;

/// Whether Sign in with Apple can be offered at all.
///
/// Apple requires it to be offered wherever other third-party sign-in is, but
/// only on their own platforms — on Android there is nothing to call.
Future<bool> appleSignInAvailable() async {
  if (!appleSignInEnabled) return false;
  if (kIsWeb || !Platform.isIOS) return false;
  try {
    return await SignInWithApple.isAvailable();
  } catch (_) {
    return false;
  }
}

String _rawNonce([int length = 32]) {
  const chars =
      'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._';
  final rand = Random.secure();
  return List.generate(length, (_) => chars[rand.nextInt(chars.length)]).join();
}

Future<AuthSession> signInWithApple() async {
  // Apple binds the token to a nonce we choose: they receive only its hash,
  // and the server checks that the hash inside the token matches the raw value
  // we send it. A token captured elsewhere therefore cannot be replayed here,
  // because it is tied to a nonce that only this attempt knows.
  final rawNonce = _rawNonce();
  final hashedNonce = sha256.convert(utf8.encode(rawNonce)).toString();

  final AuthorizationCredentialAppleID credential;
  try {
    credential = await SignInWithApple.getAppleIDCredential(
      scopes: const [
        AppleIDAuthorizationScopes.email,
        AppleIDAuthorizationScopes.fullName,
      ],
      nonce: hashedNonce,
    );
  } on SignInWithAppleAuthorizationException catch (e) {
    if (e.code == AuthorizationErrorCode.canceled) {
      throw const SocialSignInCancelled();
    }
    throw SocialSignInError(e.message);
  } catch (e) {
    throw SocialSignInError('$e');
  }

  final idToken = credential.identityToken;
  if (idToken == null || idToken.isEmpty) {
    throw const SocialSignInError('Apple did not return an identity token.');
  }

  // Apple sends the name once and only on the very first authorisation, and
  // never inside the token — so if it is not captured here it is gone. The
  // server treats it as a display hint, never as identity.
  final name = [credential.givenName, credential.familyName]
      .where((p) => p != null && p.trim().isNotEmpty)
      .map((p) => p!.trim())
      .join(' ');

  return _exchange(
    provider: 'apple',
    idToken: idToken,
    fullName: name,
    rawNonce: rawNonce,
  );
}

Future<AuthSession> signInWithGoogle() async {
  final signIn = GoogleSignIn.instance;
  try {
    // The iOS client id identifies this app to Google; the server client id is
    // what makes Google mint an ID token our backend can verify. Both come
    // from the Firebase/Google Cloud project — see googleClientId in api.dart.
    await signIn.initialize(
      clientId: googleClientId,
      serverClientId: googleServerClientId,
    );
  } catch (e) {
    throw SocialSignInError('$e');
  }

  if (!signIn.supportsAuthenticate()) {
    throw const SocialSignInError(
      'Google sign-in is not available on this device.',
    );
  }

  final GoogleSignInAccount account;
  try {
    account = await signIn.authenticate();
  } on GoogleSignInException catch (e) {
    if (e.code == GoogleSignInExceptionCode.canceled) {
      throw const SocialSignInCancelled();
    }
    throw SocialSignInError(e.description ?? e.code.name);
  } catch (e) {
    throw SocialSignInError('$e');
  }

  final idToken = account.authentication.idToken;
  if (idToken == null || idToken.isEmpty) {
    throw const SocialSignInError(
      'Google did not return an identity token. Check the server client id.',
    );
  }

  return _exchange(
    provider: 'google',
    idToken: idToken,
    fullName: account.displayName ?? '',
  );
}

Future<AuthSession> _exchange({
  required String provider,
  required String idToken,
  required String fullName,
  String? rawNonce,
}) async {
  final http.Response res;
  try {
    res = await http.post(
      socialLoginEndpoint,
      headers: jsonHeaders,
      body: jsonEncode({
        'provider': provider,
        'idToken': idToken,
        if (fullName.isNotEmpty) 'fullName': fullName,
        'nonce': ?rawNonce,
      }),
    );
  } catch (e) {
    throw SocialSignInError(friendlyError(e));
  }
  if (res.statusCode != 200 && res.statusCode != 201) {
    throw SocialSignInError(friendlyHttpError(res));
  }
  return AuthSession.fromJson(jsonDecode(res.body) as Map<String, dynamic>);
}

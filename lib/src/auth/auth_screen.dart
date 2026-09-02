import 'dart:async';
import 'dart:convert';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import '../core/http_client.dart' as http;

import '../../l10n/app_localizations.dart';
import '../core/api.dart';
import '../core/models.dart';
import '../core/legal_links.dart';
import '../map/city_map_view.dart';
import '../map/map_snapshot.dart';
import 'app_intro_page.dart';
import 'social_buttons.dart';
import 'forgot_password_screen.dart';

class AuthScreen extends StatefulWidget {
const AuthScreen({
  super.key,
  required this.onAuthenticated,
  required this.themeMode,
  this.initialSignup = false,
});
final ValueChanged<AuthSession> onAuthenticated;
final ThemeMode themeMode;
final bool initialSignup;

@override
State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
final _username = TextEditingController();
final _email = TextEditingController();
final _password = TextEditingController();
final _fullName = TextEditingController();
late bool _signup = widget.initialSignup;
bool _loading = false;
String? _error;
final _termsRecognizer = TapGestureRecognizer();
final _privacyRecognizer = TapGestureRecognizer();

bool _cityMapPrewarmed = false;

@override
void didChangeDependencies() {
super.didChangeDependencies();
// The signup flow always ends at the city-picker map — warm its WebView in
// the background as soon as we know we're in that flow (rather than when
// the map screen actually opens), so the mapkit.js parse hides behind
// whatever time the user spends filling in the form.
if (_signup && !_cityMapPrewarmed) {
_cityMapPrewarmed = true;
final isDark = Theme.of(context).brightness == Brightness.dark;
unawaited(prewarmCityMap(homeCity: '', isDark: isDark));
unawaited(prewarmCityMapHero(isDark: isDark));
unawaited(prewarmCityMapSnapshot(isDark: isDark, context: context));
}
}

@override
void initState() {
super.initState();
_termsRecognizer.onTap = () => openTermsOfService(context);
_privacyRecognizer.onTap = () => openPrivacyPolicy(context);
}

@override
void dispose() {
_username.dispose();
_email.dispose();
_password.dispose();
_fullName.dispose();
_termsRecognizer.dispose();
_privacyRecognizer.dispose();
super.dispose();
}

Future<void> _submit() async {
setState(() {
_loading = true;
_error = null;
});
final body = {
'username': _username.text.trim(),
'password': _password.text,
};
if (_signup) {
body['email'] = _email.text.trim();
body['fullName'] = _fullName.text.trim();
}
try {
final res = await http.post(
_signup ? signupEndpoint : loginEndpoint,
headers: jsonHeaders,
body: jsonEncode(body),
);
if (res.statusCode != 200 && res.statusCode != 201) {
throw Exception(friendlyHttpError(res));
}
final session = AuthSession.fromJson(
jsonDecode(res.body) as Map<String, dynamic>,
);
if (mounted) {
// Both paths hand the session straight over, which is what writes the
// token to the Keychain. Sign-up used to hold it in memory until a city
// had been picked, so anything that ended the app on the map step — a
// crash, a dead connection, the user backgrounding it — threw the token
// away while the account stayed on the server: the username was taken
// and there was no way back into it. AuthGate now sees a session whose
// user has no city and resumes at the map instead of the form.
if (mounted && Navigator.of(context).canPop()) Navigator.of(context).popUntil((r) => r.isFirst);
widget.onAuthenticated(session);
}
} catch (e) {
if (mounted) {
setState(() => _error = friendlyError(e));
}
} finally {
if (mounted) {
setState(() => _loading = false);
}
}
}

@override
Widget build(BuildContext context) {
final l10n = AppLocalizations.of(context);
final isLight = widget.themeMode == ThemeMode.light;
return Scaffold(
backgroundColor: isLight ? Colors.white : const Color(0xff000000),
body: SafeArea(
child: Center(
child: SingleChildScrollView(
padding: const EdgeInsets.all(24),
child: ConstrainedBox(
constraints: const BoxConstraints(maxWidth: 420),
child: Column(
crossAxisAlignment: CrossAxisAlignment.stretch,
children: [
Image.asset(
  'assets/neat_logo.png',
  height: 112,
  color: isLight ? Colors.black : Colors.white,
  colorBlendMode: BlendMode.srcIn,
),
const SizedBox(height: 20),
TextField(
controller: _username,
style: TextStyle(color: isLight ? Colors.black : Colors.white),
cursorColor: isLight ? Colors.black : Colors.white,
decoration: _fieldDecoration(
_signup ? l10n.username : l10n.emailOrUsername, isLight),
),
if (_signup) ...[
const SizedBox(height: 12),
TextField(
controller: _email,
style: TextStyle(color: isLight ? Colors.black : Colors.white),
cursorColor: isLight ? Colors.black : Colors.white,
decoration: _fieldDecoration(l10n.email, isLight),
),
const SizedBox(height: 12),
TextField(
controller: _fullName,
style: TextStyle(color: isLight ? Colors.black : Colors.white),
cursorColor: isLight ? Colors.black : Colors.white,
decoration: _fieldDecoration(l10n.fullName, isLight),
),
],
const SizedBox(height: 12),
TextField(
controller: _password,
obscureText: true,
style: TextStyle(color: isLight ? Colors.black : Colors.white),
cursorColor: isLight ? Colors.black : Colors.white,
decoration: _fieldDecoration(l10n.password, isLight),
),
if (_error != null) ...[
const SizedBox(height: 12),
Text(
_error!,
style: const TextStyle(color: Colors.redAccent),
),
],
const SizedBox(height: 16),
FilledButton(
onPressed: _loading ? null : _submit,
child: Text(_signup ? l10n.signUp : l10n.signIn),
),
// Only on the sign-in side. Somebody who reached the sign-up form got
// here by choosing "with email" a screen ago, and offering the other two
// again would be asking the same question twice.
//
// The same buttons as sign-up on purpose: to the server both are the one
// act, so whoever created their account with a provider gets back into
// it by tapping the provider again.
if (!_signup) ...[
  const SizedBox(height: 20),
  AuthOrDivider(isLight: isLight),
  const SizedBox(height: 16),
  SocialSignInButtons(
    isLight: isLight,
    onAuthenticated: widget.onAuthenticated,
    onBusyChanged: (busy) => setState(() => _loading = busy),
  ),
],
if (_signup) ...[
  const SizedBox(height: 12),
  Text.rich(
    TextSpan(
      style: TextStyle(
        color: isLight ? const Color(0xff6b7280) : const Color(0xffb7b7b7),
        fontSize: 13,
        height: 1.4,
      ),
      children: [
        TextSpan(text: l10n.authAgreePrefix),
        TextSpan(
          text: l10n.termsOfService,
          style: const TextStyle(color: Color(0xff1479ff), fontWeight: FontWeight.w600),
          recognizer: _termsRecognizer,
        ),
        TextSpan(text: l10n.authAnd),
        TextSpan(
          text: l10n.privacyPolicy,
          style: const TextStyle(color: Color(0xff1479ff), fontWeight: FontWeight.w600),
          recognizer: _privacyRecognizer,
        ),
        TextSpan(text: l10n.authAgreeSuffix),
      ],
    ),
    textAlign: TextAlign.center,
  ),
],
if (!_signup) ...[
  const SizedBox(height: 4),
  TextButton(
    onPressed: _loading ? null : () => Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ForgotPasswordScreen(
          onAuthenticated: widget.onAuthenticated,
          themeMode: widget.themeMode,
        ),
      ),
    ),
    child: Text(
      l10n.forgotPassword,
      style: const TextStyle(color: Color(0xff1479ff), fontWeight: FontWeight.w600),
    ),
  ),
],
TextButton(
onPressed: _loading
? null
: () {
if (!_signup) {
// Coming from sign-in, "new here?" starts sign-up properly:
// the tutorial, then the choice of Apple/Google/email. Flipping
// this form into sign-up mode instead dropped people straight
// into a credentials form, skipping both.
Navigator.of(context).push(
MaterialPageRoute<void>(
builder: (_) => AppIntroPage(
onAuthenticated: widget.onAuthenticated,
themeMode: widget.themeMode,
),
),
);
return;
}
setState(() => _signup = false);
},
child: Text(
_signup
? l10n.authSwitchToSignIn
: l10n.authSwitchToSignUp,
),
),
],
),
),
),
),
),
);
}

InputDecoration _fieldDecoration(String label, bool isLight) {
return InputDecoration(
labelText: label,
labelStyle: const TextStyle(color: Color(0xffb7b7b7)),
filled: true,
fillColor: isLight ? Colors.white : const Color(0xff141414),
border: OutlineInputBorder(
  borderRadius: BorderRadius.circular(16),
  borderSide: BorderSide(color: isLight ? const Color(0xffd0d5dd) : const Color(0xff2a2a2a)),
),
enabledBorder: OutlineInputBorder(
  borderRadius: BorderRadius.circular(16),
  borderSide: BorderSide(color: isLight ? const Color(0xffd0d5dd) : const Color(0xff2a2a2a)),
),
focusedBorder: OutlineInputBorder(
  borderRadius: BorderRadius.circular(16),
  borderSide: const BorderSide(color: Colors.white),
),
);
}

}

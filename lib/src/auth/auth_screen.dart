import 'dart:async';
import 'dart:convert';
import 'dart:ui';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import '../core/http_client.dart' as http;

import '../core/api.dart';
import '../core/models.dart';
import '../legal/legal_page.dart';
import '../map/city_map_view.dart';
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
unawaited(prewarmCityMap(homeCity: '', isDark: Theme.of(context).brightness == Brightness.dark));
}
}

@override
void initState() {
super.initState();
_termsRecognizer.onTap = () => Navigator.of(context).push(
  MaterialPageRoute(
    builder: (_) => LegalPage(
      title: 'Terms of Service',
      body: termsOfServiceText,
      titleEl: termsOfServiceTitleEl,
      bodyEl: termsOfServiceTextEl,
      themeMode: widget.themeMode,
    ),
  ),
);
_privacyRecognizer.onTap = () => Navigator.of(context).push(
  MaterialPageRoute(
    builder: (_) => LegalPage(
      title: 'Privacy Policy',
      body: privacyPolicyText,
      titleEl: privacyPolicyTitleEl,
      bodyEl: privacyPolicyTextEl,
      themeMode: widget.themeMode,
    ),
  ),
);
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
if (_signup) {
final selectedCity = await Navigator.of(context).push<String>(
MaterialPageRoute(
builder: (_) => _CityPickPage(token: session.token),
),
);
if (!mounted) return;
if (selectedCity == null || selectedCity.isEmpty) {
setState(() => _loading = false);
return;
}
final updateRes = await http.patch(
meEndpoint,
headers: authJsonHeaders(session.token),
body: jsonEncode({'city': selectedCity}),
);
if (updateRes.statusCode != 200) {
throw Exception(friendlyHttpError(updateRes));
}
final updated = jsonDecode(updateRes.body) as Map<String, dynamic>;
final user = UserProfile.fromJson(
updated['user'] as Map<String, dynamic>,
);
if (mounted && Navigator.of(context).canPop()) Navigator.of(context).popUntil((r) => r.isFirst);
widget.onAuthenticated(AuthSession(token: session.token, user: user));
} else {
if (mounted && Navigator.of(context).canPop()) Navigator.of(context).popUntil((r) => r.isFirst);
widget.onAuthenticated(session);
}
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
final isLight = widget.themeMode == ThemeMode.light;
return Scaffold(
backgroundColor: isLight ? Colors.white : const Color(0xff121212),
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
decoration: _fieldDecoration('Username', isLight),
),
if (_signup) ...[
const SizedBox(height: 12),
TextField(
controller: _email,
style: TextStyle(color: isLight ? Colors.black : Colors.white),
cursorColor: isLight ? Colors.black : Colors.white,
decoration: _fieldDecoration('Email', isLight),
),
const SizedBox(height: 12),
TextField(
controller: _fullName,
style: TextStyle(color: isLight ? Colors.black : Colors.white),
cursorColor: isLight ? Colors.black : Colors.white,
decoration: _fieldDecoration('Full name', isLight),
),
],
const SizedBox(height: 12),
TextField(
controller: _password,
obscureText: true,
style: TextStyle(color: isLight ? Colors.black : Colors.white),
cursorColor: isLight ? Colors.black : Colors.white,
decoration: _fieldDecoration('Password', isLight),
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
child: Text(_signup ? 'Sign up' : 'Sign in'),
),
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
        const TextSpan(text: 'By signing up you agree to our '),
        TextSpan(
          text: 'Terms of Service',
          style: const TextStyle(color: Color(0xff1479ff), fontWeight: FontWeight.w600),
          recognizer: _termsRecognizer,
        ),
        const TextSpan(text: ' and '),
        TextSpan(
          text: 'Privacy Policy',
          style: const TextStyle(color: Color(0xff1479ff), fontWeight: FontWeight.w600),
          recognizer: _privacyRecognizer,
        ),
        const TextSpan(text: '.'),
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
    child: const Text(
      'Forgot password?',
      style: TextStyle(color: Color(0xff1479ff), fontWeight: FontWeight.w600),
    ),
  ),
],
TextButton(
onPressed: _loading
? null
: () {
setState(() => _signup = !_signup);
if (_signup && !_cityMapPrewarmed) {
_cityMapPrewarmed = true;
unawaited(prewarmCityMap(homeCity: '', isDark: Theme.of(context).brightness == Brightness.dark));
}
},
child: Text(
_signup
? 'Already have an account? Sign in'
: 'New here? Create an account',
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
fillColor: isLight ? Colors.white : const Color(0xff1e1e1e),
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

class _CityPickPage extends StatelessWidget {
const _CityPickPage({required this.token});

final String token;

@override
Widget build(BuildContext context) {
final isLight = Theme.of(context).brightness == Brightness.light;
return Scaffold(
backgroundColor: isLight ? Colors.white : const Color(0xff121212),
body: SafeArea(
child: Stack(
children: [
CityMapView(
token: token,
homeCity: '',
isSignUp: true,
onOpenUserProfile: (_) {},
onCitySelected: (city) {
Navigator.of(context).pop(city);
},
),
Positioned(
bottom: 56,
left: 20,
right: 20,
child: ClipRRect(
borderRadius: BorderRadius.circular(18),
child: BackdropFilter(
filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
child: Container(
padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
decoration: BoxDecoration(
color: Colors.black.withValues(alpha: 0.52),
borderRadius: BorderRadius.circular(18),
border: Border.all(
color: Colors.white.withValues(alpha: 0.12),
width: 0.8,
),
),
child: Row(
crossAxisAlignment: CrossAxisAlignment.center,
children: [
Container(
padding: const EdgeInsets.all(7),
decoration: BoxDecoration(
color: Colors.white.withValues(alpha: 0.12),
shape: BoxShape.circle,
),
child: const Icon(Icons.location_on_rounded, color: Color(0xffff4a4a), size: 20),
),
const SizedBox(width: 12),
const Expanded(
child: Text(
'Συνδεθείτε στο For You της περιοχής σας, πατώντας την πινέζα της.',
style: TextStyle(
color: Colors.white,
fontSize: 14,
height: 1.45,
fontWeight: FontWeight.w500,
letterSpacing: 0.1,
),
),
),
],
),
),
),
),
),
],
),
),
);
}
} 

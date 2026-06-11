import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../core/api.dart';
import '../core/models.dart';
import '../map/city_map_view.dart';

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key, required this.onAuthenticated});
  final ValueChanged<AuthSession> onAuthenticated;

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final _username = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _fullName = TextEditingController();
  bool _signup = false;
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _username.dispose();
    _email.dispose();
    _password.dispose();
    _fullName.dispose();
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
          widget.onAuthenticated(AuthSession(token: session.token, user: user));
        } else {
          widget.onAuthenticated(session);
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
      }
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xff121212),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'Neat',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 40,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 20),
                  TextField(
                    controller: _username,
                    style: const TextStyle(color: Colors.white),
                    cursorColor: Colors.white,
                    decoration: _fieldDecoration('Username'),
                  ),
                  if (_signup) ...[
                    const SizedBox(height: 12),
                    TextField(
                      controller: _email,
                      style: const TextStyle(color: Colors.white),
                      cursorColor: Colors.white,
                      decoration: _fieldDecoration('Email'),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _fullName,
                      style: const TextStyle(color: Colors.white),
                      cursorColor: Colors.white,
                      decoration: _fieldDecoration('Full name'),
                    ),
                  ],
                  const SizedBox(height: 12),
                  TextField(
                    controller: _password,
                    obscureText: true,
                    style: const TextStyle(color: Colors.white),
                    cursorColor: Colors.white,
                    decoration: _fieldDecoration('Password'),
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
                  TextButton(
                    onPressed: _loading
                        ? null
                        : () => setState(() => _signup = !_signup),
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

  InputDecoration _fieldDecoration(String label) {
    return InputDecoration(
      labelText: label,
      labelStyle: const TextStyle(color: Color(0xffb7b7b7)),
      filled: true,
      fillColor: const Color(0xff1e1e1e),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: Color(0xff2a2a2a)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: Color(0xff2a2a2a)),
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
    return Scaffold(
      backgroundColor: const Color(0xff121212),
      body: SafeArea(
        child: CityMapView(
          token: token,
          onOpenUserProfile: (_) {},
          onCitySelected: (city) {
            Navigator.of(context).pop(city);
          },
        ),
      ),
    );
  }
}

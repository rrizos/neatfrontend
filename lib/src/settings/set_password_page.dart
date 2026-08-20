import 'dart:convert';

import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../core/api.dart';
import '../core/http_client.dart' as http;
import '../core/models.dart';

/// Adds a password to an account that has none, or replaces the one it has.
///
/// The first case is the reason this screen exists: an account created through
/// Apple or Google has no usable password, which also means the
/// forgot-password flow will not touch it — so losing the provider account
/// meant losing this one, with nothing support could do. A password is the
/// second way in.
class SetPasswordPage extends StatefulWidget {
  const SetPasswordPage({
    super.key,
    required this.token,
    required this.hasPassword,
    required this.isLight,
    this.onSaved,
  });

  final String token;

  /// False for a provider-only account: no current password is asked for,
  /// because there is none to ask about.
  final bool hasPassword;
  final bool isLight;
  final ValueChanged<UserProfile>? onSaved;

  @override
  State<SetPasswordPage> createState() => _SetPasswordPageState();
}

class _SetPasswordPageState extends State<SetPasswordPage> {
  final _current = TextEditingController();
  final _next = TextEditingController();
  final _confirm = TextEditingController();
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _current.dispose();
    _next.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final l10n = AppLocalizations.of(context);
    if (_next.text != _confirm.text) {
      setState(() => _error = l10n.passwordsDoNotMatch);
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final res = await http
          .post(
            setPasswordEndpoint,
            headers: authJsonHeaders(widget.token),
            body: jsonEncode({
              'password': _next.text,
              if (widget.hasPassword) 'currentPassword': _current.text,
            }),
          )
          .timeout(const Duration(seconds: 20));
      if (!mounted) return;
      if (res.statusCode != 200) {
        // The server owns the password rules, so its wording is shown rather
        // than a local guess at which rule was broken.
        setState(() {
          _saving = false;
          _error = friendlyHttpError(res);
        });
        return;
      }
      final decoded = jsonDecode(res.body) as Map<String, dynamic>;
      widget.onSaved?.call(
        UserProfile.fromJson(decoded['user'] as Map<String, dynamic>),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(l10n.passwordSaved),
          behavior: SnackBarBehavior.floating,
        ),
      );
      Navigator.of(context).pop();
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
    final l10n = AppLocalizations.of(context);
    final isLight = widget.isLight;
    final fg = isLight ? Colors.black : Colors.white;
    final muted = isLight ? const Color(0xff6b7280) : const Color(0xff9a9a9a);

    return Scaffold(
      backgroundColor: isLight ? Colors.white : const Color(0xff000000),
      appBar: AppBar(
        backgroundColor: isLight ? Colors.white : const Color(0xff000000),
        foregroundColor: fg,
        elevation: 0,
        title: Text(
          widget.hasPassword ? l10n.changePasswordTitle : l10n.setPasswordTitle,
        ),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
          children: [
            Text(
              widget.hasPassword
                  ? l10n.changePasswordExplain
                  : l10n.setPasswordExplain,
              style: TextStyle(color: muted, fontSize: 14, height: 1.45),
            ),
            const SizedBox(height: 22),
            if (widget.hasPassword) ...[
              _field(_current, l10n.currentPasswordHint, fg, muted, isLight),
              const SizedBox(height: 14),
            ],
            _field(_next, l10n.newPasswordHint, fg, muted, isLight),
            const SizedBox(height: 14),
            _field(_confirm, l10n.confirmPasswordHint, fg, muted, isLight),
            if (_error != null) ...[
              const SizedBox(height: 14),
              Text(
                _error!,
                style: const TextStyle(color: Colors.redAccent, fontSize: 13.5),
              ),
            ],
            const SizedBox(height: 26),
            FilledButton(
              onPressed: _saving ? null : _save,
              child: Text(l10n.savePassword),
            ),
          ],
        ),
      ),
    );
  }

  Widget _field(
    TextEditingController controller,
    String hint,
    Color fg,
    Color muted,
    bool isLight,
  ) {
    return TextField(
      controller: controller,
      obscureText: true,
      enabled: !_saving,
      autocorrect: false,
      enableSuggestions: false,
      style: TextStyle(color: fg),
      decoration: InputDecoration(
        labelText: hint,
        labelStyle: TextStyle(color: muted),
        enabledBorder: OutlineInputBorder(
          borderSide: BorderSide(
            color: isLight ? const Color(0xffd6d9de) : const Color(0xff2a2a2a),
          ),
          borderRadius: BorderRadius.circular(12),
        ),
        focusedBorder: OutlineInputBorder(
          borderSide: BorderSide(color: fg),
          borderRadius: BorderRadius.circular(12),
        ),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }
}

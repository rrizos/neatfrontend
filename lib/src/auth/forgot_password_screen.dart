import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

import '../core/api.dart';
import '../core/models.dart';

class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({
    super.key,
    required this.onAuthenticated,
    required this.themeMode,
  });

  final ValueChanged<AuthSession> onAuthenticated;
  final ThemeMode themeMode;

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  int _step = 0; // 0=email  1=code  2=new password

  final _emailCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();

  // 6 separate OTP boxes
  final List<TextEditingController> _otpCtrls =
      List.generate(6, (_) => TextEditingController());
  final List<FocusNode> _otpFoci = List.generate(6, (_) => FocusNode());

  bool _loading = false;
  String? _error;
  bool _obscurePass = true;
  bool _obscureConfirm = true;

  int _resendSeconds = 0;
  Timer? _resendTimer;

  String get _otpCode => _otpCtrls.map((c) => c.text).join();

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passCtrl.dispose();
    _confirmCtrl.dispose();
    for (final c in _otpCtrls) { c.dispose(); }
    for (final f in _otpFoci) { f.dispose(); }
    _resendTimer?.cancel();
    super.dispose();
  }

  // ─── Helpers ───────────────────────────────────────────────────────────────

  bool get _isLight => widget.themeMode == ThemeMode.light;
  Color get _bg => _isLight ? const Color(0xfff3f4f6) : const Color(0xff121212);
  Color get _surface => _isLight ? Colors.white : const Color(0xff1e1e1e);
  Color get _text => _isLight ? Colors.black : Colors.white;
  Color get _sub => const Color(0xffa9a9a9);
  Color get _border => _isLight ? const Color(0xffd0d5dd) : const Color(0xff2a2a2a);

  void _startResendTimer() {
    _resendSeconds = 30;
    _resendTimer?.cancel();
    _resendTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) { t.cancel(); return; }
      setState(() {
        _resendSeconds--;
        if (_resendSeconds <= 0) t.cancel();
      });
    });
  }

  void _clearOtp() {
    for (final c in _otpCtrls) { c.clear(); }
  }

  // ─── Actions ───────────────────────────────────────────────────────────────

  Future<void> _sendCode() async {
    final email = _emailCtrl.text.trim();
    if (email.isEmpty) {
      setState(() => _error = 'Please enter your email');
      return;
    }
    setState(() { _loading = true; _error = null; });
    try {
      final res = await http.post(
        forgotPasswordEndpoint,
        headers: jsonHeaders,
        body: jsonEncode({'email': email}),
      );
      if (!mounted) return;
      if (res.statusCode != 200) throw Exception(friendlyHttpError(res));
      _clearOtp();
      setState(() { _step = 1; _loading = false; });
      _startResendTimer();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _otpFoci[0].requestFocus();
      });
    } catch (e) {
      if (mounted) setState(() { _error = e.toString().replaceFirst('Exception: ', ''); _loading = false; });
    }
  }

  void _confirmCode() {
    if (_otpCode.length < 6) {
      setState(() => _error = 'Please enter all 6 digits');
      return;
    }
    setState(() { _step = 2; _error = null; });
  }

  Future<void> _resetPassword() async {
    final pass = _passCtrl.text;
    final confirm = _confirmCtrl.text;
    if (pass.length < 8) {
      setState(() => _error = 'Password must be at least 8 characters');
      return;
    }
    if (pass != confirm) {
      setState(() => _error = "Passwords don't match");
      return;
    }
    setState(() { _loading = true; _error = null; });
    try {
      final res = await http.post(
        resetPasswordEndpoint,
        headers: jsonHeaders,
        body: jsonEncode({
          'email': _emailCtrl.text.trim(),
          'code': _otpCode,
          'newPassword': pass,
        }),
      );
      if (!mounted) return;
      if (res.statusCode != 200) {
        // Wrong code → send user back to code step
        final err = friendlyHttpError(res);
        setState(() { _error = err; _loading = false; });
        if (err.toLowerCase().contains('code') || err.toLowerCase().contains('expired')) {
          setState(() => _step = 1);
        }
        return;
      }
      final session = AuthSession.fromJson(jsonDecode(res.body) as Map<String, dynamic>);
      if (mounted && Navigator.of(context).canPop()) {
        Navigator.of(context).popUntil((r) => r.isFirst);
      }
      widget.onAuthenticated(session);
    } catch (e) {
      if (mounted) setState(() { _error = e.toString().replaceFirst('Exception: ', ''); _loading = false; });
    }
  }

  void _goBack() {
    if (_step > 0) {
      setState(() { _step--; _error = null; });
    } else {
      Navigator.of(context).pop();
    }
  }

  // ─── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _bg,
        surfaceTintColor: _bg,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios_new_rounded, color: _text, size: 20),
          onPressed: _goBack,
        ),
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(28, 8, 28, 40),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 260),
                transitionBuilder: (child, anim) {
                  return FadeTransition(
                    opacity: CurvedAnimation(parent: anim, curve: Curves.easeOut),
                    child: SlideTransition(
                      position: Tween(
                        begin: const Offset(0.04, 0),
                        end: Offset.zero,
                      ).animate(CurvedAnimation(parent: anim, curve: Curves.easeOut)),
                      child: child,
                    ),
                  );
                },
                child: KeyedSubtree(
                  key: ValueKey(_step),
                  child: _buildStep(),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStep() {
    switch (_step) {
      case 0: return _EmailStep(
        emailCtrl: _emailCtrl,
        loading: _loading,
        error: _error,
        onSend: _sendCode,
        isLight: _isLight,
        bg: _bg,
        surface: _surface,
        textColor: _text,
        subColor: _sub,
        border: _border,
      );
      case 1: return _CodeStep(
        email: _emailCtrl.text.trim(),
        otpCtrls: _otpCtrls,
        otpFoci: _otpFoci,
        loading: _loading,
        error: _error,
        resendSeconds: _resendSeconds,
        onVerify: _confirmCode,
        onResend: _sendCode,
        isLight: _isLight,
        surface: _surface,
        textColor: _text,
        subColor: _sub,
        border: _border,
      );
      case 2: return _PasswordStep(
        passCtrl: _passCtrl,
        confirmCtrl: _confirmCtrl,
        loading: _loading,
        error: _error,
        obscurePass: _obscurePass,
        obscureConfirm: _obscureConfirm,
        onTogglePass: () => setState(() => _obscurePass = !_obscurePass),
        onToggleConfirm: () => setState(() => _obscureConfirm = !_obscureConfirm),
        onSubmit: _resetPassword,
        isLight: _isLight,
        surface: _surface,
        textColor: _text,
        subColor: _sub,
        border: _border,
      );
      default: return const SizedBox.shrink();
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Step 0 — Email entry
// ─────────────────────────────────────────────────────────────────────────────

class _EmailStep extends StatelessWidget {
  const _EmailStep({
    required this.emailCtrl,
    required this.loading,
    required this.error,
    required this.onSend,
    required this.isLight,
    required this.bg,
    required this.surface,
    required this.textColor,
    required this.subColor,
    required this.border,
  });

  final TextEditingController emailCtrl;
  final bool loading;
  final String? error;
  final VoidCallback onSend;
  final bool isLight;
  final Color bg, surface, textColor, subColor, border;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 8),
        Image.asset(
          'assets/neat_logo.png',
          height: 80,
          color: isLight ? Colors.black : Colors.white,
          colorBlendMode: BlendMode.srcIn,
        ),
        const SizedBox(height: 28),
        Text(
          'Forgot password?',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: textColor,
            fontSize: 26,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.5,
          ),
        ),
        const SizedBox(height: 10),
        Text(
          "Enter your email or username and we'll\nsend a code to your email.",
          textAlign: TextAlign.center,
          style: TextStyle(color: subColor, fontSize: 14, height: 1.55),
        ),
        const SizedBox(height: 32),
        TextField(
          controller: emailCtrl,
          keyboardType: TextInputType.text,
          autocorrect: false,
          textInputAction: TextInputAction.done,
          style: TextStyle(color: textColor),
          cursorColor: const Color(0xff1479ff),
          onSubmitted: (_) => loading ? null : onSend(),
          decoration: _deco('Email or username', surface, border),
        ),
        if (error != null) _errorWidget(error!),
        const SizedBox(height: 20),
        _PrimaryBtn(label: 'Send code', loading: loading, onPressed: onSend),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Step 1 — OTP code entry
// ─────────────────────────────────────────────────────────────────────────────

class _CodeStep extends StatelessWidget {
  const _CodeStep({
    required this.email,
    required this.otpCtrls,
    required this.otpFoci,
    required this.loading,
    required this.error,
    required this.resendSeconds,
    required this.onVerify,
    required this.onResend,
    required this.isLight,
    required this.surface,
    required this.textColor,
    required this.subColor,
    required this.border,
  });

  final String email;
  final List<TextEditingController> otpCtrls;
  final List<FocusNode> otpFoci;
  final bool loading;
  final String? error;
  final int resendSeconds;
  final VoidCallback onVerify;
  final VoidCallback onResend;
  final bool isLight;
  final Color surface, textColor, subColor, border;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 8),
        Center(
          child: Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              color: const Color(0xff1479ff).withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.mark_email_read_outlined, color: Color(0xff1479ff), size: 34),
          ),
        ),
        const SizedBox(height: 24),
        Text(
          'Check your email',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: textColor,
            fontSize: 26,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.5,
          ),
        ),
        const SizedBox(height: 10),
        Text.rich(
          TextSpan(
            text: "We sent a 6-digit code to\n",
            style: TextStyle(color: subColor, fontSize: 14, height: 1.55),
            children: [
              TextSpan(
                text: email,
                style: TextStyle(color: textColor, fontWeight: FontWeight.w600),
              ),
            ],
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 32),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: List.generate(6, (i) => _OtpBox(
            controller: otpCtrls[i],
            focusNode: otpFoci[i],
            prevFocus: i > 0 ? otpFoci[i - 1] : null,
            nextFocus: i < 5 ? otpFoci[i + 1] : null,
            prevCtrl: i > 0 ? otpCtrls[i - 1] : null,
            isLight: isLight,
            surface: surface,
            textColor: textColor,
            border: border,
          )),
        ),
        if (error != null) _errorWidget(error!),
        const SizedBox(height: 20),
        _PrimaryBtn(label: 'Verify', loading: loading, onPressed: onVerify),
        const SizedBox(height: 18),
        Center(
          child: resendSeconds > 0
              ? Text(
                  'Resend code in ${resendSeconds}s',
                  style: TextStyle(color: subColor, fontSize: 13),
                )
              : GestureDetector(
                  onTap: loading ? null : onResend,
                  child: const Text(
                    'Resend code',
                    style: TextStyle(
                      color: Color(0xff1479ff),
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
        ),
      ],
    );
  }
}

// Single OTP box
class _OtpBox extends StatelessWidget {
  const _OtpBox({
    required this.controller,
    required this.focusNode,
    required this.prevFocus,
    required this.nextFocus,
    required this.prevCtrl,
    required this.isLight,
    required this.surface,
    required this.textColor,
    required this.border,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final FocusNode? prevFocus;
  final FocusNode? nextFocus;
  final TextEditingController? prevCtrl;
  final bool isLight;
  final Color surface, textColor, border;

  @override
  Widget build(BuildContext context) {
    return Focus(
      onKeyEvent: (_, event) {
        if (event is KeyDownEvent &&
            event.logicalKey == LogicalKeyboardKey.backspace &&
            controller.text.isEmpty &&
            prevFocus != null) {
          prevCtrl?.clear();
          prevFocus!.requestFocus();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: SizedBox(
        width: 48,
        height: 58,
        child: TextField(
          controller: controller,
          focusNode: focusNode,
          keyboardType: TextInputType.number,
          textAlign: TextAlign.center,
          inputFormatters: [
            FilteringTextInputFormatter.digitsOnly,
            LengthLimitingTextInputFormatter(1),
          ],
          style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: textColor),
          cursorColor: const Color(0xff1479ff),
          decoration: InputDecoration(
            counterText: '',
            filled: true,
            fillColor: surface,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide(color: border),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide(color: border),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(color: Color(0xff1479ff), width: 2),
            ),
          ),
          onChanged: (val) {
            if (val.isNotEmpty && nextFocus != null) {
              nextFocus!.requestFocus();
            }
          },
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Step 2 — New password
// ─────────────────────────────────────────────────────────────────────────────

class _PasswordStep extends StatelessWidget {
  const _PasswordStep({
    required this.passCtrl,
    required this.confirmCtrl,
    required this.loading,
    required this.error,
    required this.obscurePass,
    required this.obscureConfirm,
    required this.onTogglePass,
    required this.onToggleConfirm,
    required this.onSubmit,
    required this.isLight,
    required this.surface,
    required this.textColor,
    required this.subColor,
    required this.border,
  });

  final TextEditingController passCtrl;
  final TextEditingController confirmCtrl;
  final bool loading;
  final String? error;
  final bool obscurePass;
  final bool obscureConfirm;
  final VoidCallback onTogglePass;
  final VoidCallback onToggleConfirm;
  final VoidCallback onSubmit;
  final bool isLight;
  final Color surface, textColor, subColor, border;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 8),
        Center(
          child: Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              color: const Color(0xff1479ff).withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.lock_reset_rounded, color: Color(0xff1479ff), size: 32),
          ),
        ),
        const SizedBox(height: 24),
        Text(
          'Create new password',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: textColor,
            fontSize: 26,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.5,
          ),
        ),
        const SizedBox(height: 10),
        Text(
          'Must be at least 8 characters.',
          textAlign: TextAlign.center,
          style: TextStyle(color: subColor, fontSize: 14, height: 1.55),
        ),
        const SizedBox(height: 32),
        TextField(
          controller: passCtrl,
          obscureText: obscurePass,
          textInputAction: TextInputAction.next,
          style: TextStyle(color: textColor),
          cursorColor: const Color(0xff1479ff),
          decoration: _deco('New password', surface, border).copyWith(
            suffixIcon: IconButton(
              icon: Icon(
                obscurePass ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                color: subColor,
                size: 20,
              ),
              onPressed: onTogglePass,
            ),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: confirmCtrl,
          obscureText: obscureConfirm,
          textInputAction: TextInputAction.done,
          style: TextStyle(color: textColor),
          cursorColor: const Color(0xff1479ff),
          onSubmitted: (_) => loading ? null : onSubmit(),
          decoration: _deco('Confirm password', surface, border).copyWith(
            suffixIcon: IconButton(
              icon: Icon(
                obscureConfirm ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                color: subColor,
                size: 20,
              ),
              onPressed: onToggleConfirm,
            ),
          ),
        ),
        if (error != null) _errorWidget(error!),
        const SizedBox(height: 20),
        _PrimaryBtn(label: 'Reset password', loading: loading, onPressed: onSubmit),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Shared widgets
// ─────────────────────────────────────────────────────────────────────────────

class _PrimaryBtn extends StatelessWidget {
  const _PrimaryBtn({required this.label, required this.loading, required this.onPressed});
  final String label;
  final bool loading;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return FilledButton(
      onPressed: loading ? null : onPressed,
      style: FilledButton.styleFrom(
        backgroundColor: const Color(0xff1479ff),
        disabledBackgroundColor: const Color(0xff1479ff).withValues(alpha: 0.5),
        foregroundColor: Colors.white,
        minimumSize: const Size(double.infinity, 52),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
      ),
      child: loading
          ? const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white),
            )
          : Text(label),
    );
  }
}

Widget _errorWidget(String error) => Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Text(
        error,
        textAlign: TextAlign.center,
        style: const TextStyle(color: Color(0xffff4d4d), fontSize: 13, height: 1.4),
      ),
    );

InputDecoration _deco(String label, Color surface, Color border) => InputDecoration(
      labelText: label,
      labelStyle: const TextStyle(color: Color(0xffa9a9a9)),
      filled: true,
      fillColor: surface,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: Color(0xff1479ff), width: 2),
      ),
    );

import 'dart:async';

import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../core/models.dart';
import 'app_intro_page.dart';
import 'auth_screen.dart';

class LandingPage extends StatefulWidget {
  const LandingPage({
    super.key,
    required this.onAuthenticated,
    required this.themeMode,
  });

  final ValueChanged<AuthSession> onAuthenticated;
  final ThemeMode themeMode;

  @override
  State<LandingPage> createState() => _LandingPageState();
}

class _LandingPageState extends State<LandingPage> {
  String _slogan = '';

  int _visibleChars = 0;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    Future.delayed(const Duration(milliseconds: 600), _startTyping);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _slogan = AppLocalizations.of(context).landingSlogan;
  }

  void _startTyping() {
    _timer = Timer.periodic(const Duration(milliseconds: 38), (t) {
      if (!mounted) { t.cancel(); return; }
      if (_visibleChars >= _slogan.length) {
        t.cancel();
        return;
      }
      setState(() => _visibleChars++);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  // Sign-up goes through the intro screen first ("here's what Neat is"), and
  // only then to the credentials form; sign-in jumps straight to the form.
  void _go({required bool signup}) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => signup
            ? AppIntroPage(
                onAuthenticated: widget.onAuthenticated,
                themeMode: widget.themeMode,
              )
            : AuthScreen(
                onAuthenticated: widget.onAuthenticated,
                themeMode: widget.themeMode,
              ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isLight = widget.themeMode == ThemeMode.light;
    final bg = isLight ? Colors.white : const Color(0xff000000);
    final fg = isLight ? Colors.black : Colors.white;

    return Scaffold(
      backgroundColor: bg,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Spacer(flex: 3),
              Image.asset(
                'assets/neat_logo.png',
                height: 110,
                color: fg,
                colorBlendMode: BlendMode.srcIn,
              ),
              const SizedBox(height: 28),
              _TypingText(
                fullText: _slogan,
                visibleChars: _visibleChars,
                style: TextStyle(
                  color: fg.withValues(alpha: 0.65),
                  fontSize: 15,
                  height: 1.55,
                ),
              ),
              const Spacer(flex: 4),
              FilledButton(
                onPressed: () => _go(signup: true),
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xff5B6CF6),
                  foregroundColor: Colors.white,
                  minimumSize: const Size.fromHeight(52),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: Text(
                  AppLocalizations.of(context).signUp,
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                ),
              ),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: () => _go(signup: false),
                style: FilledButton.styleFrom(
                  backgroundColor: isLight
                      ? const Color(0xffe0e0e0)
                      : const Color(0xff141414),
                  foregroundColor: fg,
                  minimumSize: const Size.fromHeight(52),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: Text(
                  AppLocalizations.of(context).signIn,
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                ),
              ),
              const SizedBox(height: 28),
            ],
          ),
        ),
      ),
    );
  }
}

class _TypingText extends StatelessWidget {
  const _TypingText({
    required this.fullText,
    required this.visibleChars,
    required this.style,
  });

  final String fullText;
  final int visibleChars;
  final TextStyle style;

  @override
  Widget build(BuildContext context) {
    final shown = fullText.substring(0, visibleChars.clamp(0, fullText.length));
    final cursor = visibleChars < fullText.length ? '|' : '';
    return Text(
      '$shown$cursor',
      textAlign: TextAlign.center,
      style: style,
    );
  }
}

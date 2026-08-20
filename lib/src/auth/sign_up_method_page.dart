import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../core/models.dart';
import '../core/onboarding_ui.dart';
import 'auth_screen.dart';
import 'social_buttons.dart';

/// Sign-up step 2 — how, before who.
///
/// Sits between the intro and the credentials form. Apple is offered only on
/// Apple's own platforms, and only when the device can actually do it; Google
/// everywhere; email always, because it is the one that cannot be taken away
/// by a provider outage or a device that has never been signed in to either.
///
/// Whichever is chosen, the session that comes back is an ordinary one whose
/// user has no city yet — so all three routes converge on the map.
class SignUpMethodPage extends StatefulWidget {
  const SignUpMethodPage({
    super.key,
    required this.onAuthenticated,
    required this.themeMode,
  });

  final ValueChanged<AuthSession> onAuthenticated;
  final ThemeMode themeMode;

  @override
  State<SignUpMethodPage> createState() => _SignUpMethodPageState();
}

class _SignUpMethodPageState extends State<SignUpMethodPage> {
  bool _busy = false;

  void _openEmailForm({required bool signup}) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => AuthScreen(
          onAuthenticated: widget.onAuthenticated,
          themeMode: widget.themeMode,
          initialSignup: signup,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final isLight = widget.themeMode == ThemeMode.light;
    final fg = onboardingFg(isLight);

    return Scaffold(
      backgroundColor: isLight ? Colors.white : const Color(0xff000000),
      body: SafeArea(
        child: Column(
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: IconButton(
                onPressed: _busy ? null : () => Navigator.of(context).maybePop(),
                icon: Icon(Icons.arrow_back_rounded, color: fg),
              ),
            ),
            Expanded(
              child: OnboardingBody(
                children: [
                  // The mark carries the screen; the words underneath only
                  // have to say what happens next. Centred as a block, which
                  // is why this does not use OnboardingHeadline — that one is
                  // left-aligned for screens where copy leads.
                  Image.asset(
                    'assets/neat_logo.png',
                    height: 76,
                    color: fg,
                    colorBlendMode: BlendMode.srcIn,
                  ),
                  const SizedBox(height: 30),
                  Text(
                    l10n.signUpMethodTitle,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: fg,
                      fontSize: 25,
                      fontWeight: FontWeight.w700,
                      height: 1.2,
                      letterSpacing: -0.5,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    l10n.signUpMethodSubtitle,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: onboardingMuted(isLight),
                      fontSize: 14.5,
                      height: 1.45,
                    ),
                  ),
                ],
              ),
            ),
            OnboardingFooter(
              children: [
                SocialSignInButtons(
                  isLight: isLight,
                  onAuthenticated: widget.onAuthenticated,
                  onBusyChanged: (busy) => setState(() => _busy = busy),
                ),
                const SizedBox(height: 12),
                ProviderButton(
                  label: l10n.signUpWithEmail,
                  isLight: isLight,
                  enabled: !_busy,
                  icon: Icon(Icons.mail_outline_rounded,
                      size: 20, color: isLight ? Colors.black : Colors.white),
                  onPressed: () => _openEmailForm(signup: true),
                ),
                const SizedBox(height: 18),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      l10n.signUpMethodHaveAccount,
                      style: TextStyle(
                          color: onboardingMuted(isLight), fontSize: 13.5),
                    ),
                    TextButton(
                      onPressed:
                          _busy ? null : () => _openEmailForm(signup: false),
                      child: Text(
                        l10n.signUpMethodSignIn,
                        style: TextStyle(
                          color: fg,
                          fontSize: 13.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

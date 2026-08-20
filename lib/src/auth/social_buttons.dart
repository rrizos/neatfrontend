import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../l10n/app_localizations.dart';
import '../core/api.dart';
import '../core/models.dart';
import '../core/onboarding_ui.dart';
import 'social_sign_in.dart';

/// The Apple and Google buttons, wherever they appear.
///
/// Shared between signing up and signing in because to the server they are the
/// same act: it cannot tell from a provider identity whether this person has
/// been here before, and neither can the app. Somebody who created their
/// account with Google taps the same button to get back into it.
class SocialSignInButtons extends StatefulWidget {
  const SocialSignInButtons({
    super.key,
    required this.isLight,
    required this.onAuthenticated,
    this.onBusyChanged,
  });

  final bool isLight;
  final ValueChanged<AuthSession> onAuthenticated;

  /// Lets the surrounding form disable itself while a provider sheet is up.
  final ValueChanged<bool>? onBusyChanged;

  @override
  State<SocialSignInButtons> createState() => _SocialSignInButtonsState();
}

class _SocialSignInButtonsState extends State<SocialSignInButtons> {
  bool _busy = false;
  bool _appleAvailable = false;

  @override
  void initState() {
    super.initState();
    // Asked rather than assumed: Sign in with Apple needs the capability in
    // the build and an Apple account on the device.
    appleSignInAvailable().then((available) {
      if (mounted) setState(() => _appleAvailable = available);
    });
  }

  void _setBusy(bool value) {
    if (!mounted) return;
    setState(() => _busy = value);
    widget.onBusyChanged?.call(value);
  }

  Future<void> _run(Future<AuthSession> Function() flow) async {
    if (_busy) return;
    _setBusy(true);
    try {
      final session = await flow();
      if (!mounted) return;
      // Back to the root before handing the session over: AuthGate swaps its
      // home when a session arrives, and anything still pushed on top would
      // hide the screen that replaces it.
      if (Navigator.of(context).canPop()) {
        Navigator.of(context).popUntil((r) => r.isFirst);
      }
      widget.onAuthenticated(session);
    } on SocialSignInCancelled {
      // Backing out of the provider's sheet is a normal thing to do.
      _setBusy(false);
    } on SocialSignInError catch (e) {
      if (!mounted) return;
      _setBusy(false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.message),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final isLight = widget.isLight;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_appleAvailable) ...[
          ProviderButton(
            label: l10n.signUpWithApple,
            isLight: isLight,
            enabled: !_busy,
            icon: SvgPicture.asset(
              'assets/apple_logo.svg',
              width: 21,
              height: 21,
              colorFilter: ColorFilter.mode(
                isLight ? Colors.black : Colors.white,
                BlendMode.srcIn,
              ),
            ),
            onPressed: () => _run(signInWithApple),
          ),
          const SizedBox(height: 12),
        ],
        ProviderButton(
          label: l10n.signUpWithGoogle,
          isLight: isLight,
          enabled: !_busy,
          icon: SvgPicture.asset('assets/google_g.svg', width: 20, height: 20),
          onPressed: () {
            if (!googleSignInConfigured) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(l10n.signUpGoogleUnavailable),
                  behavior: SnackBarBehavior.floating,
                ),
              );
              return;
            }
            _run(signInWithGoogle);
          },
        ),
      ],
    );
  }
}

/// A hairline with a word in it, separating the password form from the
/// provider buttons.
class AuthOrDivider extends StatelessWidget {
  const AuthOrDivider({super.key, required this.isLight});

  final bool isLight;

  @override
  Widget build(BuildContext context) {
    final line = isLight ? const Color(0xffe3e6ea) : const Color(0xff262626);
    return Row(
      children: [
        Expanded(child: Divider(color: line, height: 1)),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Text(
            AppLocalizations.of(context).authOr,
            style: TextStyle(color: onboardingMuted(isLight), fontSize: 12.5),
          ),
        ),
        Expanded(child: Divider(color: line, height: 1)),
      ],
    );
  }
}

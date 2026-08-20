import 'dart:async';

import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../core/models.dart';
import '../map/city_map_view.dart';
import 'sign_up_method_page.dart';
import '../core/onboarding_ui.dart';

/// Sign-up step 1 of 3 — shown right after the landing page's "Sign up",
/// before the user types anything. Says in three lines what Neat is, then
/// hands off to [SignUpMethodPage], where they pick how to sign up.
class AppIntroPage extends StatefulWidget {
  const AppIntroPage({
    super.key,
    required this.onAuthenticated,
    required this.themeMode,
  });

  final ValueChanged<AuthSession> onAuthenticated;
  final ThemeMode themeMode;

  @override
  State<AppIntroPage> createState() => _AppIntroPageState();
}

class _AppIntroPageState extends State<AppIntroPage> {
  bool _cityMapPrewarmed = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // The whole sign-up flow ends on the map, so start building it here —
    // this screen plus the form is the longest stretch of user reading and
    // typing in the app, and it hides the mapkit.js parse entirely.
    if (!_cityMapPrewarmed) {
      _cityMapPrewarmed = true;
      unawaited(prewarmCityMap(
        homeCity: '',
        isDark: Theme.of(context).brightness == Brightness.dark,
      ));
    }
  }

  void _continue() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => SignUpMethodPage(
          onAuthenticated: widget.onAuthenticated,
          themeMode: widget.themeMode,
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
                onPressed: () => Navigator.of(context).maybePop(),
                icon: Icon(Icons.arrow_back_rounded, color: fg),
              ),
            ),
            Expanded(
              child: OnboardingBody(
                children: [
                  // Sits inside the centred block rather than pinned to the
                  // top bar, so it reads as part of the message.
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Image.asset(
                      'assets/neat_logo.png',
                      height: 48,
                      color: fg,
                      colorBlendMode: BlendMode.srcIn,
                    ),
                  ),
                  const SizedBox(height: 30),
                  OnboardingHeadline(
                    title: l10n.introTitle,
                    subtitle: l10n.introSubtitle,
                    isLight: isLight,
                  ),
                  const SizedBox(height: 36),
                  // The nav bar's own icons, so the three promises point at
                  // places the user will recognise once they're inside.
                  OnboardingPoint(
                    icon: Icons.home_outlined,
                    title: l10n.introLocalFeedTitle,
                    body: l10n.introLocalFeedBody,
                    isLight: isLight,
                  ),
                  const SizedBox(height: 26),
                  OnboardingPoint(
                    icon: Icons.mode_comment_outlined,
                    title: l10n.introEngagementTitle,
                    body: l10n.introEngagementBody,
                    isLight: isLight,
                  ),
                  const SizedBox(height: 26),
                  OnboardingPoint(
                    icon: Icons.map_outlined,
                    title: l10n.introExploreTitle,
                    body: l10n.introExploreBody,
                    isLight: isLight,
                  ),
                ],
              ),
            ),
            OnboardingFooter(
              children: [
                OnboardingButton(
                  label: l10n.introContinue,
                  onPressed: _continue,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';

// Shared building blocks for the app's onboarding screens — the two sign-up
// steps and the spectator-mode introduction.
//
// Both follow the same rules as the rest of the app: the plain scaffold
// background (white / #121212), the app's own nav-bar icon set, and the
// landing page's button. No cards, no borders, no gradients — hierarchy comes
// from type weight and whitespace.

const kOnboardingAccent = Color(0xff5B6CF6);

Color onboardingFg(bool isLight) => isLight ? Colors.black : Colors.white;

Color onboardingMuted(bool isLight) =>
    isLight ? const Color(0xff6b7280) : const Color(0xffb7b7b7);

/// The scrolling middle of an onboarding screen.
///
/// Vertically centred while the content fits — which is the normal case and
/// what stops these screens reading as a top-heavy wall of text — and
/// scrollable the moment large text settings or a short screen make it taller
/// than the viewport.
class OnboardingBody extends StatelessWidget {
  const OnboardingBody({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 24, 24, 24),
        child: ConstrainedBox(
          // Minus the padding, so "fits exactly" doesn't start a scroll.
          constraints: BoxConstraints(minHeight: constraints.maxHeight - 48),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: children,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The pinned bottom block: optional microcopy plus the primary button.
class OnboardingFooter extends StatelessWidget {
  const OnboardingFooter({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: children,
          ),
        ),
      ),
    );
  }
}

/// Screen headline plus its supporting line.
class OnboardingHeadline extends StatelessWidget {
  const OnboardingHeadline({
    super.key,
    required this.title,
    required this.subtitle,
    required this.isLight,
  });

  final String title;
  final String subtitle;
  final bool isLight;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: TextStyle(
            color: onboardingFg(isLight),
            fontSize: 26,
            fontWeight: FontWeight.w700,
            height: 1.2,
            letterSpacing: -0.5,
          ),
        ),
        const SizedBox(height: 10),
        Text(
          subtitle,
          style: TextStyle(
            color: onboardingMuted(isLight),
            fontSize: 15,
            height: 1.45,
          ),
        ),
      ],
    );
  }
}

/// One "icon + label + line of explanation" row. Deliberately unboxed — a
/// plain row reads as part of the app, a bordered card reads as a brochure.
class OnboardingPoint extends StatelessWidget {
  const OnboardingPoint({
    super.key,
    required this.icon,
    required this.title,
    required this.body,
    required this.isLight,
  });

  final IconData icon;
  final String title;
  final String body;
  final bool isLight;

  @override
  Widget build(BuildContext context) {
    final fg = onboardingFg(isLight);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 1),
          child: Icon(icon, size: 24, color: fg),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  color: fg,
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                body,
                style: TextStyle(
                  color: onboardingMuted(isLight),
                  fontSize: 13.5,
                  height: 1.4,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// The same button the landing page uses, so the flow keeps one primary
/// action style from "Sign up" all the way to the map.
class OnboardingButton extends StatelessWidget {
  const OnboardingButton({
    super.key,
    required this.label,
    required this.onPressed,
  });

  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return FilledButton(
      onPressed: onPressed,
      style: FilledButton.styleFrom(
        backgroundColor: kOnboardingAccent,
        foregroundColor: Colors.white,
        minimumSize: const Size.fromHeight(52),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      child: Text(
        label,
        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
      ),
    );
  }
}

/// A provider button in the app's own shape, for the providers that do not
/// ship one. Deliberately the same height and radius as Apple's so the three
/// read as one stack rather than three borrowed styles.
class ProviderButton extends StatelessWidget {
  const ProviderButton({
    super.key,
    required this.label,
    required this.icon,
    required this.isLight,
    required this.enabled,
    required this.onPressed,
  });

  final String label;
  final Widget icon;
  final bool isLight;
  final bool enabled;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final fg = isLight ? Colors.black : Colors.white;
    return Opacity(
      opacity: enabled ? 1 : 0.5,
      child: SizedBox(
        height: 52,
        width: double.infinity,
        child: OutlinedButton(
          onPressed: enabled ? onPressed : null,
          style: OutlinedButton.styleFrom(
            backgroundColor: isLight ? Colors.white : const Color(0xff0d0d0d),
            side: BorderSide(
              color: isLight ? const Color(0xffd6d9de) : const Color(0xff2a2a2a),
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              icon,
              const SizedBox(width: 10),
              Text(
                label,
                style: TextStyle(
                  color: fg,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

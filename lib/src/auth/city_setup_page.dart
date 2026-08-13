import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../map/city_map_view.dart';
import '../map/map_snapshot.dart';
import '../core/onboarding_ui.dart';

/// Sign-up step 3 of 3 — the account exists, but the user has no home city
/// yet. Explains that the city they pick is the *only* one they can post in,
/// then opens the map to pick it.
///
/// The map behind the copy is a still image ([CityMapSnapshot]), not the live
/// map. Embedding the interactive platform view under a full-screen Flutter
/// layer is what left it unable to pan on iOS; an image has no gestures to
/// lose. The real map is warmed in parallel from the intro screen
/// ([prewarmCityMap]) and gets a screen of its own, with nothing drawn over
/// it, when the user taps through.
///
/// Pops with the chosen city name (never with null: the step is mandatory, so
/// there is no back affordance and the system back gesture is blocked).
class CitySetupPage extends StatefulWidget {
  const CitySetupPage({
    super.key,
    required this.token,
    required this.themeMode,
  });

  final String token;
  final ThemeMode themeMode;

  @override
  State<CitySetupPage> createState() => _CitySetupPageState();
}

class _CitySetupPageState extends State<CitySetupPage> {
  Uint8List? _mapImage;
  bool _snapshotRequested = false;
  // Settled = we know whether there will ever be an image. Until then the hero
  // holds its space so the copy doesn't jump when the snapshot lands; after a
  // failure (offline, or a platform with no snapshotter) the hero is dropped
  // entirely rather than left as an empty grey band.
  bool _snapshotSettled = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_snapshotRequested) return;
    _snapshotRequested = true;
    final media = MediaQuery.of(context);
    CityMapSnapshot.load(
      // Rendered at the hero's own size rather than the whole screen.
      size: Size(media.size.width, media.size.height * _heroFraction),
      devicePixelRatio: media.devicePixelRatio,
      isDark: widget.themeMode != ThemeMode.light,
    ).then((bytes) {
      if (!mounted) return;
      setState(() {
        _mapImage = bytes;
        _snapshotSettled = true;
      });
    });
  }

  Future<void> _openMap() async {
    final city = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => _CityPickPage(token: widget.token)),
    );
    // Backing out of the map lands here again rather than anywhere further
    // back — this screen is the flow's floor until a city exists.
    if (!mounted || city == null || city.isEmpty) return;
    Navigator.of(context).pop(city);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final isLight = widget.themeMode == ThemeMode.light;
    final background = isLight ? Colors.white : const Color(0xff121212);

    return PopScope(
      // The account is already created at this point — dropping back to the
      // form would leave the user signed up with no city and no session.
      canPop: false,
      child: Scaffold(
        backgroundColor: background,
        // No top SafeArea: the map runs under the status bar.
        body: Column(
          children: [
            if (_mapImage != null || !_snapshotSettled || AndroidCityMapHero.isSupported)
              _MapHero(
                image: _mapImage,
                background: background,
                isLight: isLight,
                height: MediaQuery.sizeOf(context).height * _heroFraction,
              ),
            Expanded(
              child: OnboardingBody(
                children: [
                  OnboardingHeadline(
                    title: l10n.citySetupTitle,
                    subtitle: l10n.citySetupSubtitle,
                    isLight: isLight,
                  ),
                  const SizedBox(height: 32),
                  OnboardingPoint(
                    icon: Icons.place_outlined,
                    title: l10n.citySetupHomeCityTitle,
                    body: l10n.citySetupHomeCityBody,
                    isLight: isLight,
                  ),
                  const SizedBox(height: 26),
                  OnboardingPoint(
                    icon: Icons.do_not_disturb_on_outlined,
                    title: l10n.citySetupElsewhereTitle,
                    body: l10n.citySetupElsewhereBody,
                    isLight: isLight,
                  ),
                ],
              ),
            ),
            SafeArea(
              top: false,
              child: OnboardingFooter(
                children: [
                  Text(
                    l10n.citySetupMicrocopy,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: onboardingMuted(isLight),
                      fontSize: 12.5,
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 14),
                  OnboardingButton(
                    label: l10n.citySetupCta,
                    onPressed: _openMap,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

const _heroFraction = 0.34;

/// The map, as a picture, with a single pin standing in for the one city the
/// user is about to claim — the whole point of the screen. It fades into the
/// scaffold background so the copy below sits on plain colour.
class _MapHero extends StatelessWidget {
  const _MapHero({
    required this.image,
    required this.background,
    required this.isLight,
    required this.height,
  });

  final Uint8List? image;
  final Color background;
  final bool isLight;
  final double height;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      width: double.infinity,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Holds the space in the app's own colours until (or if) the
          // snapshot arrives — offline, or on Android, this is all there is.
          ColoredBox(
            color: isLight ? const Color(0xfff2f3f5) : const Color(0xff1a1c22),
          ),
          // Android has no snapshotter, so it draws the live map instead —
          // held still and deaf to touches. See AndroidCityMapHero.
          if (AndroidCityMapHero.isSupported)
            AndroidCityMapHero(isDark: !isLight)
          else if (image != null)
            Image.memory(
              image!,
              fit: BoxFit.cover,
              gaplessPlayback: true,
              errorBuilder: (context, error, stack) => const SizedBox.shrink(),
            ),
          // Dims it and melts the bottom edge into the page. The fade stops
          // just short of opaque at the very bottom so MapKit's required
          // "Apple Maps" attribution, baked into the snapshot's bottom-left
          // corner, stays legible.
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  background.withValues(alpha: isLight ? 0.30 : 0.42),
                  background.withValues(alpha: isLight ? 0.16 : 0.26),
                  background.withValues(alpha: 0.72),
                ],
                stops: const [0.0, 0.5, 1.0],
              ),
            ),
          ),
          Align(
            alignment: const Alignment(0, -0.12),
            child: _HomePin(isLight: isLight),
          ),
        ],
      ),
    );
  }
}

/// The same green the live map's pins use, so this reads as a preview of the
/// choice the user is about to make there.
class _HomePin extends StatelessWidget {
  const _HomePin({required this.isLight});

  final bool isLight;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 54,
          height: 54,
          decoration: BoxDecoration(
            color: const Color(0xff34C759),
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 3),
            boxShadow: const [
              BoxShadow(color: Colors.black38, blurRadius: 14, offset: Offset(0, 5)),
            ],
          ),
          child: const Icon(Icons.place_rounded, color: Colors.white, size: 28),
        ),
        const SizedBox(height: 6),
        // The pin's shadow on the "ground", so it reads as planted on the map.
        Container(
          width: 12,
          height: 4,
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: isLight ? 0.22 : 0.45),
            borderRadius: BorderRadius.circular(2),
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// The map — pins over Greece, one tap picks the home city
//
// Restored verbatim from the version this flow shipped with. Nothing is drawn
// over the map except the hint pill it has always had; see the class doc on
// [CitySetupPage] for why that matters.
// ─────────────────────────────────────────────────────────────────────────────

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
                          child: const Icon(Icons.location_on_rounded,
                              color: Color(0xffff4a4a), size: 20),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            AppLocalizations.of(context).cityPickHint,
                            style: const TextStyle(
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

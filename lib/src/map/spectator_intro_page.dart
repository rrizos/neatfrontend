import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../core/onboarding_ui.dart';
import 'city_map_view.dart' show AndroidCityMapHero;
import 'greece_cities.dart';
import 'map_snapshot.dart';

/// Shown once, the first time the user opens the Map tab.
///
/// The sign-up flow told them the city they picked is the only place they can
/// post; this is the other half of that rule — everywhere else is readable but
/// not writable. Naming it ("Spectator Mode", left in English in both locales
/// because that is what the product calls it) gives the restriction a shape
/// the user can hold on to instead of discovering it as a dead comment box.
///
/// The map behind the copy is a still image with the city dots drawn in, not
/// the live map — see [CityMapSnapshot].
class SpectatorIntroPage extends StatefulWidget {
  const SpectatorIntroPage({super.key, required this.themeMode});

  final ThemeMode themeMode;

  @override
  State<SpectatorIntroPage> createState() => _SpectatorIntroPageState();
}

class _SpectatorIntroPageState extends State<SpectatorIntroPage> {
  static const _heroFraction = 0.34;

  Uint8List? _mapImage;
  bool _snapshotRequested = false;
  bool _snapshotSettled = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_snapshotRequested) return;
    _snapshotRequested = true;
    final media = MediaQuery.of(context);
    CityMapSnapshot.load(
      size: Size(media.size.width, media.size.height * _heroFraction),
      devicePixelRatio: media.devicePixelRatio,
      isDark: widget.themeMode != ThemeMode.light,
      // Every city at once: the screen is about the breadth of what you can
      // watch, so the still shows the whole field of dots rather than one pin.
      pins: [
        for (final city in greeceCities)
          (latitude: city.latitude, longitude: city.longitude),
      ],
    ).then((bytes) {
      if (!mounted) return;
      setState(() {
        _mapImage = bytes;
        _snapshotSettled = true;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final isLight = widget.themeMode == ThemeMode.light;
    final background = isLight ? Colors.white : const Color(0xff0a0a0a);

    return Scaffold(
      backgroundColor: background,
      // No top SafeArea: the map runs under the status bar.
      body: Column(
        children: [
          if (_mapImage != null || !_snapshotSettled || AndroidCityMapHero.isSupported)
            _CitiesHero(
              image: _mapImage,
              background: background,
              isLight: isLight,
              height: MediaQuery.sizeOf(context).height * _heroFraction,
            ),
          Expanded(
            child: OnboardingBody(
              children: [
                OnboardingHeadline(
                  title: l10n.spectatorTitle,
                  subtitle: l10n.spectatorSubtitle,
                  isLight: isLight,
                ),
                const SizedBox(height: 32),
                OnboardingPoint(
                  icon: Icons.visibility_outlined,
                  title: l10n.spectatorWatchTitle,
                  body: l10n.spectatorWatchBody,
                  isLight: isLight,
                ),
                const SizedBox(height: 26),
                OnboardingPoint(
                  icon: Icons.do_not_disturb_on_outlined,
                  title: l10n.spectatorNoInteractionTitle,
                  body: l10n.spectatorNoInteractionBody,
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
                  l10n.spectatorMicrocopy,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: onboardingMuted(isLight),
                    fontSize: 12.5,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 14),
                OnboardingButton(
                  label: l10n.spectatorCta,
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Greece with every city dotted on it, fading into the page.
class _CitiesHero extends StatelessWidget {
  const _CitiesHero({
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
          ColoredBox(
            color: isLight ? const Color(0xfff2f3f5) : const Color(0xff141414),
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
          // Melts the bottom edge into the page, stopping short of opaque so
          // MapKit's required "Apple Maps" attribution stays legible.
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
        ],
      ),
    );
  }
}

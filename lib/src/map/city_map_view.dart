import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';

import '../core/media_cache.dart';
import 'greece_cities.dart';

// MapKit JS JWT — origin: netnest.net
const _kMapKitToken =
    'eyJraWQiOiIySDdDRjVUOVRSIiwidHlwIjoiSldUIiwiYWxnIjoiRVMyNTYifQ'
    '.eyJpc3MiOiJSWjM2UE5XUzgyIiwiaWF0IjoxNzUyMDkwNjM2LCJvcmlnaW4iO'
    'iJuZXRuZXN0Lm5ldCJ9.r9qHYkpSBP65h1O9HkVJcxiYN4rHgtwdHgLyhbS0f'
    'FnbZOlvx5LcYZELtt4Q7MBQEGDFICKLp-9nUpsMlA-ZuQ';

const _kMapKitCdnUrl = 'https://cdn.apple-mapkit.com/mk/5.x.x/mapkit.js';

// ─────────────────────────────────────────────────────────────────────────────
// Android: Apple Maps via MapKit JS
//
// Apple doesn't ship native MapKit for Android, so the map is MapKit JS in a
// WebView. The design keeps every stateful decision in exactly one place:
//
//  * Input — while the Flutter city card is open, the card's opaque barrier
//    swallows all touches before they can reach the WebView, so the page
//    holds no lock/unlock state of its own and nothing can ever be left
//    "stuck". A tapped pin is deselected right away; selection is a tap
//    signal, not state.
//  * Bounds — panning and zoom are fenced by the camera itself
//    (cameraBoundary + cameraZoomRange), so gestures stop at a smooth wall
//    instead of triggering corrective snap-back animations.
//  * Bridge — one JSON channel out (ready / pin / error) and one call in
//    (NeatMap.reset()). The widget only attaches the WebView after 'ready',
//    so a half-initialized page is never on screen.
//
// mapkit.js is inlined from the asset bundle so first paint never waits on a
// CDN, and prewarm() builds the whole page off-screen (the native WebView
// exists and runs JS before it is ever attached to the widget tree), so
// opening the map tab shows an already-rendered map.
class _AndroidMap {
  _AndroidMap._();

  final ValueNotifier<bool> ready = ValueNotifier(false);
  late final WebViewController controller;
  void Function(String city)? onPinTap;

  void reset() {
    controller.runJavaScript('NeatMap.reset()').catchError((Object e) {
      debugPrint('[map] reset: $e');
    });
  }

  static String? _mapkitJs;
  static Future<_AndroidMap>? _warmed;
  static String? _warmedKey;

  static String _cacheKey(String homeCity, bool isDark) =>
      '${homeCity.trim().toLowerCase()}|$isDark';

  static Future<void> prewarm({required String homeCity, required bool isDark}) {
    final key = _cacheKey(homeCity, isDark);
    if (_warmed == null || _warmedKey != key) {
      _warmedKey = key;
      _warmed = _build(homeCity: homeCity, isDark: isDark);
    }
    return _warmed!.then((_) {});
  }

  /// Claims the prewarmed instance when it matches, else builds fresh. The
  /// cache slot is cleared either way — a non-matching leftover would just
  /// hold a dead WebView in memory.
  static Future<_AndroidMap> obtain({required String homeCity, required bool isDark}) {
    final warmed = _warmed;
    final matches = warmed != null && _warmedKey == _cacheKey(homeCity, isDark);
    _warmed = null;
    _warmedKey = null;
    if (matches) return warmed;
    return _build(homeCity: homeCity, isDark: isDark);
  }

  static Future<_AndroidMap> _build({required String homeCity, required bool isDark}) async {
    if (_mapkitJs == null) {
      try {
        _mapkitJs = await rootBundle.loadString('assets/mapkit.js');
      } catch (e) {
        debugPrint('[map] mapkit.js asset unavailable, falling back to CDN: $e');
      }
    }
    final map = _AndroidMap._();
    final controller = WebViewController();
    map.controller = controller;
    controller
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(isDark ? const Color(0xff0a0a0a) : const Color(0xfff2f2f7))
      ..setNavigationDelegate(NavigationDelegate(
        onWebResourceError: (e) => debugPrint('[map] resource: ${e.description}'),
      ))
      ..addJavaScriptChannel('NeatBridge', onMessageReceived: map._onBridgeMessage);
    if (kDebugMode) {
      unawaited(controller.setOnConsoleMessage((m) => debugPrint('[map js] ${m.message}')));
    }
    final platform = controller.platform;
    if (platform is AndroidWebViewController) {
      // The page never scrolls (fixed, overflow:hidden canvas) — the native
      // edge-glow would only ever appear by mistake during a fast drag.
      unawaited(platform.setOverScrollMode(WebViewOverScrollMode.never));
    }
    unawaited(controller.loadHtmlString(
      _androidMapPage(homeCity: homeCity, isDark: isDark, inlineMapkitJs: _mapkitJs),
      // Must match the origin the MapKit JWT was issued for.
      baseUrl: 'https://netnest.net',
    ));
    return map;
  }

  void _onBridgeMessage(JavaScriptMessage message) {
    Object? decoded;
    try {
      decoded = jsonDecode(message.message);
    } catch (_) {
      return;
    }
    if (decoded is! Map<String, dynamic>) return;
    switch (decoded['event']) {
      case 'ready':
        ready.value = true;
      case 'pin':
        final city = decoded['city'];
        if (city is String && city.isNotEmpty) onPinTap?.call(city);
      case 'error':
        debugPrint('[map] js: ${decoded['message']}');
    }
  }
}

Future<void> prewarmCityMap({required String homeCity, required bool isDark}) {
  if (kIsWeb || !Platform.isAndroid) return Future.value();
  return _AndroidMap.prewarm(homeCity: homeCity, isDark: isDark);
}

// ─────────────────────────────────────────────────────────────────────────────
// Public widget
// ─────────────────────────────────────────────────────────────────────────────

class CityMapView extends StatefulWidget {
  const CityMapView({
    super.key,
    required this.token,
    required this.homeCity,
    required this.onOpenUserProfile,
    required this.onCitySelected,
    this.isSignUp = false,
  });

  final String token;
  final String homeCity;
  final ValueChanged<String> onOpenUserProfile;
  final ValueChanged<String> onCitySelected;
  final bool isSignUp;

  @override
  State<CityMapView> createState() => _CityMapViewState();
}

class _CityMapViewState extends State<CityMapView> {
  // ── iOS channel ──────────────────────────────────────────────────────────
  static const _iosChannel = MethodChannel('neat/native_city_map_channel');

  _AndroidMap? _androidMap;
  // Guards against an in-flight obtain() from a superseded theme/config
  // finishing late and overwriting the newer map.
  int _mapEpoch = 0;

  // ── UI state ──────────────────────────────────────────────────────────────
  GreeceCity? _activeCity;
  Brightness _brightness = Brightness.dark;
  bool _androidInitDone = false;

  // ─────────────────────────────────────────────────────────────────────────
  // Lifecycle
  // ─────────────────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    _iosChannel.setMethodCallHandler(_onNativeCall);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final newBrightness = Theme.of(context).brightness;
    final changed = newBrightness != _brightness;
    _brightness = newBrightness;
    if (kIsWeb) return;
    if (Platform.isAndroid) {
      // First build, or the theme flipped — either way the page must be
      // (re)built for the right color scheme.
      if (!_androidInitDone || changed) {
        _androidInitDone = true;
        _initAndroid();
      }
    } else if (Platform.isIOS && changed) {
      _iosChannel.invokeMethod('updateColorScheme', _brightness == Brightness.dark);
    }
  }

  @override
  void dispose() {
    _iosChannel.setMethodCallHandler(null);
    _androidMap?.onPinTap = null;
    super.dispose();
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Native → Flutter  (iOS)
  // ─────────────────────────────────────────────────────────────────────────

  Future<void> _onNativeCall(MethodCall call) async {
    if (call.method == 'citySelected') {
      final name = call.arguments?.toString() ?? '';
      if (name.isNotEmpty && mounted) _onCityPinTapped(name);
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Android WebView
  // ─────────────────────────────────────────────────────────────────────────

  Future<void> _initAndroid() async {
    final epoch = ++_mapEpoch;
    final map = await _AndroidMap.obtain(
      homeCity: widget.homeCity,
      isDark: _brightness == Brightness.dark,
    );
    if (!mounted || epoch != _mapEpoch) return;
    map.onPinTap = _onCityPinTapped;
    setState(() => _androidMap = map);
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Shared event handlers
  // ─────────────────────────────────────────────────────────────────────────

  // Shows the card immediately — no awaits on the way. The card's
  // CachedNetworkImage paints a placeholder and loads the real image on its
  // own; while the card is up, its opaque barrier is what blocks map input.
  void _onCityPinTapped(String name) {
    final city = greeceCities.firstWhere(
      (c) => c.name == name,
      orElse: () => greeceCities.first,
    );
    if (_activeCity?.name == city.name) return;
    if (mounted) setState(() => _activeCity = city);
  }

  void _closeCard() {
    if (_activeCity == null) return;
    setState(() => _activeCity = null);
    _resetNativeMap();
  }

  void _joinCity() {
    final city = _activeCity;
    if (city == null) return;
    setState(() => _activeCity = null);
    _resetNativeMap();
    widget.onCitySelected(city.name);
  }

  // Called on every card-close path — dismiss AND join — to zoom the map
  // back out to the overview.
  void _resetNativeMap() {
    if (kIsWeb) return;
    if (Platform.isAndroid) {
      _androidMap?.reset();
    } else if (Platform.isIOS) {
      _iosChannel.invokeMethod('zoomOut');
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Build
  // ─────────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final city = _activeCity;
    return Stack(
      children: [
        Positioned.fill(child: _MapLayer(androidMap: _androidMap, homeCity: widget.homeCity, isDark: _brightness == Brightness.dark)),

        if (city != null)
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _closeCard,
              child: ColoredBox(
                color: Colors.black.withValues(alpha: 0.45),
                child: Center(
                  child: GestureDetector(
                    onTap: () {},
                    child: _CityCard(
                      city: city,
                      imageUrl: city.imageUrl,
                      onClose: _closeCard,
                      onJoin: _joinCity,
                      isSignUp: widget.isSignUp,
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Android map page
//
// A self-contained HTML document. The page exposes exactly one JS object
// (NeatMap) and talks back over exactly one channel (NeatBridge, JSON).
// mapkit.js is inlined from the asset bundle when available so the page
// boots without any network; the CDN is only a fallback.
// ─────────────────────────────────────────────────────────────────────────────

String _androidMapPage({required String homeCity, required bool isDark, String? inlineMapkitJs}) {
  final home = homeCity.trim().toLowerCase();
  final config = jsonEncode({
    'token': _kMapKitToken,
    'dark': isDark,
    'cities': [
      for (final c in greeceCities)
        if (c.name.trim().toLowerCase() != home)
          {'name': c.name, 'lat': c.latitude, 'lng': c.longitude},
    ],
  });
  final bg = isDark ? '#0a0a0a' : '#f2f2f7';

  // StringBuffer so the ~800 KB of minified mapkit.js is appended verbatim,
  // never embedded inside a Dart string literal.
  final page = StringBuffer();

  page.write('''<!DOCTYPE html>
<html>
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width,initial-scale=1.0,maximum-scale=1.0,user-scalable=no">
  <style>
    html, body { margin:0; padding:0; width:100%; height:100%; overflow:hidden; background:$bg; }
    /* touch-action:none hands every pointer straight to MapKit. Without it
       the WebView first arbitrates each drag as a possible page scroll or
       pinch-zoom, and the map only hears about the gesture ~100-300ms in. */
    #map { position:fixed; inset:0; background:$bg; touch-action:none; }
    /* No tap-highlight flashes on pin taps — this page is a map, not a
       document. */
    * { -webkit-tap-highlight-color:transparent; -webkit-user-select:none; user-select:none; }
  </style>
</head>
<body>
  <div id="map"></div>
  <script>
    'use strict';
    var NeatMap = (function () {
      var map = null;
      var userTouched = false;
      var settleTimer = null;

      function post(payload) {
        try { NeatBridge.postMessage(JSON.stringify(payload)); } catch (e) {}
      }

      function overview() {
        return new mapkit.CoordinateRegion(
          new mapkit.Coordinate(39.0, 22.9),
          new mapkit.CoordinateSpan(7.5, 7.5)
        );
      }

      // Same fence as the native iOS map: the camera center may not leave a
      // padded Greece box (center 38,24, span 12x16) and zoom-out is capped
      // at 2,500,000 m. NOTE: in MapKit JS cameraBoundary takes a
      // CoordinateRegion — assigning a BoundingRegion (the obvious guess,
      // and what an earlier version did) is silently rejected, which is why
      // the fence never held.
      function applyHome() {
        try {
          map.cameraBoundary = new mapkit.CoordinateRegion(
            new mapkit.Coordinate(38.0, 24.0),
            new mapkit.CoordinateSpan(12.0, 16.0)
          );
        } catch (e) {}
        try { map.cameraZoomRange = new mapkit.CameraZoomRange(1000, 2500000); } catch (e) {}
        map.region = overview();
      }

      // The page usually boots PREWARMED, in a WebView not yet attached to
      // the widget tree — the viewport is 0x0 or a placeholder size, and it
      // grows to the real screen size in steps. Anything MapKit is told at a
      // wrong size produces a wrong result once the final size arrives (US
      // default view, or Greece framed absurdly far out for a tiny
      // viewport). There is no single reliable "final size is in" moment,
      // so: every resize re-applies the home framing, debounced so only the
      // last size of a layout burst wins — and all of it stops permanently
      // the first time the user actually touches the map, so a late settle
      // can never yank the view away from them.
      function scheduleHome() {
        if (userTouched || !map) return;
        if (settleTimer) clearTimeout(settleTimer);
        settleTimer = setTimeout(function () {
          settleTimer = null;
          if (!userTouched && map) applyHome();
        }, 120);
      }

      document.addEventListener('touchstart', function () {
        userTouched = true;
        if (settleTimer) { clearTimeout(settleTimer); settleTimer = null; }
      }, { capture: true, passive: true, once: true });
      window.addEventListener('resize', scheduleHome);

      function start(config) {
        try {
          mapkit.init({
            authorizationCallback: function (done) { done(config.token); }
          });

          map = new mapkit.Map('map', {
            colorScheme: config.dark ? mapkit.Map.ColorSchemes.Dark
                                     : mapkit.Map.ColorSchemes.Light,
            isRotationEnabled: false,
            showsCompass: mapkit.FeatureVisibility.Hidden,
            showsScale: mapkit.FeatureVisibility.Hidden,
            showsMapTypeControl: false,
            showsZoomControl: false,
            showsUserLocationControl: false
          });
          try { map.isPitchEnabled = false; } catch (e) {}
          try { map.pointOfInterestFilter = mapkit.PointOfInterestFilter.excludingAllCategories; } catch (e) {}

          applyHome();
          // Capped retries cover the cases where attach never changes the
          // viewport size (so no resize fires) or an event is missed; each
          // one is a no-op after the user's first touch.
          [250, 750, 1500, 3000].forEach(function (ms) {
            setTimeout(scheduleHome, ms);
          });

          config.cities.forEach(function (c) {
            var pin = new mapkit.MarkerAnnotation(
              new mapkit.Coordinate(c.lat, c.lng),
              { title: c.name, color: '#34C759', calloutEnabled: false }
            );
            pin.addEventListener('select', function () {
              // Mirror iOS: the pin stays selected (raised) while its card is
              // open; reset() deselects it when the card closes. While the
              // card is up the Flutter overlay swallows all map input, so no
              // lock is needed here.
              map.setRegionAnimated(new mapkit.CoordinateRegion(
                new mapkit.Coordinate(c.lat, c.lng),
                new mapkit.CoordinateSpan(0.63, 0.81)
              ));
              post({ event: 'pin', city: c.name });
            });
            map.addAnnotation(pin);
          });

          post({ event: 'ready' });
        } catch (e) {
          post({ event: 'error', message: String(e) });
        }
      }

      function reset() {
        if (!map) return;
        // Deselect FIRST — this is what visually lowers the pin the moment
        // the card closes (same order as iOS zoomOut()). In MapKit JS the
        // documented way is assigning null to the selectedAnnotation
        // property (deselectAnnotation/selectedAnnotations are iOS-only).
        try { map.selectedAnnotation = null; } catch (e) {}
        try { map.setRegionAnimated(overview()); }
        catch (e) { try { map.region = overview(); } catch (e2) {} }
      }

      return { start: start, reset: reset };
    })();
  </script>
''');

  if (inlineMapkitJs != null) {
    page
      ..write('<script>')
      ..write(inlineMapkitJs)
      ..write('</script>\n<script>NeatMap.start($config);</script>\n');
  } else {
    page.write('''<script>
(function () {
  var s = document.createElement('script');
  s.src = '$_kMapKitCdnUrl';
  s.onload = function () { NeatMap.start($config); };
  s.onerror = function () {
    try { NeatBridge.postMessage(JSON.stringify({ event: 'error', message: 'mapkit cdn unreachable' })); } catch (e) {}
  };
  document.head.appendChild(s);
})();
</script>
''');
  }

  page.write('</body>\n</html>');
  return page.toString();
}

// ─────────────────────────────────────────────────────────────────────────────
// Map layer widget
// ─────────────────────────────────────────────────────────────────────────────

class _MapLayer extends StatelessWidget {
  const _MapLayer({this.androidMap, required this.homeCity, required this.isDark});
  final _AndroidMap? androidMap;
  final String homeCity;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    if (kIsWeb) {
      return const ColoredBox(
        color: Color(0xff050505),
        child: Center(
          child: Text(
            'Map is available on mobile only.',
            style: TextStyle(color: Color(0xffd0d0d0)),
          ),
        ),
      );
    }

    if (Platform.isIOS) {
      final homeCity = this.homeCity.trim().toLowerCase();
      return UiKitView(
        viewType: 'neat/native_city_map',
        creationParams: {
          'cities': greeceCities
              .where((c) => c.name.trim().toLowerCase() != homeCity)
              .map((c) => {
                    'name': c.name,
                    'latitude': c.latitude,
                    'longitude': c.longitude,
                  })
              .toList(),
          'isDark': isDark,
        },
        creationParamsCodec: const StandardMessageCodec(),
      );
    }

    // Android.
    //
    // Uses the default Texture Layer embedding on purpose — full hybrid
    // composition (displayWithHybridComposition) merges Flutter's UI and
    // platform threads and slows the whole app down (flutter#167547).
    //
    // The WebView is only attached once the page reports 'ready', so what
    // slides in is an already-rendered map — never a white page or a
    // half-initialized one. Until then (and while a rebuild for a theme
    // change is in flight) a map-colored surface shows instead.
    final map = androidMap;
    final placeholderColor = isDark ? const Color(0xff0a0a0a) : const Color(0xfff2f2f7);
    if (map == null) return ColoredBox(color: placeholderColor);
    return ValueListenableBuilder<bool>(
      valueListenable: map.ready,
      builder: (context, ready, child) =>
          ready ? child! : ColoredBox(color: placeholderColor),
      child: WebViewWidget(controller: map.controller),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// City card
// ─────────────────────────────────────────────────────────────────────────────

class _CityCard extends StatelessWidget {
  const _CityCard({
    required this.city,
    required this.onClose,
    required this.onJoin,
    this.imageUrl,
    this.isSignUp = false,
  });

  final GreeceCity city;
  final VoidCallback onClose;
  final VoidCallback onJoin;
  final String? imageUrl;
  final bool isSignUp;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 340),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Container(
          decoration: BoxDecoration(
            color: const Color(0xff0d0e12),
            borderRadius: BorderRadius.circular(22),
            boxShadow: const [
              BoxShadow(color: Colors.black54, blurRadius: 32, offset: Offset(0, 16)),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Image with white border frame — X button inside image at top-right
              Padding(
                padding: const EdgeInsets.fromLTRB(22, 22, 22, 0),
                child: Stack(
                  children: [
                    Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: Colors.white, width: 2.5),
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(14),
                        child: SizedBox(
                          height: 190,
                          width: double.infinity,
                          child: imageUrl != null
                              ? CachedNetworkImage(
                                  imageUrl: imageUrl!,
                                  cacheManager: imageCacheManager,
                                  fit: BoxFit.cover,
                                  fadeInDuration: Duration.zero,
                                  placeholder: (ctx, _) => _placeholder(),
                                  errorWidget: (ctx, url, err) {
                                    debugPrint('[CityCard] image failed: $err');
                                    return _placeholder();
                                  },
                                )
                              : _placeholder(),
                        ),
                      ),
                    ),
                    // X inside image, top-right corner
                    Positioned(
                      top: 8,
                      right: 8,
                      child: GestureDetector(
                        onTap: onClose,
                        behavior: HitTestBehavior.opaque,
                        child: const Padding(
                          padding: EdgeInsets.all(4),
                          child: Icon(Icons.close_rounded, color: Colors.white, size: 22),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              // Description text — sign-up only
              if (isSignUp)
                const Padding(
                  padding: EdgeInsets.fromLTRB(22, 18, 22, 0),
                  child: Text(
                    'Επιλέξτε προσεκτικά την πόλη σας! Μπορείτε να αλλάξετε πόλη μετά από 6 μήνες.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      height: 1.5,
                    ),
                  ),
                ),
              // Button
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 18, 16, 20),
                child: SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: onJoin,
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xff2F80ED),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(30),
                      ),
                    ),
                    child: Text(
                      isSignUp ? 'Συνδέσου ${city.name}' : 'Παρακολούθησε ${city.name}',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 15,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _placeholder() {
    return Container(
      color: const Color(0xff1e1f21),
      child: Center(
        child: SizedBox(
          width: 28,
          height: 28,
          child: CircularProgressIndicator(
            strokeWidth: 2.5,
            color: Colors.white.withValues(alpha: 0.35),
          ),
        ),
      ),
    );
  }

}

// Keep this top-level so home_page.dart can still call it if needed.
String cityInitialFor(String value) {
  final t = value.trim();
  return t.isEmpty ? '?' : t[0].toUpperCase();
}

import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';

import '../../l10n/app_localizations.dart';
import '../core/api.dart';
import '../core/media_cache.dart';
import '../core/neat_loader.dart';
import 'city_locator.dart';
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
/// How long focusCity() will wait for the WebView's page to report 'ready'
/// before giving up. Generous: this covers a cold sign-up with no prewarm,
/// where the page is built from scratch on a slow device.
const Duration _kReadyTimeout = Duration(seconds: 12);

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

  /// Waits for the page to come up before flying, and resolves once the
  /// command has actually been issued so the caller can time what follows.
  ///
  /// Unlike iOS — where the native map is live the moment the platform view
  /// exists — this map is a WebView that has to load and run MapKit JS first.
  /// Firing NeatMap.focusCity() into a page that has not reached 'ready' just
  /// throws "NeatMap is not defined" into the catchError below, which is
  /// precisely how the sign-up fly-to went missing on Android.
  Future<void> focusCity(String name) async {
    if (!ready.value) {
      final loaded = Completer<void>();
      void onReady() {
        if (ready.value && !loaded.isCompleted) loaded.complete();
      }

      ready.addListener(onReady);
      try {
        await loaded.future.timeout(_kReadyTimeout);
      } catch (_) {
        debugPrint('[map] focusCity: page never became ready');
        return;
      } finally {
        ready.removeListener(onReady);
      }
    }
    final encoded = jsonEncode(name);
    await controller.runJavaScript('NeatMap.focusCity($encoded)').catchError((Object e) {
      debugPrint('[map] focusCity: $e');
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

  // The channel is one shared name, so only one handler can be installed at a
  // time. Two maps can exist at once (sign-up, and the home tab's), and the
  // second one to be torn down used to clear the handler out from under the
  // first — after which every 'citySelected' from the live map went nowhere:
  // no card, and so nothing left to call zoomOut. Tracking the owner means
  // only the instance that installed the handler can remove it.
  static Object? _iosHandlerOwner;

  _AndroidMap? _androidMap;
  // The same map as _androidMap, but available from the moment it is asked
  // for rather than only once it has been built. Sign-up's auto-focus resolves
  // the device's city on its own schedule and regularly wins that race, and
  // firing at a null _androidMap simply did nothing — which is why Android
  // never travelled to the detected city while iOS, whose native map exists
  // with the platform view, always did.
  Future<_AndroidMap>? _androidMapPending;
  // Guards against an in-flight obtain() from a superseded theme/config
  // finishing late and overwriting the newer map.
  int _mapEpoch = 0;

  // ── UI state ──────────────────────────────────────────────────────────────
  GreeceCity? _activeCity;
  String? _joiningCityName;
  Map<String, double> _cityHeat = {};

  // Bumped whenever the card is dismissed, to build a fresh platform view.
  //
  // On iOS a live map that has had a full-screen Flutter layer over it does
  // not reliably get its gestures back once that layer goes away — the map
  // still draws, but no longer pans, which is the "it became a photo" people
  // hit after opening a city and closing it again. This codebase has met the
  // same limitation before and worked around it by not putting the live map
  // under Flutter layers at all (see CitySetupPage's doc comment); here the
  // card has to sit over the map, so the map is rebuilt instead.
  //
  // The cost is a tile reload, and nothing else: the card only ever closes
  // back to the country-wide view, which is exactly where a new map starts,
  // so there is no camera state worth preserving across the swap.
  int _mapGeneration = 0;
  Timer? _mapRebuild;
  Brightness _brightness = Brightness.dark;
  bool _androidInitDone = false;

  // ─────────────────────────────────────────────────────────────────────────
  // Lifecycle
  // ─────────────────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    _iosHandlerOwner = this;
    _iosChannel.setMethodCallHandler(_onNativeCall);
    if (widget.isSignUp) unawaited(_preselectCurrentCity());
    if (!widget.isSignUp) unawaited(_fetchCityHeat());
  }

  /// How long the map is given to reach the detected city before the card
  /// covers it: settling at the country view (350ms), the glide across to the
  /// city (750ms), and the descent onto it — all set on both native sides.
  /// Land the card any earlier and it hides the movement that is the whole
  /// point of showing someone where their city is.
  static const _kFocusTravel = Duration(milliseconds: 2000);

  /// Asks for location permission and, if it is granted, opens the card for
  /// the city the device is in so the user only has to press connect.
  ///
  /// The map travels there first. Dropping the card straight onto a map still
  /// showing the whole country gave no sense of where "your city" is; flying
  /// to it and then presenting the card reads as one movement.
  Future<void> _preselectCurrentCity() async {
    final name = await CityLocator.detectCity();
    // The prompt is modal and the fix can take seconds — by now the user may
    // have left, or already picked a city by hand. Never override either.
    if (!mounted || name == null || _activeCity != null) return;

    // Awaited, so _kFocusTravel is measured from when the map actually starts
    // moving. On Android that can be a second or two after detection resolves
    // (the WebView still has to load), and timing the card from detection
    // instead used to drop it over a map that had not gone anywhere.
    await _focusNativeCity(name);
    if (!mounted || _activeCity != null) return;

    await Future<void>.delayed(_kFocusTravel);
    // Re-check: the wait is long enough for the user to have tapped a pin of
    // their own, and their choice wins over the one we guessed.
    if (!mounted || _activeCity != null) return;
    _onCityPinTapped(name);
  }

  /// Zooms the map to [name] without a tap, on whichever map is in play.
  /// Completes once the map has been told to travel, not when it arrives.
  Future<void> _focusNativeCity(String name) async {
    if (kIsWeb) return;
    // Never lets a failure to travel stop the card from opening — a map that
    // stayed put is the old behaviour, a sign-up stuck with no card is not.
    // iOS installs the channel handler with the platform view, so an early
    // detection can still find nothing listening there.
    try {
      if (Platform.isAndroid) {
        // Not `_androidMap?.` — that field is only set once the map is built,
        // and this runs on location's schedule, which is often sooner.
        final pending = _androidMapPending;
        if (pending == null) return;
        final map = await pending;
        if (!mounted) return;
        await map.focusCity(name);
      } else if (Platform.isIOS) {
        await _iosChannel.invokeMethod('focusCity', name);
      }
    } catch (e) {
      debugPrint('[map] focusNativeCity: $e');
    }
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
    _mapRebuild?.cancel();
    if (identical(_iosHandlerOwner, this)) {
      _iosChannel.setMethodCallHandler(null);
      _iosHandlerOwner = null;
    }
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
    // Published before the first await so a waiter that arrives during the
    // build gets this map rather than nothing.
    final pending = _AndroidMap.obtain(
      homeCity: widget.homeCity,
      isDark: _brightness == Brightness.dark,
    );
    _androidMapPending = pending;
    final map = await pending;
    if (!mounted || epoch != _mapEpoch) return;
    map.onPinTap = _onCityPinTapped;
    setState(() => _androidMap = map);
    _pushHeatToAndroid();
  }

  // ─────────────────────────────────────────────────────────────────────────
  // City heat
  // ─────────────────────────────────────────────────────────────────────────

  Future<void> _fetchCityHeat() async {
    try {
      final res = await http.get(cityHeatEndpoint, headers: authGetHeaders(widget.token));
      if (!mounted || res.statusCode != 200) return;
      final raw = jsonDecode(res.body) as Map<String, dynamic>;
      _cityHeat = raw.map((k, v) => MapEntry(k, (v as num).toDouble()));
      _pushHeatToAndroid();
      _pushHeatToIos();
    } catch (_) {}
  }

  void _pushHeatToAndroid() {
    final map = _androidMap;
    if (map == null || !map.ready.value) return;
    map.controller
        .runJavaScript('NeatMap.updateHeat(${jsonEncode(_cityHeat)})')
        .catchError((_) {});
  }

  void _pushHeatToIos() {
    if (kIsWeb || !Platform.isIOS) return;
    _iosChannel.invokeMethod<void>('updateHeat', _cityHeat).catchError((_) {});
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
    // Always animate out first. The rebuild that follows on iOS is only there
    // to restore gestures; letting it replace the animation would drop the
    // user at the country view with no sense of having travelled back.
    _resetNativeMap();
    if (_needsFreshMapAfterOverlay) _scheduleMapRebuild();
  }

  /// iOS only: see [_mapGeneration]. Elsewhere the map survives having Flutter
  /// drawn over it, so it is reset in place rather than rebuilt.
  bool get _needsFreshMapAfterOverlay => !kIsWeb && Platform.isIOS;

  /// Long enough for the zoom-out to finish before the map is swapped, so the
  /// new one is built at the camera the old one just animated to and the
  /// exchange is invisible.
  static const _kZoomOutSettle = Duration(milliseconds: 900);

  void _scheduleMapRebuild() {
    _mapRebuild?.cancel();
    _mapRebuild = Timer(_kZoomOutSettle, () {
      // A card opened again during the wait means the map is under an overlay
      // once more; rebuilding now would swap it out from under the card, and
      // the next close will schedule this again anyway.
      if (!mounted || _activeCity != null) return;
      setState(() => _mapGeneration++);
    });
  }

  void _joinCity() {
    final city = _activeCity;
    if (city == null) return;
    setState(() {
      _activeCity = null;
      _joiningCityName = city.name;
    });
    _resetNativeMap();
    Future<void>.delayed(const Duration(milliseconds: 1500), () {
      if (!mounted) return;
      widget.onCitySelected(city.name);
    });
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
        Positioned.fill(
          child: _MapLayer(
            // Changing key = new platform view; see [_mapGeneration].
            key: ValueKey(_mapGeneration),
            androidMap: _androidMap,
            homeCity: widget.homeCity,
            isDark: _brightness == Brightness.dark,
          ),
        ),

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

        if (_joiningCityName != null)
          Positioned.fill(
            child: ColoredBox(
              color: Colors.black,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  NeatLoader(size: 72, color: Colors.white),
                  const SizedBox(height: 24),
                  Text(
                    AppLocalizations.of(context).joiningCity(_joiningCityName!),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
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
          {'name': c.name, 'lat': c.latitude, 'lng': c.longitude, 'tier': c.tier},
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
      var allPinsRef = [];
      var userTouched = false;
      var settleTimer = null;

      function heatToColor(h) {
        if (!h || h < 0.25) return '#34C759';
        if (h < 0.5)  return '#FFCC00';
        if (h < 0.75) return '#FF9500';
        return '#FF3B30';
      }

      /* Set once focusCity() has aimed the camera somewhere deliberate. From
         then on the home-framing retries below must only re-apply the fence,
         never the country-wide region: their whole job is to correct a camera
         that nothing has claimed yet, and left unguarded they land squarely on
         top of the sign-up fly-to and snap it back to the whole of Greece. */
      var cameraClaimed = false;
      var focusAttempts = 0;

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
      function applyFence() {
        try {
          map.cameraBoundary = new mapkit.CoordinateRegion(
            new mapkit.Coordinate(38.0, 24.0),
            new mapkit.CoordinateSpan(12.0, 16.0)
          );
        } catch (e) {}
        try { map.cameraZoomRange = new mapkit.CameraZoomRange(1000, 2500000); } catch (e) {}
      }

      /* The fence is re-applied on every pass — it is cheap and the comment
         above explains why it needs the repetition — but the framing is not,
         once someone has claimed the camera. */
      function applyHome() {
        applyFence();
        if (userTouched || cameraClaimed) return;
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
              { title: c.name, color: heatToColor(c.heat), calloutEnabled: false }
            );
            pin._neatTier = c.tier || 3;
            pin._neatName = c.name;
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
            allPinsRef.push(pin);
            map.addAnnotation(pin);
          });

          function updatePinVisibility() {
            try {
              var span = map.region.span.latitudeDelta;
              if (!span || isNaN(span) || span <= 0) return;
              // tier 1 always visible; tier 2 at delta < 5; tier 3 at delta < 2.5
              var maxTier = span < 2.5 ? 3 : (span < 5 ? 2 : 1);
              allPinsRef.forEach(function (p) {
                p.visible = p._neatTier <= maxTier;
              });
            } catch (e) {}
          }
          map.addEventListener('region-change-end', updatePinVisibility);
          // region-change-end only fires for animated region changes, not instant
          // map.region = ... assignments. Call directly after the map settles so
          // the initial overview (latitudeDelta 7.5 → maxTier 1) hides tier 2/3.
          [300, 800, 2000].forEach(function (ms) { setTimeout(updatePinVisibility, ms); });

          post({ event: 'ready' });
        } catch (e) {
          post({ event: 'error', message: String(e) });
        }
      }

      /* Zooms to a city by name without waiting for a tap, so sign-up can
         travel to the city it detected rather than dropping the card over an
         untouched map of the whole country. */
      function focusCity(name) {
        if (!map) return;
        /* The WebView reaches 'ready' while it is still off the widget tree,
           so the element can be 0x0 here. Every region below would then be
           computed against a viewport with no size and land nowhere — and
           because focusing claims the camera, nothing would come along to
           correct it. Wait for a real layout instead. */
        var el = document.getElementById('map');
        if (el && (el.clientWidth === 0 || el.clientHeight === 0)) {
          if (focusAttempts++ < 40) setTimeout(function () { focusCity(name); }, 100);
          return;
        }
        var target = null;
        map.annotations.forEach(function (a) {
          if (a.title === name) target = a;
        });
        if (!target) return;

        cameraClaimed = true;
        if (settleTimer) { clearTimeout(settleTimer); settleTimer = null; }
        /* Two stages so it reads as travel rather than a cut: glide across
           the country at the height you were already at, then descend once
           the city is under you.

           Camera only. Assigning selectedAnnotation fires the pin's own
           'select' listener, which posts back as a tap and opens the card
           instantly — over the animation this exists to let people watch. */
        try {
          /* 1. back to the country view, so every trip starts alike */
          map.setRegionAnimated(overview());
          setTimeout(function () {
            try {
              /* 2. glide to the city at that height */
              map.setRegionAnimated(new mapkit.CoordinateRegion(
                target.coordinate, overview().span));
            } catch (e) {}
            setTimeout(function () {
              try {
                /* 3. descend onto it */
                map.setRegionAnimated(new mapkit.CoordinateRegion(
                  target.coordinate,
                  new mapkit.CoordinateSpan(0.63, 0.81)
                ));
              } catch (e) {}
            }, 750);
          }, 350);
        } catch (e) {}
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

      function updateHeat(heatMap) {
        allPinsRef.forEach(function (p) {
          var h = heatMap[p._neatName];
          if (h !== undefined) {
            try { p.color = heatToColor(h); } catch (e) {}
          }
        });
      }

      return { start: start, reset: reset, focusCity: focusCity, updateHeat: updateHeat };
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
  const _MapLayer({
    super.key,
    this.androidMap,
    required this.homeCity,
    required this.isDark,
  });
  final _AndroidMap? androidMap;
  final String homeCity;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    if (kIsWeb) {
      return ColoredBox(
        color: const Color(0xff050505),
        child: Center(
          child: Text(
            AppLocalizations.of(context).mapMobileOnly,
            style: const TextStyle(color: Color(0xffd0d0d0)),
          ),
        ),
      );
    }

    if (Platform.isIOS) {
      final homeCity = this.homeCity.trim().toLowerCase();
      return UiKitView(
        viewType: 'neat/native_city_map',
        // Without this the map dies mid-pan and stays dead.
        //
        // A UiKitView with no recognizers of its own only *borrows* touches:
        // Flutter withholds them pending the gesture arena, and hands them to
        // the platform view only while nothing in Flutter has claimed them.
        // The moment an ancestor recognizer wins — the route's own
        // back-swipe, a parent page view — the native map is sent
        // touchesCancelled and the pan stops dead, which is why it froze a
        // second or two in rather than immediately. Claiming eagerly means the
        // map owns the gesture from touch-down and cannot have it taken away.
        gestureRecognizers: <Factory<OneSequenceGestureRecognizer>>{
          Factory<OneSequenceGestureRecognizer>(EagerGestureRecognizer.new),
        },
        creationParams: {
          'cities': greeceCities
              .where((c) => c.name.trim().toLowerCase() != homeCity)
              .map((c) => {
                    'name': c.name,
                    'latitude': c.latitude,
                    'longitude': c.longitude,
                    'tier': c.tier,
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
      // Claims touches eagerly for the same reason as the iOS map above: an
      // ancestor winning the arena mid-pan would cancel the WebView's gesture
      // and leave the map unresponsive.
      child: WebViewWidget(
        controller: map.controller,
        gestureRecognizers: <Factory<OneSequenceGestureRecognizer>>{
          Factory<OneSequenceGestureRecognizer>(EagerGestureRecognizer.new),
        },
      ),
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
                                  memCacheWidth: (MediaQuery.sizeOf(context).width *
                                          MediaQuery.devicePixelRatioOf(context))
                                      .round(),
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
    return const ColoredBox(
      color: Color(0xff1e1f21),
      child: NeatLoader(size: 52, color: Colors.white),
    );
  }

}

// Keep this top-level so home_page.dart can still call it if needed.
String cityInitialFor(String value) {
  final t = value.trim();
  return t.isEmpty ? '?' : t[0].toUpperCase();
}

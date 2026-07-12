import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:webview_flutter/webview_flutter.dart';

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
// Android: prewarm the map WebView ahead of time
//
// The ~807 KB mapkit.js inline parse is a real, visible stall the first time
// a WebViewController evaluates it. The home map tab is already kept alive
// once visited (IndexedStack), so that stall only happens once — but it used
// to happen exactly when the user tapped the Map tab. The signup city-picker
// is a brand-new screen/route every time, so it always pays the cost fresh.
// `prewarmCityMap` lets callers (home_page.dart, auth_screen.dart) kick off
// the WebView creation + JS parse in the background, before the map is
// actually shown, so the cost lands on idle time instead of a tap or a
// network round-trip that's already in flight.
String? _cachedMapkitJs;
WebViewController? _prewarmedCityMapCtrl;
String? _prewarmedCityMapKey;
Future<void>? _prewarmingCityMap;
String? _prewarmingCityMapKey;
ValueChanged<String>? _cityMapPinHandler;

String _cityMapCacheKey(String homeCity, bool isDark) => '${homeCity.trim().toLowerCase()}|$isDark';

Future<void> prewarmCityMap({required String homeCity, required bool isDark}) {
  if (kIsWeb || !Platform.isAndroid) return Future.value();
  final key = _cityMapCacheKey(homeCity, isDark);
  if (_prewarmedCityMapKey == key && _prewarmedCityMapCtrl != null) return Future.value();
  if (_prewarmingCityMap != null && _prewarmingCityMapKey == key) return _prewarmingCityMap!;
  final done = Completer<void>();
  _prewarmingCityMap = done.future;
  _prewarmingCityMapKey = key;
  () async {
    if (_cachedMapkitJs == null) {
      try {
        _cachedMapkitJs = await rootBundle.loadString('assets/mapkit.js');
      } catch (e) {
        debugPrint('[map] MapKit JS asset load: $e');
      }
    }
    _prewarmedCityMapCtrl = _buildCityMapController(homeCity: homeCity, isDark: isDark);
    _prewarmedCityMapKey = key;
    _prewarmingCityMap = null;
    _prewarmingCityMapKey = null;
    done.complete();
  }();
  return done.future;
}

WebViewController _buildCityMapController({required String homeCity, required bool isDark}) {
  final home = homeCity.trim().toLowerCase();
  final citiesJson = jsonEncode(
    greeceCities
        .where((c) => c.name.trim().toLowerCase() != home)
        .map((c) => {'name': c.name, 'lat': c.latitude, 'lng': c.longitude})
        .toList(),
  );
  return WebViewController()
    ..setJavaScriptMode(JavaScriptMode.unrestricted)
    ..setBackgroundColor(isDark ? const Color(0xff0a0a0a) : const Color(0xfff2f2f7))
    ..setNavigationDelegate(NavigationDelegate(
      onWebResourceError: (e) => debugPrint('[map] ${e.description}'),
    ))
    ..addJavaScriptChannel('FlutterBridge', onMessageReceived: (msg) {
      _cityMapPinHandler?.call(msg.message);
    })
    ..loadHtmlString(
      _mapHtml(citiesJson, inlineJs: _cachedMapkitJs, isDark: isDark),
      baseUrl: 'https://netnest.net',
    );
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

  WebViewController? _webCtrl;

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
      if (!_androidInitDone) {
        _androidInitDone = true;
        _initAndroid();
      } else if (changed && _webCtrl != null) {
        _buildWebView();
        setState(() {});
      }
    } else if (Platform.isIOS && changed) {
      _iosChannel.invokeMethod('updateColorScheme', _brightness == Brightness.dark);
    }
  }

  @override
  void dispose() {
    _iosChannel.setMethodCallHandler(null);
    if (identical(_cityMapPinHandler, _onCityPinTapped)) _cityMapPinHandler = null;
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
    final isDark = _brightness == Brightness.dark;
    final key = _cityMapCacheKey(widget.homeCity, isDark);
    // A matching prewarm may still be running (e.g. kicked off alongside the
    // signup network call) — wait for it rather than starting a redundant
    // second WebView build.
    if (_prewarmingCityMapKey == key && _prewarmingCityMap != null) {
      await _prewarmingCityMap;
      if (!mounted) return;
    }
    // Reuse a controller warmed ahead of time (see prewarmCityMap) instead of
    // paying the mapkit.js parse cost right when the map becomes visible.
    if (_prewarmedCityMapKey == key && _prewarmedCityMapCtrl != null) {
      _webCtrl = _prewarmedCityMapCtrl;
      _prewarmedCityMapCtrl = null;
      _prewarmedCityMapKey = null;
    } else {
      if (_cachedMapkitJs == null) {
        try {
          _cachedMapkitJs = await rootBundle.loadString('assets/mapkit.js');
        } catch (e) {
          debugPrint('[map] MapKit JS asset load: $e');
        }
      }
      if (!mounted) return;
      _buildWebView();
    }
    _cityMapPinHandler = _onCityPinTapped;
    if (mounted) setState(() {});
  }

  void _buildWebView() {
    _webCtrl = _buildCityMapController(homeCity: widget.homeCity, isDark: _brightness == Brightness.dark);
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Shared event handlers
  // ─────────────────────────────────────────────────────────────────────────

  Future<void> _onCityPinTapped(String name) async {
    final city = greeceCities.firstWhere(
      (c) => c.name == name,
      orElse: () => greeceCities.first,
    );
    if (_activeCity?.name == city.name) return;
    final imageUrl = city.imageUrl;
    if (imageUrl != null && imageUrl.isNotEmpty) {
      try {
        await precacheImage(
          CachedNetworkImageProvider(imageUrl, cacheManager: imageCacheManager),
          context,
        );
      } catch (_) {}
    }
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

  // Must be called on every card-close path — dismiss AND join — so native
  // map interaction is never permanently locked.
  void _resetNativeMap() {
    if (kIsWeb) return;
    if (Platform.isAndroid) {
      _webCtrl?.runJavaScript('resetMap()').catchError(
        (e) => debugPrint('[map] resetMap: $e'),
      );
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
        Positioned.fill(child: _MapLayer(webCtrl: _webCtrl, homeCity: widget.homeCity, isDark: _brightness == Brightness.dark)),

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
// Android: Apple MapKit JS
//
// mapkit.js is loaded from the Flutter asset bundle (assets/mapkit.js) and
// injected inline so the WebView never makes a network request for the library.
// This works on all devices including emulators where DNS may be unreliable.
// The CDN URL (cdn.apple-mapkit.com) is only hit if the asset load fails.
// ─────────────────────────────────────────────────────────────────────────────

String _mapHtml(String citiesJson, {String? inlineJs, required bool isDark}) {
  // Use StringBuffer so the (potentially large) mapkit.js content is appended
  // without being inside a Dart string literal — avoids any ''' termination
  // risk in minified JS and keeps the Dart source clean.
  final buf = StringBuffer();

  buf.write('''<!DOCTYPE html>
<html>
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="initial-scale=1.0,width=device-width">
  <style>
    html, body, #map { margin:0; padding:0; width:100%; height:100%; background:${isDark ? '#0a0a0a' : '#f2f2f7'}; overflow:hidden; }
  </style>
</head>
<body>
  <div id="map"></div>
  <script>
    var busy = false;
    var map, home, homeSpan, activePin = null;

    function initMap() {
      mapkit.init({
        authorizationCallback: function(done) { done('$_kMapKitToken'); }
      });

      home     = new mapkit.Coordinate(39.0, 22.9);
      homeSpan = new mapkit.CoordinateSpan(7.5, 7.5);

      map = new mapkit.Map('map', {
        colorScheme:              mapkit.Map.ColorSchemes.${isDark ? 'Dark' : 'Light'},
        showsCompass:             mapkit.FeatureVisibility.Hidden,
        showsScale:               mapkit.FeatureVisibility.Hidden,
        showsMapTypeControl:      false,
        showsZoomControl:         false,
        showsUserLocationControl: false,
      });

      map.isRotationEnabled = false;
      map.isPitchEnabled    = false;

      // Mirror iOS: map.pointOfInterestFilter = .excludingAll
      try { map.pointOfInterestFilter = mapkit.PointOfInterestFilter.excludingAllCategories; } catch(_) {}

      map.region = new mapkit.CoordinateRegion(home, homeSpan);

      // Constrain centre to a padded Greece bounding box (N, E, S, W).
      try { map.cameraBoundary = new mapkit.BoundingRegion(44, 32, 32, 16); } catch(_) {}

      // Cap zoom-out: refuse spans wider than ~12° lat (≈ 2× Greece height).
      map.addEventListener('region-change-end', function() {
        if (busy) return;
        var r = map.region;
        if (r.span.latitudeDelta > 13) {
          map.region = new mapkit.CoordinateRegion(
            r.center, new mapkit.CoordinateSpan(13, 13)
          );
        }
      });

      var cities = $citiesJson;
      cities.forEach(function(c) {
        var coord = new mapkit.Coordinate(c.lat, c.lng);
        var pin   = new mapkit.MarkerAnnotation(coord, {
          title:          c.name,
          color:          '#34C759',   // iOS systemGreen exact hex
          calloutEnabled: false,
        });
        pin.addEventListener('select', function() {
          // Mirror iOS didSelect: lock immediately, zoom in, notify Flutter
          if (busy) { map.deselectAnnotation(pin); return; }
          busy      = true;
          activePin = pin;
          document.getElementById('map').style.pointerEvents = 'none';
          // 70 000 m radius ≈ 0.63° lat × 0.81° lng at 39°N — matches iOS
          map.setRegionAnimated(
            new mapkit.CoordinateRegion(coord, new mapkit.CoordinateSpan(0.63, 0.81))
          );
          FlutterBridge.postMessage(c.name);
        });
        map.addAnnotation(pin);
      });
    }

    // Mirror iOS zoomOut(): unlock FIRST (unconditional), deselect, then zoom out.
    function resetMap() {
      busy = false;
      document.getElementById('map').style.pointerEvents = '';
      if (!map) return;
      if (activePin) {
        try { map.deselectAnnotation(activePin); } catch(_) {}
        activePin = null;
      }
      var overview = new mapkit.CoordinateRegion(
        new mapkit.Coordinate(39.0, 22.9),
        new mapkit.CoordinateSpan(7.5, 7.5)
      );
      try {
        map.setRegionAnimated(overview);
      } catch(e) {
        console.error('[map] setRegionAnimated: ' + e);
        try { map.region = overview; } catch(_) {}
      }
    }
  </script>
''');

  if (inlineJs != null) {
    // Injected inline — no CDN request needed inside the WebView.
    buf.write('<script>');
    buf.write(inlineJs);
    buf.write('</script>\n<script>initMap();</script>\n');
  } else {
    // Dart pre-fetch failed; let the WebView try the CDN directly.
    // Works on real devices; may fail on emulators with broken DNS.
    buf.write('''  <script>
(function() {
  var s    = document.createElement('script');
  s.src    = '$_kMapKitCdnUrl';
  s.onload = initMap;
  s.onerror = function() { console.error('[map] MapKit JS CDN unavailable'); };
  document.head.appendChild(s);
})();
  </script>
''');
  }

  buf.write('</body>\n</html>');
  return buf.toString();
}

// ─────────────────────────────────────────────────────────────────────────────
// Map layer widget
// ─────────────────────────────────────────────────────────────────────────────

class _MapLayer extends StatelessWidget {
  const _MapLayer({this.webCtrl, required this.homeCity, required this.isDark});
  final WebViewController? webCtrl;
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

    // Android — null while mapkit.js is being pre-fetched
    final ctrl = webCtrl;
    if (ctrl == null) return ColoredBox(color: isDark ? const Color(0xff0a0a0a) : const Color(0xfff2f2f7));
    return WebViewWidget(controller: ctrl);
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
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.add_photo_alternate_outlined,
              size: 40, color: Colors.white.withValues(alpha: 0.25)),
          const SizedBox(height: 10),
          Text(
            city.name,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.35),
              fontSize: 15,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '// TODO: add imageUrl in greece_cities.dart',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.18),
              fontSize: 10,
              fontFamily: 'monospace',
            ),
          ),
        ],
      ),
    );
  }
}

// Keep this top-level so home_page.dart can still call it if needed.
String cityInitialFor(String value) {
  final t = value.trim();
  return t.isEmpty ? '?' : t[0].toUpperCase();
}

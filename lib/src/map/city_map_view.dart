import 'dart:convert';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:webview_flutter/webview_flutter.dart';

import 'greece_cities.dart';

// MapKit JS JWT — origin: netnest.net
const _kMapKitToken =
    'eyJraWQiOiIySDdDRjVUOVRSIiwidHlwIjoiSldUIiwiYWxnIjoiRVMyNTYifQ'
    '.eyJpc3MiOiJSWjM2UE5XUzgyIiwiaWF0IjoxNzUyMDkwNjM2LCJvcmlnaW4iO'
    'iJuZXRuZXN0Lm5ldCJ9.r9qHYkpSBP65h1O9HkVJcxiYN4rHgtwdHgLyhbS0f'
    'FnbZOlvx5LcYZELtt4Q7MBQEGDFICKLp-9nUpsMlA-ZuQ';

const _kMapKitCdnUrl = 'https://cdn.apple-mapkit.com/mk/5.x.x/mapkit.js';

// ─────────────────────────────────────────────────────────────────────────────
// Public widget
// ─────────────────────────────────────────────────────────────────────────────

class CityMapView extends StatefulWidget {
  const CityMapView({
    super.key,
    required this.token,
    required this.onOpenUserProfile,
    required this.onCitySelected,
  });

  final String token;
  final ValueChanged<String> onOpenUserProfile;
  final ValueChanged<String> onCitySelected;

  @override
  State<CityMapView> createState() => _CityMapViewState();
}

class _CityMapViewState extends State<CityMapView> {
  // ── iOS channel ──────────────────────────────────────────────────────────
  static const _iosChannel = MethodChannel('neat/native_city_map_channel');

  // ── Android WebView ───────────────────────────────────────────────────────
  // mapkit.js content cached for the lifetime of the app process so subsequent
  // map opens are instant and only the first ever visit pays the fetch cost.
  static String? _cachedMapkitJs;

  WebViewController? _webCtrl;

  // ── UI state ──────────────────────────────────────────────────────────────
  GreeceCity? _activeCity;

  // ─────────────────────────────────────────────────────────────────────────
  // Lifecycle
  // ─────────────────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    _iosChannel.setMethodCallHandler(_onNativeCall);
    if (!kIsWeb && Platform.isAndroid) _initAndroid();
  }

  @override
  void dispose() {
    _iosChannel.setMethodCallHandler(null);
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

  // Load mapkit.js from the bundled Flutter asset (assets/mapkit.js).
  // This is instant (reads from the app bundle, no network) and works on every
  // device including emulators where CDN DNS may fail.  The CDN URL in the
  // HTML is only ever used as a last-resort fallback if the asset load fails.
  Future<void> _initAndroid() async {
    if (_cachedMapkitJs == null) {
      try {
        _cachedMapkitJs = await rootBundle.loadString('assets/mapkit.js');
      } catch (e) {
        debugPrint('[map] MapKit JS asset load: $e');
      }
    }
    if (!mounted) return;
    _buildWebView();
    setState(() {});
  }

  void _buildWebView() {
    final citiesJson = jsonEncode(
      greeceCities
          .map((c) => {'name': c.name, 'lat': c.latitude, 'lng': c.longitude})
          .toList(),
    );

    _webCtrl = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(const Color(0xff0a0a0a))
      ..setNavigationDelegate(NavigationDelegate(
        onWebResourceError: (e) => debugPrint('[map] ${e.description}'),
      ))
      ..addJavaScriptChannel('FlutterBridge', onMessageReceived: (msg) {
        if (mounted) _onCityPinTapped(msg.message);
      })
      ..loadHtmlString(
        _mapHtml(citiesJson, inlineJs: _cachedMapkitJs),
        baseUrl: 'https://netnest.net',
      );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Shared event handlers
  // ─────────────────────────────────────────────────────────────────────────

  void _onCityPinTapped(String name) {
    final city = greeceCities.firstWhere(
      (c) => c.name == name,
      orElse: () => greeceCities.first,
    );
    if (_activeCity?.name == city.name) return;
    setState(() => _activeCity = city);
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
        Positioned.fill(child: _MapLayer(webCtrl: _webCtrl)),

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
                      onClose: _closeCard,
                      onJoin: _joinCity,
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

String _mapHtml(String citiesJson, {String? inlineJs}) {
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
    html, body, #map { margin:0; padding:0; width:100%; height:100%; background:#0a0a0a; overflow:hidden; }
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
        colorScheme:              mapkit.Map.ColorSchemes.Dark,
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
  const _MapLayer({this.webCtrl});
  final WebViewController? webCtrl;

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
      return UiKitView(
        viewType: 'neat/native_city_map',
        creationParams: {
          'cities': greeceCities
              .map((c) => {
                    'name': c.name,
                    'latitude': c.latitude,
                    'longitude': c.longitude,
                  })
              .toList(),
        },
        creationParamsCodec: const StandardMessageCodec(),
      );
    }

    // Android — null while mapkit.js is being pre-fetched
    final ctrl = webCtrl;
    if (ctrl == null) return const ColoredBox(color: Color(0xff0a0a0a));
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
  });

  final GreeceCity city;
  final VoidCallback onClose;
  final VoidCallback onJoin;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 320),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: const Color(0xff101010),
            borderRadius: BorderRadius.circular(28),
            border: Border.all(color: const Color(0xff2a2a2a)),
            boxShadow: const [
              BoxShadow(
                  color: Colors.black54, blurRadius: 24, offset: Offset(0, 14)),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Stack(
                  children: [
                    Container(
                      height: 132,
                      width: double.infinity,
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [Color(0xff1c1c1c), Color(0xff090909)],
                        ),
                      ),
                      alignment: Alignment.center,
                      child: CircleAvatar(
                        radius: 38,
                        backgroundColor: const Color(0xff171717),
                        child: Text(
                          _initial(city.name),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 28,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      top: 8,
                      right: 8,
                      child: IconButton(
                        icon: const Icon(Icons.close, color: Colors.white),
                        onPressed: onClose,
                      ),
                    ),
                  ],
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(18, 18, 18, 22),
                  child: Column(
                    children: [
                      Text(
                        city.name,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'View this city\'s feed and join the local network.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Color(0xffababab),
                          fontSize: 13,
                          height: 1.4,
                        ),
                      ),
                      const SizedBox(height: 20),
                      SizedBox(
                        width: double.infinity,
                        height: 48,
                        child: FilledButton(
                          onPressed: onJoin,
                          style: FilledButton.styleFrom(
                            backgroundColor: Colors.white,
                            foregroundColor: Colors.black,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                          child: const Text(
                            'Join city',
                            style: TextStyle(fontWeight: FontWeight.w700),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _initial(String s) {
    final t = s.trim();
    return t.isEmpty ? '?' : t[0].toUpperCase();
  }
}

// Keep this top-level so home_page.dart can still call it if needed.
String cityInitialFor(String value) {
  final t = value.trim();
  return t.isEmpty ? '?' : t[0].toUpperCase();
}

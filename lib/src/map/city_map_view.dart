import 'dart:convert';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:webview_flutter/webview_flutter.dart';

import 'greece_cities.dart';

// Paste your MapKit JS token here (JWT from developer.apple.com → Maps → Keys)
const _kMapKitJsToken = 'eyJraWQiOiIySDdDRjVUOVRSIiwidHlwIjoiSldUIiwiYWxnIjoiRVMyNTYifQ.eyJpc3MiOiJSWjM2UE5XUzgyIiwiaWF0IjoxNzUyMDkwNjM2LCJvcmlnaW4iOiJuZXRuZXN0Lm5ldCJ9.r9qHYkpSBP65h1O9HkVJcxiYN4rHgtwdHgLyhbS0fFnbZOlvx5LcYZELtt4Q7MBQEGDFICKLp-9nUpsMlA-ZuQ';

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
  static const _channelName = 'neat/native_city_map_channel';
  late final MethodChannel _channel;
  WebViewController? _webController;
  GreeceCity? _selectedCity;

  @override
  void initState() {
    super.initState();
    _channel = const MethodChannel(_channelName);
    _channel.setMethodCallHandler(_handleNativeCall);
    if (!kIsWeb && Platform.isAndroid) {
      _initWebController();
    }
  }

  @override
  void dispose() {
    _channel.setMethodCallHandler(null);
    super.dispose();
  }

  void _initWebController() {
    final citiesJson = jsonEncode(
      greeceCities
          .map((c) => {
                'name': c.name,
                'latitude': c.latitude,
                'longitude': c.longitude,
              })
          .toList(),
    );

    _webController = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(const Color(0xff0a0a0a))
      ..addJavaScriptChannel(
        'CityChannel',
        onMessageReceived: (msg) {
          if (mounted) _showCity(msg.message);
        },
      )
      ..loadHtmlString(_buildMapHtml(citiesJson), baseUrl: 'https://netnest.net');
  }

  Future<dynamic> _handleNativeCall(MethodCall call) async {
    if (call.method == 'citySelected') {
      final city = call.arguments?.toString();
      if (city != null && city.isNotEmpty) _showCity(city);
    }
    return null;
  }

  void _showCity(String cityName) {
    final city = greeceCities.firstWhere(
      (item) => item.name == cityName,
      orElse: () => greeceCities.first,
    );
    if (_selectedCity?.name == city.name) return;
    setState(() => _selectedCity = city);
    // Camera is already moved by the WebView JS (Android) or native MapKit (iOS)
  }

  void _dismissCity() {
    if (_selectedCity == null) return;
    setState(() => _selectedCity = null);
    if (!kIsWeb && Platform.isAndroid) {
      _webController?.runJavaScript('zoomOut()');
    } else if (!kIsWeb && Platform.isIOS) {
      _channel.invokeMethod('zoomOut');
    }
  }

  void _openCityFeed() {
    final city = _selectedCity;
    if (city == null) return;
    widget.onCitySelected(city.name);
    setState(() => _selectedCity = null);
  }

  @override
  Widget build(BuildContext context) {
    final selectedCity = _selectedCity;

    return Stack(
      children: [
        Positioned.fill(
          child: _NativeMap(
            cities: greeceCities,
            webController: _webController,
          ),
        ),
        if (selectedCity != null)
          Positioned.fill(
            child: GestureDetector(
              onTap: _dismissCity,
              child: Container(
                color: Colors.black.withValues(alpha: 0.42),
                alignment: Alignment.center,
                child: GestureDetector(
                  onTap: () {},
                  child: _JoinCityCard(
                    city: selectedCity,
                    onClose: _dismissCity,
                    onJoin: _openCityFeed,
                  ),
                ),
              ),
            ),
          ),
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Align(
              alignment: Alignment.topRight,
              child: _GlassIconButton(
                icon: Icons.public,
                onTap: () {},
              ),
            ),
          ),
        ),
      ],
    );
  }
}

String _buildMapHtml(String citiesJson) {
  return '''
<!DOCTYPE html>
<html>
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="initial-scale=1.0, width=device-width">
  <style>
    * { margin: 0; padding: 0; box-sizing: border-box; }
    body { background: #0a0a0a; overflow: hidden; }
    #map { width: 100vw; height: 100vh; }
  </style>
</head>
<body>
  <div id="map"></div>
  <script>
    var _map, _overviewCenter, _overviewSpan;

    function initMap() {
      mapkit.init({
        authorizationCallback: function(done) {
          done('$_kMapKitJsToken');
        }
      });

      _map = new mapkit.Map('map', {
        colorScheme: mapkit.Map.ColorSchemes.Dark,
        showsUserLocationControl: false,
        showsCompass: mapkit.FeatureVisibility.Hidden,
        showsScale: mapkit.FeatureVisibility.Hidden,
        showsMapTypeControl: false,
        showsZoomControl: false,
      });

      _overviewCenter = new mapkit.Coordinate(39.0, 22.9);
      _overviewSpan = new mapkit.CoordinateSpan(7.5, 7.5);
      _map.region = new mapkit.CoordinateRegion(_overviewCenter, _overviewSpan);

      var cities = $citiesJson;
      cities.forEach(function(city) {
        var coord = new mapkit.Coordinate(city.latitude, city.longitude);
        var annotation = new mapkit.MarkerAnnotation(coord, {
          title: city.name,
          color: '#4CAF50',
        });
        annotation.addEventListener('select', function() {
          _map.setRegionAnimated(new mapkit.CoordinateRegion(
            coord,
            new mapkit.CoordinateSpan(0.7, 0.7)
          ));
          CityChannel.postMessage(city.name);
        });
        _map.addAnnotation(annotation);
      });
    }

    function zoomOut() {
      if (!_map) return;
      try {
        if (_map.selectedAnnotation) _map.deselectAnnotation(_map.selectedAnnotation);
      } catch(e) {}
      _map.setRegionAnimated(new mapkit.CoordinateRegion(_overviewCenter, _overviewSpan));
    }

    // Load MapKit JS dynamically — guarantees initMap runs only after the
    // script is fully parsed and mapkit is defined.
    var s = document.createElement('script');
    s.src = 'https://cdn.apple-cdn.com/mapkitjs/mapkit.js';
    s.onload = initMap;
    s.onerror = function() {
      console.error('MapKit JS failed to load from CDN');
    };
    document.head.appendChild(s);
  </script>
</body>
</html>
''';
}

class _NativeMap extends StatelessWidget {
  const _NativeMap({
    required this.cities,
    this.webController,
  });

  final List<GreeceCity> cities;
  final WebViewController? webController;

  @override
  Widget build(BuildContext context) {
    if (kIsWeb) {
      return const ColoredBox(
        color: Color(0xff050505),
        child: Center(
          child: Text(
            'Map view is available on mobile only.',
            style: TextStyle(color: Color(0xffd0d0d0)),
          ),
        ),
      );
    }

    if (Platform.isIOS) {
      return UiKitView(
        viewType: 'neat/native_city_map',
        creationParams: {
          'cities': cities
              .map(
                (city) => {
                  'name': city.name,
                  'latitude': city.latitude,
                  'longitude': city.longitude,
                },
              )
              .toList(),
        },
        creationParamsCodec: const StandardMessageCodec(),
      );
    }

    // Android — Apple MapKit JS via WebView, no Google Maps required
    final controller = webController;
    if (controller == null) {
      return const ColoredBox(color: Color(0xff0a0a0a));
    }
    return WebViewWidget(controller: controller);
  }
}

class _GlassIconButton extends StatelessWidget {
  const _GlassIconButton({
    required this.icon,
    required this.onTap,
  });

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xcc0c0c0c),
      shape: const CircleBorder(),
      child: IconButton(
        onPressed: onTap,
        icon: Icon(icon, color: Colors.white),
      ),
    );
  }
}

class _JoinCityCard extends StatelessWidget {
  const _JoinCityCard({
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
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 20),
        decoration: BoxDecoration(
          color: const Color(0xff101010),
          borderRadius: BorderRadius.circular(28),
          border: Border.all(color: const Color(0xff2a2a2a)),
          boxShadow: const [
            BoxShadow(
              color: Colors.black54,
              blurRadius: 22,
              offset: Offset(0, 12),
            ),
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
                        cityInitialFor(city.name),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 28,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    right: 8,
                    top: 8,
                    child: IconButton(
                      onPressed: onClose,
                      icon: const Icon(Icons.close, color: Colors.white),
                    ),
                  ),
                ],
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 18, 18, 20),
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
                      'You can view this city feed and join the local network.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Color(0xffababab),
                        fontSize: 13,
                        height: 1.35,
                      ),
                    ),
                    const SizedBox(height: 18),
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
    );
  }
}

String cityInitialFor(String value) {
  final trimmed = value.trim();
  if (trimmed.isEmpty) return '?';
  return trimmed.substring(0, 1).toUpperCase();
}

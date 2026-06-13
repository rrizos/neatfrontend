import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import 'greece_cities.dart';

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
  GreeceCity? _selectedCity;

  @override
  void initState() {
    super.initState();
    _channel = const MethodChannel(_channelName);
    _channel.setMethodCallHandler(_handleNativeCall);
  }

  @override
  void dispose() {
    _channel.setMethodCallHandler(null);
    super.dispose();
  }

  Future<dynamic> _handleNativeCall(MethodCall call) async {
    if (call.method == 'citySelected') {
      final city = call.arguments?.toString();
      if (city != null && city.isNotEmpty) {
        _showCity(city);
      }
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
  }

  void _openCityFeed() {
    final city = _selectedCity;
    if (city == null) return;
    widget.onCitySelected(city.name);
    setState(() => _selectedCity = null);
  }

  @override
  Widget build(BuildContext context) {
    final selectedCity = _selectedCity ?? greeceCities.first;

    return Stack(
      children: [
        Positioned.fill(
          child: _NativeMap(
            cityName: selectedCity.name,
            cities: greeceCities,
          ),
        ),
        if (_selectedCity != null)
          Positioned.fill(
            child: GestureDetector(
              onTap: () => setState(() => _selectedCity = null),
              child: Container(
                color: Colors.black.withValues(alpha: 0.42),
                alignment: Alignment.center,
                child: GestureDetector(
                  onTap: () {},
                  child: _JoinCityCard(
                    city: selectedCity,
                    onClose: () => setState(() => _selectedCity = null),
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

class _NativeMap extends StatelessWidget {
  const _NativeMap({
    required this.cityName,
    required this.cities,
  });

  final String cityName;
  final List<GreeceCity> cities;

  @override
  Widget build(BuildContext context) {
    final markers = cities
        .map(
          (city) => Marker(
            markerId: MarkerId(city.name),
            position: LatLng(city.latitude, city.longitude),
            icon: BitmapDescriptor.defaultMarkerWithHue(
              BitmapDescriptor.hueGreen,
            ),
            onTap: () {
              if (context.mounted) {
                final state =
                    context.findAncestorStateOfType<_CityMapViewState>();
                state?._showCity(city.name);
              }
            },
          ),
        )
        .toSet();

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
          'selectedCity': cityName,
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

    return GoogleMap(
      initialCameraPosition: CameraPosition(
        target: LatLng(cities.first.latitude, cities.first.longitude),
        zoom: 6.2,
      ),
      markers: markers,
      myLocationButtonEnabled: false,
      zoomControlsEnabled: false,
      mapToolbarEnabled: false,
      compassEnabled: false,
      onMapCreated: (controller) {},
    );
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
                        colors: [
                          Color(0xff1c1c1c),
                          Color(0xff090909),
                        ],
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

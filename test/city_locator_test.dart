import 'package:flutter_test/flutter_test.dart';
import 'package:neat/src/map/city_locator.dart';

void main() {
  group('nearestCity', () {
    test('resolves a point inside a city to that city', () {
      // Syntagma square, a little off the stored Athens centre.
      expect(CityLocator.nearestCity(37.9755, 23.7348)?.name, 'Αθήνα');
      // The White Tower, Thessaloniki.
      expect(CityLocator.nearestCity(40.6264, 22.9484)?.name, 'Θεσσαλονίκη');
      // Rhodes old town.
      expect(CityLocator.nearestCity(36.4443, 28.2246)?.name, 'Ρόδος');
    });

    test('resolves a point between cities to the closer one', () {
      // Just outside Larissa, ~135km from Thessaloniki.
      expect(CityLocator.nearestCity(39.6500, 22.4300)?.name, 'Λάρισα');
    });

    test('returns null far from every Greek city, so the map stays plain', () {
      expect(CityLocator.nearestCity(51.5072, -0.1276), isNull); // London
      expect(CityLocator.nearestCity(40.7128, -74.0060), isNull); // New York
      expect(CityLocator.nearestCity(-33.8688, 151.2093), isNull); // Sydney
    });

    test('returns null just past the cutoff but a city just inside it', () {
      // Due south of Crete: open sea, walking outwards from Heraklion.
      expect(CityLocator.nearestCity(34.4, 25.1442), isNotNull); // ~104km
      expect(CityLocator.nearestCity(33.5, 25.1442), isNull); // ~204km
    });

    test('handles the antimeridian and the poles without throwing', () {
      expect(CityLocator.nearestCity(0, 180), isNull);
      expect(CityLocator.nearestCity(90, 0), isNull);
      expect(CityLocator.nearestCity(-90, 0), isNull);
    });
  });
}

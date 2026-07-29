import 'package:flutter_test/flutter_test.dart';
import 'package:neat/src/core/api.dart';

void main() {
  group('friendlyError', () {
    test('offline host lookup does not leak the host or URL', () {
      const raw =
          "ClientException with SocketException: Failed host lookup: '63.181.201.175' "
          "(OS Error: nodename nor servname provided, or not known, errno = 8), "
          "uri=https://63.181.201.175/api/auth/login/";
      final msg = friendlyError(Exception(raw));
      expect(msg, 'Δεν υπάρχει σύνδεση στο διαδίκτυο. Έλεγξε τη σύνδεσή σου και δοκίμασε ξανά.');
      expect(msg.contains('63.181.201.175'), isFalse);
      expect(msg.contains('api/auth'), isFalse);
    });

    test('connection refused reads as offline', () {
      const raw =
          'SocketException: Connection refused (OS Error: Connection refused, errno = 61), '
          'address = 63.181.201.175, port = 443';
      expect(friendlyError(Exception(raw)),
          'Δεν υπάρχει σύνδεση στο διαδίκτυο. Έλεγξε τη σύνδεσή σου και δοκίμασε ξανά.');
    });

    test('web XMLHttpRequest failure reads as offline', () {
      expect(friendlyError(Exception('ClientException: XMLHttpRequest error.')),
          'Δεν υπάρχει σύνδεση στο διαδίκτυο. Έλεγξε τη σύνδεσή σου και δοκίμασε ξανά.');
    });

    test('timeout gets its own message', () {
      expect(friendlyError(Exception('TimeoutException after 0:00:30.000000')),
          'Έληξε ο χρόνος σύνδεσης. Δοκίμασε ξανά.');
    });

    test('server wording still reaches the user', () {
      expect(friendlyError(Exception('Invalid username or password')),
          'Invalid username or password');
    });

    test('any stray host/IP is scrubbed even from passthrough messages', () {
      final msg = friendlyError(
          Exception('Something broke at https://63.181.201.175/api/posts/ for 10.0.0.5:8000'));
      expect(msg.contains('63.181.201.175'), isFalse);
      expect(msg.contains('10.0.0.5'), isFalse);
      expect(msg.contains('τον διακομιστή'), isTrue);
    });
  });
}

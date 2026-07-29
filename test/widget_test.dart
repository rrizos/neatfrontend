import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neat/src/app.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    // flutter_secure_storage has no test implementation, and the auth gate
    // reads it before anything is caught. Answer "nothing stored" so a cold
    // start resolves to the signed-out landing page.
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
      (call) async => call.method == 'readAll' ? <String, String>{} : null,
    );
  });

  testWidgets('a cold start with no session lands on the landing page',
      (tester) async {
    await tester.pumpWidget(const NeatApp());
    // The landing page types its slogan out on a periodic timer, so the tree
    // never goes idle — pumpAndSettle would just time out. Pump past the
    // start delay and far enough for the typing to finish and cancel its own
    // timer, otherwise the test ends with timers still pending.
    // Three passes: the auth gate resolves on the first, the landing page
    // mounts and starts its timers on the second, and they run out on the
    // third — a test that ends with live timers fails.
    await tester.pump(const Duration(milliseconds: 700));
    await tester.pump(const Duration(seconds: 5));
    await tester.pump(const Duration(seconds: 5));

    expect(find.text('Εγγραφή'), findsOneWidget);
    expect(find.text('Σύνδεση'), findsOneWidget);
  });
}

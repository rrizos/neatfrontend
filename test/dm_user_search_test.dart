// Verifies the "new message" sheet answers as you type instead of waiting for
// a complete username plus enter.
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neat/l10n/app_localizations.dart';
import 'package:neat/src/core/models.dart';
import 'package:neat/src/messages/messages_page.dart';

UserProfile _user(String username, String fullName) =>
    UserProfile.fromJson({'username': username, 'fullName': fullName});

Widget _app() => MaterialApp(
      locale: const Locale('el'),
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      home: MessagesPage(
        // No network in a widget test: the remote leg fails and the local
        // suggestion filter is what we're checking anyway.
        token: 'test-token',
        currentUsername: 'me',
        suggestedUsers: [
          _user('maria_k', 'Μαρία Κ.'),
          _user('giorgos99', 'Γιώργος Παπαδόπουλος'),
          _user('nikos_ath', 'Νίκος Αθανασίου'),
          _user('marianna', 'Μαριάννα Λ.'),
          _user('me', 'Εγώ'),
        ],
        onLogout: () async {},
      ),
    );

void main() {
  testWidgets('typing filters people without submitting', (tester) async {
    await tester.pumpWidget(_app());
    await tester.pump(const Duration(milliseconds: 300));

    await tester.tap(find.byIcon(Icons.edit_square));
    await tester.pump(const Duration(milliseconds: 400));

    // Sheet opens on the full suggestion list.
    expect(find.text('@maria_k'), findsOneWidget);
    expect(find.text('@giorgos99'), findsOneWidget);

    // Two characters is enough — no enter, no full username.
    await tester.enterText(find.byType(TextField).last, 'mar');
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('@maria_k'), findsOneWidget);
    expect(find.text('@marianna'), findsOneWidget);
    expect(find.text('@giorgos99'), findsNothing);
    expect(find.text('@nikos_ath'), findsNothing);
  });

  testWidgets('matches full names too, and never offers you yourself',
      (tester) async {
    await tester.pumpWidget(_app());
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.byIcon(Icons.edit_square));
    await tester.pump(const Duration(milliseconds: 400));

    await tester.enterText(find.byType(TextField).last, 'Γιώργ');
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('@giorgos99'), findsOneWidget);
    expect(find.text('@maria_k'), findsNothing);

    await tester.enterText(find.byType(TextField).last, 'me');
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('@me'), findsNothing);
  });
}

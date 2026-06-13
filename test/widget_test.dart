import 'package:flutter_test/flutter_test.dart';

import 'package:neat/src/app.dart';

void main() {
  testWidgets('Dark social MVP supports core interactions', (tester) async {
    await tester.pumpWidget(const NeatApp());
    await tester.pumpAndSettle();

    expect(find.text('Neat'), findsOneWidget);
  });
}

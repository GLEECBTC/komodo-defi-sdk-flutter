import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:json_editor_flutter/json_editor_flutter.dart';

void main() {
  testWidgets('JSON editor supports popup insertion and text editing', (
    tester,
  ) async {
    final changes = <Object?>[];

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: JsonEditor(
            json: '{"method":"version"}',
            duration: const Duration(milliseconds: 10),
            onChanged: changes.add,
          ),
        ),
      ),
    );

    // Exercise the const Row menu items that failed with Dart language 2.17.
    await tester.tap(find.byTooltip('Add new object').first);
    await tester.pumpAndSettle();
    expect(find.text('Insert'), findsOneWidget);
    await tester.tap(find.text('String'));
    await tester.pumpAndSettle();
    expect(changes.last, {'method': 'version', 'new_key_added': ''});

    await tester.tap(find.byTooltip('Change editor'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Text'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byType(TextFormField),
      '{"method":"get_balance","coin":"KMD"}',
    );
    await tester.pump(const Duration(milliseconds: 20));
    expect(changes.last, {'method': 'get_balance', 'coin': 'KMD'});
    expect(tester.takeException(), isNull);
  });
}

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:komodo_ui/komodo_ui.dart';

void main() {
  for (final decorated in [false, true]) {
    testWidgets(
      'expanded card paints list tile ink over decoration: $decorated',
      (tester) async {
        var taps = 0;
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: CollapsibleCard(
                title: const Text('Assets'),
                backgroundColor: Colors.purple,
                initiallyExpanded: true,
                childrenDecoration: decorated
                    ? const BoxDecoration(color: Colors.blue)
                    : null,
                children: [
                  ListTile(
                    title: const Text('Bitcoin'),
                    tileColor: Colors.white,
                    onTap: () => taps++,
                  ),
                ],
              ),
            ),
          ),
        );

        expect(tester.takeException(), isNull);
        await tester.tap(find.text('Bitcoin'));
        await tester.pumpAndSettle();
        expect(taps, 1);
        expect(tester.takeException(), isNull);

        await tester.tap(find.byIcon(Icons.expand_more));
        await tester.pumpAndSettle();
        expect(find.text('Bitcoin'), findsNothing);
        await tester.tap(find.byIcon(Icons.expand_more));
        await tester.pumpAndSettle();
        expect(find.text('Bitcoin'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }
}

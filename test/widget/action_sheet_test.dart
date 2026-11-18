import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:scanly/shared/widgets/action_sheet.dart';

void main() {
  testWidgets('a long action sheet scrolls instead of overflowing', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(320, 480));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    int? picked;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () async {
                  picked = await showActionSheet<int>(
                    context,
                    title: 'A document with a fairly long title',
                    actions: [
                      for (var i = 0; i < 12; i++)
                        SheetAction(
                          value: i,
                          label: 'Action $i',
                          icon: Icons.star_outline_rounded,
                          destructive: i == 11,
                        ),
                    ],
                  );
                },
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull, reason: 'no layout overflow');
    expect(find.text('Action 0'), findsOneWidget);

    // The last entry is off screen until the sheet is scrolled.
    await tester.scrollUntilVisible(
      find.text('Action 11'),
      100,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.tap(find.text('Action 11'));
    await tester.pumpAndSettle();

    expect(picked, 11);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a short action sheet still works', (tester) async {
    String? picked;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async {
                picked = await showActionSheet<String>(
                  context,
                  actions: const [
                    SheetAction(value: 'a', label: 'Rename', icon: Icons.edit),
                  ],
                );
              },
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Rename'));
    await tester.pumpAndSettle();
    expect(picked, 'a');
  });
}

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sirb/shared/widgets/desktop_context_menu.dart';

void main() {
  testWidgets('showDesktopContextMenu opens, dismisses on single tap outside, and closes on re-open', (tester) async {
    String? selectedValue;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: ElevatedButton(
                onPressed: () async {
                  final res = await showDesktopContextMenu<String>(
                    context: context,
                    position: const RelativeRect.fromLTRB(100, 100, 100, 100),
                    items: const [
                      PopupMenuItem(value: 'item1', child: Text('Item 1')),
                      PopupMenuItem(value: 'item2', child: Text('Item 2')),
                    ],
                  );
                  selectedValue = res;
                },
                child: const Text('Open Menu'),
              ),
            ),
          ),
        ),
      ),
    );

    // Click button to open menu
    await tester.tap(find.text('Open Menu'));
    await tester.pumpAndSettle();

    expect(find.text('Item 1'), findsOneWidget);
    expect(find.text('Item 2'), findsOneWidget);

    // Tap outside at (10, 10) once
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();

    // Menu should be gone on the single click!
    expect(find.text('Item 1'), findsNothing);
    expect(selectedValue, isNull);

    // Re-open menu
    await tester.tap(find.text('Open Menu'));
    await tester.pumpAndSettle();
    expect(find.text('Item 1'), findsOneWidget);

    // Select Item 2
    await tester.tap(find.text('Item 2'));
    await tester.pumpAndSettle();

    expect(find.text('Item 1'), findsNothing);
    expect(selectedValue, 'item2');

    // Test that opening a second menu replaces the first without stacking
    await tester.tap(find.text('Open Menu'));
    await tester.pumpAndSettle();
    expect(find.text('Item 1'), findsOneWidget);

    // Open another menu while first is active
    final context = tester.element(find.byType(ElevatedButton));
    unawaited(showDesktopContextMenu<String>(
      context: context,
      position: const RelativeRect.fromLTRB(200, 200, 200, 200),
      items: const [
        PopupMenuItem(value: 'second', child: Text('Second Menu')),
      ],
    ));
    await tester.pumpAndSettle();

    // There should ONLY be 'Second Menu', and 'Item 1' should be gone
    expect(find.text('Item 1'), findsNothing);
    expect(find.text('Second Menu'), findsOneWidget);

    // Tap outside once -> Second Menu should disappear
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();
    expect(find.text('Second Menu'), findsNothing);
  });
}

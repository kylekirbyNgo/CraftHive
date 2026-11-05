import 'package:crafthive/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:crafthive/core/theme/app_theme.dart';

void main() {
  setUpAll(() => AppText.useGoogleFonts = false);

  testWidgets('Log in leads to Home, and the bottom bar switches tabs', (tester) async {
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(const ProviderScope(child: CraftHiveApp()));
    await tester.pumpAndSettle();
    expect(find.text('Welcome back'), findsOneWidget);

    await tester.enterText(find.byType(TextFormField).at(0), 'ana.makes');
    await tester.enterText(find.byType(TextFormField).at(1), 'craftlover8');
    await tester.tap(find.text('Log in'));
    await tester.pumpAndSettle(const Duration(seconds: 1));

    expect(find.text('Featured'), findsOneWidget);
    expect(find.text('More to explore'), findsOneWidget);

    await tester.tap(find.text('Messages').last);
    await tester.pumpAndSettle();
    expect(find.text('Shops I order from'), findsOneWidget);

    await tester.tap(find.text('Orders').last);
    await tester.pumpAndSettle();
    expect(find.text('What I ordered'), findsOneWidget);
  });
}

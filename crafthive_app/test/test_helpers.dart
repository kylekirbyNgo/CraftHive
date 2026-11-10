import 'package:crafthive/core/theme/app_theme.dart';
import 'package:crafthive/data/providers.dart';
import 'package:crafthive/data/repositories/fake_repositories.dart';
import 'package:crafthive/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Starts the whole app with in-memory accounts and listings instead of Supabase.
Future<void> pumpApp(WidgetTester tester, {FakeAuthRepository? auth, FakeCatalogRepository? catalog}) async {
  AppText.useGoogleFonts = false;
  SharedPreferences.setMockInitialValues({});
  tester.view.physicalSize = const Size(1170, 2532);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(ProviderScope(
    overrides: [
      authRepositoryProvider.overrideWithValue(auth ?? FakeAuthRepository()),
      catalogRepositoryProvider.overrideWithValue(catalog ?? FakeCatalogRepository()),
    ],
    child: const CraftHiveApp(),
  ));
  await tester.pumpAndSettle();
}

Finder field(int index) => find.byType(TextFormField).at(index);

Future<void> tapText(WidgetTester tester, String text) async {
  final f = find.text(text).last;
  await tester.ensureVisible(f);
  await tester.pumpAndSettle();
  await tester.tap(f);
  await tester.pumpAndSettle();
}

Future<void> logIn(WidgetTester tester, String id, String password) async {
  await tester.enterText(field(0), id);
  await tester.enterText(field(1), password);
  await tapText(tester, 'Log in');
}

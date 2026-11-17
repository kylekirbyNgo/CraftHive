import 'package:crafthive/core/utils/share_links.dart';
import 'package:crafthive/data/mock_data.dart';
import 'package:crafthive/data/repositories/fake_repositories.dart';
import 'package:crafthive/data/sample_ids.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'test_helpers.dart';

Future<void> _go(WidgetTester tester, String path) async {
  final app = tester.widget<MaterialApp>(find.byType(MaterialApp));
  (app.routerConfig! as GoRouter).go(path);
  await tester.pumpAndSettle();
}

void main() {
  final spoon = MockData.products.firstWhere((p) => p.id == SampleIds.p1);
  final narra = MockData.sellers.firstWhere((s) => s.id == SampleIds.storeNarra);

  group('Share links', () {
    test('item and store links on the app scheme', () {
      expect(ShareLinks.product('abc-1'), 'ph.crafthive.app://open/product/abc-1');
      expect(ShareLinks.store('st-9'), 'ph.crafthive.app://open/store/st-9');
    });

    test('a link opens the right screen; anything else is ignored', () {
      expect(ShareLinks.routeFor(Uri.parse('ph.crafthive.app://open/product/abc-1')), '/product/abc-1');
      expect(ShareLinks.routeFor(Uri.parse('ph.crafthive.app://open/store/st-9')), '/seller/st-9');
      expect(ShareLinks.routeFor(Uri.parse('ph.crafthive.app://open/store/st-9'), myStoreId: 'st-9'), '/store');
      expect(ShareLinks.routeFor(Uri.parse('ph.crafthive.app://reset-password#access_token=x')), isNull);
      expect(ShareLinks.routeFor(Uri.parse('ph.crafthive.app://open/product/../admin')), isNull);
      expect(ShareLinks.routeFor(Uri.parse('https://example.com/open/product/abc')), isNull);
    });

    test('the message names the item, price and store', () {
      final text = ShareLinks.productText(spoon, narra);
      expect(text, contains('Hand-carved Wooden Spoon – ₱350 by Narra Craft Co. (Baguio City)'));
      expect(text, contains('Custom orders welcome.'));
      expect(text, endsWith(ShareLinks.product(SampleIds.p1)));
      expect(ShareLinks.storeText(narra, SampleIds.storeNarra, listings: 2), startsWith('Narra Craft Co. (Verified Maker) – handmade in Baguio City'));
    });
  });

  group('Sharing', () {
    testWidgets('TC-SH01 share an item from its page', (tester) async {
      final sharer = FakeSharer();
      await pumpApp(tester, auth: FakeAuthRepository(signedIn: true), sharer: sharer);
      await _go(tester, '/product/${SampleIds.p1}');
      await tester.tap(find.byTooltip('Share item'));
      await tester.pumpAndSettle();
      expect(sharer.shared.single, contains('Hand-carved Wooden Spoon'));
      expect(sharer.shared.single, contains(ShareLinks.product(SampleIds.p1)));
    });

    testWidgets('TC-SH02 share a store from its page', (tester) async {
      final sharer = FakeSharer();
      await pumpApp(tester, auth: FakeAuthRepository(signedIn: true), sharer: sharer);
      await _go(tester, '/seller/${SampleIds.storeNarra}');
      await tester.tap(find.byTooltip('Share store'));
      await tester.pumpAndSettle();
      expect(sharer.shared.single, contains(ShareLinks.store(SampleIds.storeNarra)));
    });

    testWidgets('TC-SH03 sharing my own store uses its real store ID', (tester) async {
      final sharer = FakeSharer();
      await pumpApp(tester, auth: FakeAuthRepository(signedIn: true), sharer: sharer);
      await _go(tester, '/store');
      await tapText(tester, 'Share store');
      expect(sharer.shared.single, contains(ShareLinks.store('store-me')));
    });

    testWidgets('TC-SH04 a shared link opens the item in the app', (tester) async {
      final sharer = FakeSharer();
      await pumpApp(tester, auth: FakeAuthRepository(signedIn: true), sharer: sharer);
      sharer.links.add(Uri.parse(ShareLinks.product(SampleIds.p1)));
      await tester.pumpAndSettle();
      expect(find.text('Hand-carved Wooden Spoon'), findsWidgets);
      expect(find.byTooltip('Share item'), findsOneWidget);
    });

    testWidgets('TC-SH05 a link opened while signed out opens after logging in', (tester) async {
      final sharer = FakeSharer()..initial = Uri.parse(ShareLinks.store(SampleIds.storeNarra));
      await pumpApp(tester, sharer: sharer);
      expect(find.text('Welcome back'), findsOneWidget);
      await logIn(tester, 'ana.makes', FakeAuthRepository.demoPassword);
      expect(find.byTooltip('Share store'), findsOneWidget);
      expect(find.text('Narra Craft Co.'), findsWidgets);
    });
  });
}

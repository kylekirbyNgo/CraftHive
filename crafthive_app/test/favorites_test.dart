import 'package:crafthive/data/repositories/auth_repository.dart';
import 'package:crafthive/data/repositories/catalog_repository.dart';
import 'package:crafthive/data/repositories/fake_repositories.dart';
import 'package:crafthive/data/sample_ids.dart';
import 'package:flutter_test/flutter_test.dart';

import 'test_helpers.dart';

/// Favorites (Firestore users/{uid}/savedItems and productStats.saveCount) and
/// store owners' photos on store cards.
void main() {
  const spoon = 'Hand-carved Wooden Spoon'; // SampleIds.p1

  Future<void> tapLabel(WidgetTester tester, String label) async {
    final f = find.bySemanticsLabel(label).first;
    await tester.ensureVisible(f);
    await tester.pumpAndSettle();
    await tester.tap(f);
    await tester.pumpAndSettle();
  }

  group('Favorites', () {
    testWidgets('TC-F01 the heart saves an item, counts it, and it shows in the Saved tab', (tester) async {
      final saved = FakeSavedRepository(saved: {});
      await pumpApp(tester, auth: FakeAuthRepository(signedIn: true), saved: saved);

      await tapLabel(tester, 'Save $spoon');
      expect(saved.saved, contains(SampleIds.p1));
      expect(saved.counts[SampleIds.p1], 1);
      expect(find.bySemanticsLabel('Remove $spoon from saved'), findsWidgets);

      await tester.tap(find.text('Saved').last);
      await tester.pumpAndSettle();
      expect(find.text('1 item'), findsOneWidget);
      expect(find.text(spoon), findsWidgets);
    });

    testWidgets('TC-F02 removing an item from the Saved tab', (tester) async {
      final saved = FakeSavedRepository(counts: {SampleIds.p2: 4});
      await pumpApp(tester, auth: FakeAuthRepository(signedIn: true), saved: saved);
      await tester.tap(find.text('Saved').last);
      await tester.pumpAndSettle();
      expect(find.text('3 items'), findsOneWidget);

      await tapLabel(tester, 'Remove Hand-tied Sunflower Bouquet from saved');
      expect(saved.saved, isNot(contains(SampleIds.p2)));
      expect(saved.counts[SampleIds.p2], 3);
      expect(find.text('2 items'), findsOneWidget);
    });

    testWidgets('TC-F03 when saving fails, the heart goes back', (tester) async {
      final saved = FakeSavedRepository(saved: {})..failWith = const AppFailure('No internet connection.');
      await pumpApp(tester, auth: FakeAuthRepository(signedIn: true), saved: saved);

      await tapLabel(tester, 'Save $spoon');
      expect(saved.saved, isEmpty);
      expect(find.bySemanticsLabel('Remove $spoon from saved'), findsNothing);
      expect(find.bySemanticsLabel('Save $spoon'), findsWidgets);
    });

    test('TC-F04 saving the same item twice counts it once', () async {
      final saved = FakeSavedRepository(saved: {});
      await saved.setSaved('me', SampleIds.p1, true);
      await saved.setSaved('me', SampleIds.p1, true);
      expect(saved.counts[SampleIds.p1], 1);
      await saved.setSaved('me', SampleIds.p1, false);
      await saved.setSaved('me', SampleIds.p1, false);
      expect(saved.counts[SampleIds.p1], 0);
    });
  });

  group('Store photos', () {
    final row = {
      'store_id': 'store-1',
      'store_name': 'Ana Makes',
      'city': 'Cebu City',
      'verification_status': 'verified',
      'rating': 4.5,
      'items_sold_count': 12,
      'store_description': 'Crochet',
    };

    test('TC-F05 a store card shows the owner\'s photo when there is one', () {
      final withPhoto = sellerFromRow({...row, 'avatar_path': 'u1/avatar_1.jpg'}, isMine: false, avatarUrl: (p) => 'https://cdn/avatars/$p');
      expect(withPhoto.avatarUrl, 'https://cdn/avatars/u1/avatar_1.jpg');

      final noPhoto = sellerFromRow({...row, 'avatar_path': null}, isMine: false, avatarUrl: (p) => 'https://cdn/avatars/$p');
      expect(noPhoto.avatarUrl, isNull);
      expect(noPhoto.initials, 'AM');
    });
  });
}

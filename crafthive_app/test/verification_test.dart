import 'dart:typed_data';

import 'package:crafthive/data/models.dart';
import 'package:crafthive/data/providers.dart';
import 'package:crafthive/data/repositories/auth_repository.dart';
import 'package:crafthive/data/repositories/fake_repositories.dart';
import 'package:crafthive/data/repositories/order_repository.dart';
import 'package:crafthive/data/repositories/verification_repository.dart';
import 'package:crafthive/shared/widgets/action_helpers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'test_helpers.dart';

/// A 1×1 PNG, so Image.memory has something real to show.
final _png = Uint8List.fromList(const [
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
  0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4, 0x89, 0x00, 0x00, 0x00, 0x0D, 0x49, 0x44, 0x41, 0x54, 0x78, 0x9C, 0x63, 0xF8, 0xCF, 0xC0, 0xF0,
  0x1F, 0x00, 0x05, 0x00, 0x01, 0xFF, 0x89, 0x99, 0x3D, 0x1D, 0x00, 0x00, 0x00, 0x00, 0x49, 0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82,
]);

final _picker = photoPickerProvider.overrideWithValue((_) async => PickedImage(bytes: _png, fileName: 'photo.png'));

/// Scrolls the screen's list until [text] is built, then taps it.
Future<void> _tap(WidgetTester tester, String text) async {
  await _show(tester, text);
  await tapText(tester, text);
}

Future<void> _show(WidgetTester tester, String text) async {
  await tester.scrollUntilVisible(find.text(text), 200, scrollable: find.byType(Scrollable).first);
  await tester.pumpAndSettle();
}

Future<void> _openVerification(WidgetTester tester) async {
  await tester.tap(find.bySemanticsLabel('My profile and store'));
  await tester.pumpAndSettle();
  await tapText(tester, 'Verified Maker');
}

void main() {
  group('Verification mapping', () {
    test('my_verification JSON', () {
      final v = myVerificationFromJson({
        'status': 'rejected',
        'id_type': 'Passport',
        'submitted_at': '2026-11-01T02:00:00Z',
        'review_note': 'Blurry photo',
        'id_purge_date': '2026-12-02',
        'id_on_file': true,
        'portfolio': ['u/verification/p1.jpg', 'u/verification/p2.jpg'],
      });
      expect(v.status, VerificationStatus.rejected);
      expect(v.status.canApply, isTrue);
      expect(v.reviewNote, 'Blurry photo');
      expect(v.idPurgeDate, DateTime(2026, 12, 2));
      expect(v.portfolio, hasLength(2));
    });

    test('unknown or missing status is "not verified"', () {
      expect(verificationStatusFromDb(null), VerificationStatus.unverified);
      expect(verificationStatusFromDb('pending').canApply, isFalse);
      expect(myVerificationFromJson({}).status, VerificationStatus.unverified);
    });

    test('an application for admins; a deleted ID has no path', () {
      final a = applicationFromJson({
        'seller_id': 's1',
        'store_name': 'Clayfolk Studio',
        'full_name': 'Lia Cruz',
        'username': 'clayfolk',
        'city': 'Davao City',
        'status': 'verified',
        'submitted_at': '2026-10-01T00:00:00Z',
        'id_image_path': null,
        'portfolio': ['s1/verification/p.jpg'],
      });
      expect(a.status, VerificationStatus.verified);
      expect(a.idImagePath, isNull);
      expect(a.portfolio.single, 's1/verification/p.jpg');
    });

    test('an ADMIN row becomes an admin user', () {
      final u = adminUserFromRow('x', {'first_name': 'CraftHive', 'last_name': 'Admin', 'email': 'admin@crafthive.test'});
      expect(u.isAdmin, isTrue);
      expect(u.displayName, 'CraftHive Admin');
    });
  });

  group('Verified Maker', () {
    testWidgets('TC-V01 a maker sends an ID and work photos for review', (tester) async {
      final repo = FakeVerificationRepository(mine: const MyVerification());
      await pumpApp(tester, auth: FakeAuthRepository(signedIn: true), verification: repo, extra: [_picker]);
      await _openVerification(tester);
      expect(find.text('Get the Verified Maker badge'), findsOneWidget);

      await _tap(tester, 'Send for review');
      expect(find.text('Choose the type of ID you are sending.'), findsOneWidget);

      await _show(tester, 'Type of ID');
      await tester.tap(find.text('Type of ID'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('PhilSys National ID').last);
      await tester.pumpAndSettle();
      await _tap(tester, 'Add ID photo');
      await _tap(tester, 'Add photo');
      await _tap(tester, 'Send for review');
      expect(find.text('Add at least 2 photos of your work.'), findsOneWidget);

      await _tap(tester, 'Add photo');
      await tester.ensureVisible(find.byType(CheckboxListTile));
      await tester.tap(find.byType(CheckboxListTile));
      await tester.pumpAndSettle();
      await _tap(tester, 'Send for review');

      expect(repo.mine.status, VerificationStatus.pending);
      expect(repo.mine.portfolio, hasLength(2));
      expect(find.text('Under review'), findsWidgets);
      expect(find.text('Send for review'), findsNothing);
    });

    testWidgets('TC-V02 a rejected maker sees why and can send again', (tester) async {
      final repo = FakeVerificationRepository(
          mine: MyVerification(status: VerificationStatus.rejected, reviewNote: 'The ID photo is blurry.', idPurgeDate: DateTime(2030, 1, 1), idOnFile: true));
      await pumpApp(tester, auth: FakeAuthRepository(signedIn: true), verification: repo, extra: [_picker]);
      await _openVerification(tester);
      expect(find.textContaining('The ID photo is blurry.'), findsOneWidget);
      expect(find.textContaining('will be deleted on Jan 1, 2030'), findsOneWidget);
      await _show(tester, 'Send for review');
      expect(find.text('Send for review'), findsOneWidget);
    });

    testWidgets('TC-V03 an admin logs in and approves a maker', (tester) async {
      final repo = FakeVerificationRepository();
      await pumpApp(tester, verification: repo);
      await logIn(tester, 'admin@crafthive.test', FakeAuthRepository.demoPassword);
      expect(find.text('CraftHive admin'), findsOneWidget);
      expect(find.text('Makers (1)'), findsOneWidget);

      await tapText(tester, 'Makers (1)'); // the admin home opens on Overview
      await tapText(tester, 'LayerLab PH');
      expect(find.textContaining("Driver's License"), findsOneWidget);
      await _tap(tester, 'Approve');
      await tapText(tester, 'Approve'); // confirm dialog

      expect(repo.applications.single.status, VerificationStatus.verified);
      expect(repo.applications.single.idPurgeDate, isNotNull);
      expect(find.text('No one is waiting'), findsOneWidget);
    });

    testWidgets('TC-V04 rejecting needs a reason the maker will see', (tester) async {
      final repo = FakeVerificationRepository();
      await pumpApp(tester, auth: FakeAuthRepository(signedInAsAdmin: true), verification: repo);
      await tapText(tester, 'Makers (1)'); // the admin home opens on Overview
      await tapText(tester, 'LayerLab PH');
      await _tap(tester, 'Not approved');
      await tester.enterText(find.byType(TextField).last, 'Name on ID does not match.');
      await tapText(tester, 'Send decision');

      final a = repo.applications.single;
      expect(a.status, VerificationStatus.rejected);
      expect(a.reviewNote, 'Name on ID does not match.');
      await tapText(tester, 'Reviewed');
      expect(find.text('LayerLab PH'), findsOneWidget);
      expect(find.text('Not approved'), findsOneWidget);
    });

    testWidgets('TC-V05 buyers and makers never see the admin screens', (tester) async {
      await pumpApp(tester, auth: FakeAuthRepository(signedIn: true));
      expect(find.text('CraftHive admin'), findsNothing);
      final router = (tester.widget(find.byType(MaterialApp)) as MaterialApp).routerConfig!;
      (router as dynamic).go('/admin');
      await tester.pumpAndSettle();
      expect(find.text('CraftHive admin'), findsNothing);
    });
  });
}

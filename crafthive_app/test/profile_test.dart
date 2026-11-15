import 'package:crafthive/core/utils/validators.dart';
import 'package:crafthive/data/repositories/fake_repositories.dart';
import 'package:flutter_test/flutter_test.dart';

import 'test_helpers.dart';

/// Edit profile: name, phone, store description, city, email and photo.
void main() {
  Future<void> openEditProfile(WidgetTester tester, FakeAuthRepository auth) async {
    await pumpApp(tester, auth: auth);
    await tester.tap(find.bySemanticsLabel('My profile and store'));
    await tester.pumpAndSettle();
    await tapText(tester, 'Edit profile');
  }

  group('Edit profile', () {
    // Fields: 0 name, 1 store description, 2 city, 3 phone, 4 email.
    testWidgets('TC-E01 saving updates the name, store description, city and phone', (tester) async {
      final auth = FakeAuthRepository(signedIn: true);
      await openEditProfile(tester, auth);
      await tester.enterText(field(0), 'Ana Reyes-Cruz');
      await tester.enterText(field(1), 'Crochet flowers and keychains. Orders take 3 to 5 days.');
      await tester.enterText(field(2), 'Cebu City');
      await tester.enterText(field(3), '918 765 4321');
      await tapText(tester, 'Save changes');

      expect(find.text('Profile saved.'), findsOneWidget);
      final saved = await auth.loadProfile(FakeAuthRepository.demoUser.id);
      expect(saved.displayName, 'Ana Reyes-Cruz');
      expect(saved.bio, 'Crochet flowers and keychains. Orders take 3 to 5 days.');
      expect(saved.location, 'Cebu City');
      expect(saved.phoneDigits, '639187654321');
      expect(saved.phone, '+63 918 765 4321');
    });

    testWidgets('TC-E02 wrong entries show a message and nothing is saved', (tester) async {
      final auth = FakeAuthRepository(signedIn: true);
      await openEditProfile(tester, auth);
      await tester.enterText(field(0), '');
      await tester.enterText(field(2), '');
      await tester.enterText(field(3), '123');
      await tester.enterText(field(4), 'not-an-email');
      await tapText(tester, 'Save changes');

      expect(find.text('Enter your full name.'), findsOneWidget);
      expect(find.text('Enter your city.'), findsOneWidget);
      expect(find.text('Enter the 10-digit mobile number, like 917 123 4567.'), findsOneWidget);
      expect(find.text('Enter a valid email address, like you@email.com.'), findsOneWidget);
      final saved = await auth.loadProfile(FakeAuthRepository.demoUser.id);
      expect(saved.displayName, FakeAuthRepository.demoUser.displayName);
    });

    testWidgets('TC-E03 a new email waits for the confirmation link', (tester) async {
      final auth = FakeAuthRepository(signedIn: true);
      await openEditProfile(tester, auth);
      await tester.enterText(field(4), 'Ana.New@Email.com');
      await tapText(tester, 'Save changes');

      expect(auth.pendingEmail, 'ana.new@email.com');
      expect(find.textContaining('Open the link we sent to ana.new@email.com'), findsOneWidget);
      // The email itself changes only after the link is opened.
      final saved = await auth.loadProfile(FakeAuthRepository.demoUser.id);
      expect(saved.email, FakeAuthRepository.demoUser.email);
    });
  });

  group('Phone numbers', () {
    test('TC-E04 the saved number is shown without its country code for editing', () {
      expect(Validators.localPhone('Philippines', '639171234567'), '9171234567');
      expect(Validators.localPhone('Singapore', '6581234567'), '81234567');
      expect(Validators.localPhone('Philippines', '9171234567'), '9171234567');
      expect(Validators.storedPhone(Validators.dialCodes['Philippines']!, '917 123 4567'), '639171234567');
    });

    test('TC-E05 city is required and at most 50 characters', () {
      expect(Validators.city('Cebu City'), isNull);
      expect(Validators.city(' '), 'Enter your city.');
      expect(Validators.city('x' * 51), 'City must be 50 characters or fewer.');
    });
  });
}

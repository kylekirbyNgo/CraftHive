import 'package:crafthive/data/repositories/auth_repository.dart';
import 'package:crafthive/data/repositories/fake_repositories.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'test_helpers.dart';

void main() {
  group('Log in', () {
    testWidgets('TC-L01 empty fields show what is missing', (tester) async {
      await pumpApp(tester);
      expect(find.text('Welcome back'), findsOneWidget);
      await tapText(tester, 'Log in');
      expect(find.text('Enter your username or email.'), findsOneWidget);
      expect(find.text('Enter your password.'), findsOneWidget);
    });

    testWidgets('TC-L02 wrong password shows an error and stays on Log in', (tester) async {
      await pumpApp(tester);
      await logIn(tester, 'ana.makes', 'wrongpass1');
      expect(find.text(wrongLoginMessage), findsOneWidget);
      expect(find.text('Welcome back'), findsOneWidget);
    });

    testWidgets('TC-L03 username log in opens Home and the bottom bar switches tabs', (tester) async {
      await pumpApp(tester);
      await logIn(tester, 'ana.makes', FakeAuthRepository.demoPassword);
      expect(find.text('Featured'), findsOneWidget);
      expect(find.text('More to explore'), findsOneWidget);
      expect(find.textContaining('Ana'), findsWidgets);

      await tester.tap(find.text('Messages').last);
      await tester.pumpAndSettle();
      expect(find.text('Shops I order from'), findsOneWidget);

      await tester.tap(find.text('Orders').last);
      await tester.pumpAndSettle();
      expect(find.text('What I ordered'), findsOneWidget);
    });

    testWidgets('TC-L04 email log in works too (any letter case)', (tester) async {
      await pumpApp(tester);
      await logIn(tester, '  Ana.Reyes@Email.com ', FakeAuthRepository.demoPassword);
      expect(find.text('Featured'), findsOneWidget);
    });

    testWidgets('TC-L05 no internet shows a connection message', (tester) async {
      final auth = FakeAuthRepository();
      await pumpApp(tester, auth: auth);
      auth.failWith = const AppFailure(offlineMessage);
      await logIn(tester, 'ana.makes', FakeAuthRepository.demoPassword);
      expect(find.text(offlineMessage), findsOneWidget);
    });

    testWidgets('TC-L06 a saved session opens Home without logging in again', (tester) async {
      await pumpApp(tester, auth: FakeAuthRepository(signedIn: true));
      expect(find.text('Welcome back'), findsNothing);
      expect(find.text('Featured'), findsOneWidget);
    });
  });

  group('Sign up', () {
    Future<void> openSignUp(WidgetTester tester) async {
      await pumpApp(tester);
      await tapText(tester, 'Create an account');
      expect(find.text('Create your account'), findsOneWidget);
    }

    Future<void> fill(WidgetTester tester, {String name = 'Juan Dela Cruz', String email = 'juan@email.com', String phone = '917 555 1234', String username = 'juan.dc', String password = 'handmade24'}) async {
      await tester.enterText(field(0), name);
      await tester.enterText(field(1), email);
      await tester.enterText(field(2), phone);
      await tester.enterText(field(3), username);
      await tester.enterText(field(4), password);
      await tester.pumpAndSettle();
    }

    testWidgets('TC-S01 invalid entries show a message under each field', (tester) async {
      await openSignUp(tester);
      await fill(tester, name: 'J', email: 'juan@', phone: '12345', username: 'Ju', password: 'short');
      await tapText(tester, 'Sign up');
      expect(find.text('Name is too short.'), findsOneWidget);
      expect(find.text('Enter a valid email address, like you@email.com.'), findsOneWidget);
      expect(find.text('Enter the 10-digit mobile number, like 917 123 4567.'), findsOneWidget);
      expect(find.text('Use lowercase letters only.'), findsOneWidget);
      expect(find.text('Use at least 8 characters.'), findsOneWidget);
      expect(find.text('Please accept the terms to continue.'), findsOneWidget);
    });

    testWidgets('TC-S02 a taken username is flagged on the username field', (tester) async {
      await openSignUp(tester);
      await fill(tester, username: 'ana.makes');
      await tester.ensureVisible(find.byType(Checkbox));
      await tester.tap(find.byType(Checkbox));
      await tapText(tester, 'Sign up');
      expect(find.text('That username is already taken. Try another one.'), findsOneWidget);
      expect(find.text('Create your account'), findsOneWidget);
    });

    testWidgets('TC-S03 a used email is flagged on the email field', (tester) async {
      await openSignUp(tester);
      await fill(tester, email: 'ana.reyes@email.com');
      await tester.ensureVisible(find.byType(Checkbox));
      await tester.tap(find.byType(Checkbox));
      await tapText(tester, 'Sign up');
      expect(find.text('An account with this email already exists. Log in instead.'), findsOneWidget);
    });

    testWidgets('TC-S04 a valid sign-up creates the account and opens Home', (tester) async {
      await openSignUp(tester);
      await fill(tester);
      await tester.ensureVisible(find.byType(Checkbox));
      await tester.tap(find.byType(Checkbox));
      await tapText(tester, 'Sign up');
      expect(find.text('Featured'), findsOneWidget);
      expect(find.textContaining('Juan'), findsWidgets);
    });
  });

  group('Forgot password', () {
    testWidgets('TC-F01 reset link opens Choose a new password, which saves and logs in', (tester) async {
      final auth = FakeAuthRepository();
      await pumpApp(tester, auth: auth);
      await tapText(tester, 'Forgot password?');
      await tester.enterText(field(0), 'ana.reyes@email.com');
      await tapText(tester, 'Send reset link');
      expect(auth.lastResetEmail, 'ana.reyes@email.com');
      expect(find.text('Check your email'), findsOneWidget);

      auth.openResetLink(); // the user taps the link in the email
      await tester.pumpAndSettle();
      expect(find.text('Choose a new password'), findsOneWidget);

      await tester.enterText(field(0), 'newpass123');
      await tester.enterText(field(1), 'newpass124');
      await tapText(tester, 'Save new password');
      expect(find.text('The passwords do not match.'), findsOneWidget);

      await tester.enterText(field(1), 'newpass123');
      await tapText(tester, 'Save new password');
      expect(find.text('Featured'), findsOneWidget);
    });

    testWidgets('TC-F02 an invalid email is caught before sending', (tester) async {
      final auth = FakeAuthRepository();
      await pumpApp(tester, auth: auth);
      await tapText(tester, 'Forgot password?');
      await tester.enterText(field(0), 'ana.reyes@');
      await tapText(tester, 'Send reset link');
      expect(find.text('Enter a valid email address, like you@email.com.'), findsOneWidget);
      expect(auth.lastResetEmail, isNull);
    });
  });

  group('Home', () {
    testWidgets('TC-H01 shows featured items, categories and listings from the catalog', (tester) async {
      await pumpApp(tester, auth: FakeAuthRepository(signedIn: true));
      expect(find.text('Featured'), findsOneWidget);
      expect(find.text('Categories'), findsOneWidget);
      expect(find.text('Hand-carved Wooden Spoon'), findsWidgets);
      expect(find.text('Flowers'), findsOneWidget);
      // The user's own listings are not suggested to them.
      expect(find.text('Crochet Tote Bag'), findsNothing);
    });

    testWidgets('TC-H02 a failed load shows Try again, which recovers', (tester) async {
      final catalog = FakeCatalogRepository()..failWith = const AppFailure(offlineMessage);
      await pumpApp(tester, auth: FakeAuthRepository(signedIn: true), catalog: catalog);
      expect(find.text("We couldn't load the crafts"), findsOneWidget);
      expect(find.text(offlineMessage), findsOneWidget);

      catalog.failWith = null;
      await tapText(tester, 'Try again');
      expect(find.text('Featured'), findsOneWidget);
    });

    testWidgets('TC-H03 pull down to refresh reloads the listings', (tester) async {
      final catalog = FakeCatalogRepository();
      await pumpApp(tester, auth: FakeAuthRepository(signedIn: true), catalog: catalog);
      final before = catalog.loads;
      await tester.fling(find.text('Featured'), const Offset(0, 400), 1000);
      await tester.pumpAndSettle();
      expect(catalog.loads, before + 1);
    });

    testWidgets('TC-H04 a category tile opens search filtered to it', (tester) async {
      await pumpApp(tester, auth: FakeAuthRepository(signedIn: true));
      await tester.tap(find.text('Flowers').first);
      await tester.pumpAndSettle();
      expect(find.text('Hand-tied Sunflower Bouquet'), findsWidgets);
      expect(find.text('Hand-carved Wooden Spoon'), findsNothing);
    });
  });
}

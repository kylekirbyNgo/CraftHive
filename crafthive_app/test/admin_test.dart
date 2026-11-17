import 'package:crafthive/data/models.dart';
import 'package:crafthive/data/repositories/admin_repository.dart';
import 'package:crafthive/data/repositories/auth_repository.dart';
import 'package:crafthive/data/repositories/fake_repositories.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'test_helpers.dart';

void main() {
  group('Admin mapping', () {
    test('dashboard numbers', () {
      final d = dashboardFromJson({
        'my_role': 'moderator',
        'makers_waiting': 3,
        'oldest_waiting_at': '2026-11-10T01:00:00Z',
        'disputes_open': 2,
        'disputes_under_review': 1,
        'ids_overdue': 4,
      });
      expect(d.makersWaiting, 3);
      expect(d.disputesActive, 3);
      expect(d.idsOverdue, 4);
      expect(d.oldestWaitingAt, isNotNull);
      expect(dashboardFromJson({}).makersWaiting, 0);
    });

    test('staff rows and admin roles', () {
      final s = staffFromJson({'admin_id': 'a1', 'first_name': 'Lea', 'last_name': 'Santos', 'email': 'lea@crafthive.test', 'role': 'superadmin', 'is_active': false});
      expect(s.name, 'Lea Santos');
      expect(s.isSuperadmin, isTrue);
      expect(s.isActive, isFalse);
      final u = adminUserFromRow('x', {'first_name': 'Lea', 'last_name': 'Santos', 'email': 'lea@crafthive.test', 'role': 'moderator'});
      expect(u.isAdmin, isTrue);
      expect(u.isSuperadmin, isFalse);
    });
  });

  group('Admin dashboard', () {
    testWidgets('TC-A01 an admin lands on the overview and jumps to the makers queue', (tester) async {
      await pumpApp(tester, auth: FakeAuthRepository(signedInAsAdmin: true));
      expect(find.text('Hi, CraftHive'), findsOneWidget);
      expect(find.text('Makers waiting'), findsOneWidget);
      expect(find.text('Open disputes'), findsOneWidget);
      await tester.tap(find.text('Makers waiting'));
      await tester.pumpAndSettle();
      expect(find.text('LayerLab PH'), findsOneWidget);
    });

    testWidgets('TC-A02 overdue ID photos are flagged', (tester) async {
      await pumpApp(tester, auth: FakeAuthRepository(signedInAsAdmin: true), admin: FakeAdminRepository(dashboard: const AdminDashboard(myRole: 'superadmin', idsOverdue: 2)));
      expect(find.textContaining('2 ID photos are past the 30-day deletion date'), findsOneWidget);
    });
  });

  group('Staff accounts', () {
    testWidgets('TC-A03 a superadmin adds a moderator', (tester) async {
      final repo = FakeAdminRepository();
      await pumpApp(tester, auth: FakeAuthRepository(signedInAsAdmin: true), admin: repo);
      await tapText(tester, 'Staff');
      await tapText(tester, 'Add staff member');
      await tester.enterText(find.widgetWithText(TextField, 'First name'), 'Marco');
      await tester.enterText(find.widgetWithText(TextField, 'Last name'), 'Lim');
      await tester.enterText(find.widgetWithText(TextField, 'Work email'), 'marco@crafthive.test');
      await tapText(tester, 'Send invite');

      expect(repo.invited, ['marco@crafthive.test']);
      expect(repo.staff.last.role, 'moderator');
      expect(find.text('Marco Lim'), findsOneWidget);
    });

    testWidgets('TC-A04 marketplace emails cannot become staff', (tester) async {
      final repo = FakeAdminRepository();
      await pumpApp(tester, auth: FakeAuthRepository(signedInAsAdmin: true), admin: repo);
      await tapText(tester, 'Staff');
      await tapText(tester, 'Add staff member');
      await tester.enterText(find.widgetWithText(TextField, 'First name'), 'Ana');
      await tester.enterText(find.widgetWithText(TextField, 'Last name'), 'Reyes');
      await tester.enterText(find.widgetWithText(TextField, 'Work email'), FakeAuthRepository.demoUser.email);
      await tapText(tester, 'Send invite');
      expect(find.textContaining('Use a separate work email'), findsOneWidget);
      expect(repo.invited, isEmpty);
    });

    testWidgets('TC-A05 a superadmin deactivates a moderator; their name is kept', (tester) async {
      final repo = FakeAdminRepository();
      await pumpApp(tester, auth: FakeAuthRepository(signedInAsAdmin: true), admin: repo);
      await tapText(tester, 'Staff');
      await tester.tap(find.byTooltip('Manage Lea Santos'));
      await tester.pumpAndSettle();
      await tapText(tester, 'Deactivate');
      await tapText(tester, 'Deactivate'); // confirm
      expect(repo.staff.firstWhere((s) => s.email == 'lea@crafthive.test').isActive, isFalse);
      expect(find.text('Deactivated'), findsOneWidget);
    });

    testWidgets('TC-A06 moderators cannot manage staff', (tester) async {
      final repo = FakeAdminRepository(staff: const [
        StaffMember(adminId: 'a-1', firstName: 'CraftHive', lastName: 'Admin', email: 'admin@crafthive.test', role: 'moderator', isMe: true),
        StaffMember(adminId: 'a-2', firstName: 'Lea', lastName: 'Santos', email: 'lea@crafthive.test', role: 'superadmin'),
      ]);
      final auth = FakeAuthRepository(signedInAsModerator: true);
      await pumpApp(tester, auth: auth, admin: repo);
      await tapText(tester, 'Staff');
      expect(find.text('Only superadmins can add or deactivate staff.'), findsOneWidget);
      expect(find.text('Add staff member'), findsNothing);
      expect(find.byType(PopupMenuButton<String>), findsNothing);
    });
  });
}

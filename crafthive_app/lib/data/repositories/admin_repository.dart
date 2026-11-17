import 'package:flutter/foundation.dart' show debugPrint;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models.dart';
import 'auth_repository.dart';

/// Admin dashboard numbers and staff accounts (database/13_admin_dashboard.sql,
/// supabase/functions/admin-accounts).
abstract class AdminRepository {
  Future<AdminDashboard> loadDashboard();
  Future<List<StaffMember>> loadStaff();

  /// Superadmin: creates a staff sign-in and emails a "choose your password" link.
  Future<void> invite({required String email, required String firstName, required String lastName, required String role});

  /// Superadmin: 'moderator' or 'superadmin'.
  Future<void> setRole(String adminId, String role);

  /// Superadmin: blocks or unblocks a staff member's sign-in (their past decisions stay).
  Future<void> setActive(String adminId, bool active);
}

Future<T> _run<T>(String what, Future<T> Function() call) => SupabaseAuthRepository.guard(() async {
      try {
        return await call();
      } on PostgrestException catch (e) {
        debugPrint('CraftHive: $what failed: ${e.code} ${e.message}');
        if (e.code == 'P0001') throw AppFailure(e.message);
        if (e.code == 'PGRST202' || e.code == '42883') {
          throw const AppFailure('The admin dashboard is not set up on the server yet. Run database/13_admin_dashboard.sql in Supabase.');
        }
        rethrow;
      } on FunctionException catch (e) {
        final details = e.details;
        final message = details is Map ? details['error'] as String? : null;
        debugPrint('CraftHive: $what failed: ${e.status} $details');
        if (e.status == 404 && message == null) {
          throw const AppFailure('Staff accounts are not set up on the server yet. Deploy the admin-accounts function.');
        }
        throw AppFailure(message ?? 'Could not update staff accounts. Try again.');
      }
    });

class SupabaseAdminRepository implements AdminRepository {
  SupabaseAdminRepository(this._db);
  final SupabaseClient _db;

  @override
  Future<AdminDashboard> loadDashboard() => _run('load dashboard', () async {
        final row = await _db.rpc<dynamic>('admin_dashboard');
        return dashboardFromJson(Map<String, dynamic>.from(row as Map));
      });

  @override
  Future<List<StaffMember>> loadStaff() => _run('load staff', () async {
        final rows = await _db.rpc<dynamic>('admin_accounts');
        return [for (final r in (rows as List? ?? const [])) staffFromJson(Map<String, dynamic>.from(r as Map))];
      });

  @override
  Future<void> invite({required String email, required String firstName, required String lastName, required String role}) =>
      _run('invite staff', () => _db.functions.invoke('admin-accounts', body: {'action': 'invite', 'email': email, 'firstName': firstName, 'lastName': lastName, 'role': role}));

  @override
  Future<void> setRole(String adminId, String role) => _run('change role', () => _db.rpc<dynamic>('set_admin_role', params: {'p_admin_id': adminId, 'p_role': role}));

  @override
  Future<void> setActive(String adminId, bool active) =>
      _run('update staff', () => _db.functions.invoke('admin-accounts', body: {'action': active ? 'reactivate' : 'deactivate', 'adminId': adminId}));
}

// ---------------------------------------------------------------------------
// JSON → model (plain functions so they can be unit-tested)
// ---------------------------------------------------------------------------
int _int(Object? v) => (v as num?)?.toInt() ?? 0;
DateTime? _date(Object? v) => v == null ? null : DateTime.tryParse(v as String)?.toLocal();

AdminDashboard dashboardFromJson(Map<String, dynamic> j) => AdminDashboard(
      myRole: (j['my_role'] as String?) ?? 'moderator',
      makersWaiting: _int(j['makers_waiting']),
      oldestWaitingAt: _date(j['oldest_waiting_at']),
      makersVerified: _int(j['makers_verified']),
      approved7d: _int(j['approved_7d']),
      rejected7d: _int(j['rejected_7d']),
      idsOnFile: _int(j['ids_on_file']),
      idsDue7d: _int(j['ids_due_7d']),
      idsOverdue: _int(j['ids_overdue']),
      idsDeleted30d: _int(j['ids_deleted_30d']),
      disputesOpen: _int(j['disputes_open']),
      disputesUnderReview: _int(j['disputes_under_review']),
      oldestOpenDisputeAt: _date(j['oldest_open_dispute_at']),
      disputesDecided7d: _int(j['disputes_decided_7d']),
      myDecisions7d: _int(j['my_decisions_7d']),
      stores: _int(j['stores']),
      staff: _int(j['staff']),
    );

StaffMember staffFromJson(Map<String, dynamic> j) => StaffMember(
      adminId: j['admin_id'] as String,
      firstName: (j['first_name'] as String?) ?? '',
      lastName: (j['last_name'] as String?) ?? '',
      email: (j['email'] as String?) ?? '',
      role: (j['role'] as String?) ?? 'moderator',
      isActive: j['is_active'] != false,
      isMe: j['is_me'] == true,
      createdAt: _date(j['created_at']),
      lastSignInAt: _date(j['last_sign_in_at']),
      decisions: _int(j['decisions']),
    );

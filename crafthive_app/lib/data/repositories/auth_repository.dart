import 'dart:async';
import 'dart:io' show SocketException;
import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../models.dart';
import 'listing_repository.dart' show photoType;

/// A problem the user can fix, with a message that is safe to show on screen.
class AppFailure implements Exception {
  const AppFailure(this.message, {this.field});
  final String message;

  /// The form field the message belongs to, when it is about one field.
  final AuthField? field;

  @override
  String toString() => message;
}

enum AuthField { username, email, password }

/// The link in the password-reset email opens the app here (allowed in
/// Supabase → Authentication → URL Configuration, and declared in AndroidManifest.xml).
const resetPasswordRedirect = 'ph.crafthive.app://reset-password';

enum SignUpOutcome { signedIn, confirmEmail }

class SignUpData {
  const SignUpData({
    required this.fullName,
    required this.email,
    required this.phone,
    required this.country,
    required this.sex,
    required this.username,
    required this.password,
  });
  final String fullName;
  final String email;

  /// Digits only, with the country code (users.phone_number).
  final String phone;
  final String country;
  final String sex;
  final String username;
  final String password;
}

/// Changes from Edit profile. Store fields are saved only when the user has a store.
class ProfileUpdate {
  const ProfileUpdate({required this.fullName, required this.phoneDigits, this.storeDescription, this.city});
  final String fullName;

  /// Digits with the country code (users.phone_number), e.g. 639171234567.
  final String phoneDigits;
  final String? storeDescription;
  final String? city;
}

/// Sign-in, sign-up and password reset. Supabase Auth keeps the session on the
/// phone, so the user stays logged in after closing the app.
abstract class AuthRepository {
  String? get currentUserId;

  /// The signed-in user's ID now and after every change (null when signed out).
  Stream<String?> get userIdChanges;

  Future<AppUser> loadProfile(String userId);
  Future<void> logIn(String usernameOrEmail, String password);
  Future<SignUpOutcome> signUp(SignUpData data);

  /// Emails a reset link. Opening it on the phone signs the user in for a
  /// password reset and fires [passwordRecoveryEvents].
  Future<void> sendPasswordResetLink(String email);
  Stream<void> get passwordRecoveryEvents;
  Future<void> updatePassword(String newPassword);
  Future<void> signOut();

  /// Saves name and phone (USERS), and store description and city (STORE) when given.
  Future<void> updateProfile(ProfileUpdate update);

  /// Uploads a new profile photo to the avatars bucket and returns its public link.
  Future<String> uploadAvatar(Uint8List bytes, String fileName);

  /// Starts an email change: a confirmation link is sent to the new address,
  /// and the email changes after it is opened.
  Future<void> changeEmail(String newEmail);
}

const wrongLoginMessage = 'Wrong username or password. Please try again.';
const offlineMessage = 'No internet connection. Check your Wi-Fi or mobile data and try again.';
const serverMessage = 'Something went wrong on our side. Please try again in a moment.';

class SupabaseAuthRepository implements AuthRepository {
  SupabaseAuthRepository(this._db);
  final SupabaseClient _db;

  static const _timeout = Duration(seconds: 20);

  @override
  String? get currentUserId => _db.auth.currentUser?.id;

  @override
  Stream<String?> get userIdChanges => _db.auth.onAuthStateChange.map((s) => s.session?.user.id).distinct();

  @override
  Future<AppUser> loadProfile(String userId) => guard(() async {
        final row = await _db
            .from('users')
            .select('user_id, full_name, email, username, phone_number, sex, country, avatar_path')
            .eq('user_id', userId)
            .maybeSingle();
        if (row == null) {
          // CraftHive staff live in the ADMIN table, outside the USER hierarchy.
          // select() so this also works before 13_admin_dashboard.sql adds is_active.
          final admin = await _db.from('admin').select().eq('auth_uid', userId).maybeSingle();
          if (admin != null) {
            if (admin['is_active'] == false) throw const AppFailure('This staff account was deactivated. Ask a CraftHive superadmin.');
            return adminUserFromRow(userId, admin);
          }
          throw const AppFailure('We could not find your profile. Please log out and sign up again.');
        }
        final store = await _db.from('store_card').select('city, store_description, verification_status').eq('seller_id', userId).maybeSingle();
        return AppUser(
          id: row['user_id'] as String,
          username: row['username'] as String,
          email: row['email'] as String,
          phone: formatPhone(row['phone_number'] as String),
          country: row['country'] as String,
          sex: (row['sex'] as String?) ?? 'Prefer not to say',
          displayName: row['full_name'] as String,
          bio: (store?['store_description'] as String?) ?? '',
          location: (store?['city'] as String?) ?? (row['country'] as String),
          isVerified: store?['verification_status'] == 'verified',
          avatarUrl: _avatarUrl(row['avatar_path'] as String?),
          hasStore: store != null,
          phoneDigits: row['phone_number'] as String,
        );
      });

  String? _avatarUrl(String? path) => path == null || path.isEmpty ? null : _db.storage.from('avatars').getPublicUrl(path);

  String get _uid {
    final id = _db.auth.currentUser?.id;
    if (id == null) throw const AppFailure('Please log in again.');
    return id;
  }

  @override
  Future<void> updateProfile(ProfileUpdate u) => guard(() async {
        final uid = _uid;
        await _db.from('users').update({'full_name': u.fullName.trim(), 'phone_number': u.phoneDigits}).eq('user_id', uid);
        if (u.storeDescription != null || u.city != null) {
          await _db.from('store').update({
            if (u.storeDescription != null) 'store_description': u.storeDescription!.trim().isEmpty ? null : u.storeDescription!.trim(),
            if (u.city != null) 'city': u.city!.trim(),
          }).eq('seller_id', uid);
        }
      });

  @override
  Future<String> uploadAvatar(Uint8List bytes, String fileName) => guard(() async {
        final uid = _uid;
        final type = photoType(fileName);
        // A new name each time, so phones do not keep showing the old photo from their cache.
        final path = '$uid/avatar_${DateTime.now().millisecondsSinceEpoch}.${type.ext}';
        final old = await _db.from('users').select('avatar_path').eq('user_id', uid).maybeSingle();
        await _db.storage.from('avatars').uploadBinary(path, bytes, fileOptions: FileOptions(contentType: type.mime));
        await _db.from('users').update({'avatar_path': path}).eq('user_id', uid);
        final oldPath = old?['avatar_path'] as String?;
        if (oldPath != null && oldPath.isNotEmpty && oldPath != path) {
          try {
            await _db.storage.from('avatars').remove([oldPath]);
          } catch (_) {
            // Removing the old file is only tidying up.
          }
        }
        return _db.storage.from('avatars').getPublicUrl(path);
      });

  @override
  Future<void> changeEmail(String newEmail) => guard(() async {
        final email = newEmail.trim().toLowerCase();
        final free = await _db.rpc<bool>('is_email_available', params: {'p_email': email});
        if (!free) throw const AppFailure('An account with this email already exists.', field: AuthField.email);
        await _db.auth.updateUser(UserAttributes(email: email));
      });

  @override
  Future<void> logIn(String usernameOrEmail, String password) => guard(() async {
        var email = usernameOrEmail.trim().toLowerCase();
        if (!email.contains('@')) {
          // Username: look up the linked email first, then sign in with it.
          final found = await _db.rpc<String?>('email_for_username', params: {'p_username': email});
          if (found == null) throw const AppFailure(wrongLoginMessage);
          email = found;
        }
        await _db.auth.signInWithPassword(email: email, password: password);
      });

  @override
  Future<SignUpOutcome> signUp(SignUpData d) => guard(() async {
        final username = d.username.trim().toLowerCase();
        final email = d.email.trim().toLowerCase();
        final usernameFree = await _db.rpc<bool>('is_username_available', params: {'p_username': username});
        if (!usernameFree) {
          throw const AppFailure('That username is already taken. Try another one.', field: AuthField.username);
        }
        final emailFree = await _db.rpc<bool>('is_email_available', params: {'p_email': email});
        if (!emailFree) {
          throw const AppFailure('An account with this email already exists. Log in instead.', field: AuthField.email);
        }
        final res = await _db.auth.signUp(email: email, password: d.password, data: {
          'full_name': d.fullName.trim(),
          'username': username,
          'phone_number': d.phone,
          'sex': d.sex,
          'country': d.country,
        });
        return res.session != null ? SignUpOutcome.signedIn : SignUpOutcome.confirmEmail;
      });

  @override
  Future<void> sendPasswordResetLink(String email) =>
      guard(() => _db.auth.resetPasswordForEmail(email.trim().toLowerCase(), redirectTo: resetPasswordRedirect));

  @override
  Stream<void> get passwordRecoveryEvents =>
      _db.auth.onAuthStateChange.where((s) => s.event == AuthChangeEvent.passwordRecovery).map((_) {});

  @override
  Future<void> updatePassword(String newPassword) => guard(() => _db.auth.updateUser(UserAttributes(password: newPassword)));

  @override
  Future<void> signOut() => guard(() => _db.auth.signOut());

  /// Runs a Supabase call with a time limit and turns its errors into plain messages.
  static Future<T> guard<T>(Future<T> Function() call) async {
    try {
      return await call().timeout(_timeout);
    } on AppFailure {
      rethrow;
    } on TimeoutException {
      throw const AppFailure('The server took too long to answer. Check your connection and try again.');
    } on AuthException catch (e) {
      throw AppFailure(_authMessage(e));
    } on PostgrestException catch (e) {
      if (_looksOffline(e.message)) throw const AppFailure(offlineMessage);
      throw const AppFailure(serverMessage);
    } on StorageException catch (e) {
      if (_looksOffline(e.message)) throw const AppFailure(offlineMessage);
      if (e.statusCode == '413' || e.message.toLowerCase().contains('size')) {
        throw const AppFailure('That photo is too large. Choose one under 2 MB.');
      }
      throw const AppFailure('The photo could not be uploaded. Please try again.');
    } on SocketException {
      throw const AppFailure(offlineMessage);
    } catch (e) {
      if (_looksOffline(e.toString())) throw const AppFailure(offlineMessage);
      throw const AppFailure(serverMessage);
    }
  }

  static bool _looksOffline(String text) => RegExp(
        r'SocketException|Failed host lookup|Connection (refused|reset|closed|failed)|Network is unreachable|ClientException|HandshakeException',
        caseSensitive: false,
      ).hasMatch(text);

  static bool _isNetwork(AuthException e) => e is AuthRetryableFetchException || _looksOffline(e.message);

  static String _authMessage(AuthException e) {
    if (_isNetwork(e)) return offlineMessage;
    final code = e.code ?? '';
    final msg = e.message.toLowerCase();
    if (code == 'invalid_credentials' || msg.contains('invalid login credentials')) return wrongLoginMessage;
    if (code == 'email_not_confirmed' || msg.contains('email not confirmed')) {
      return 'Please confirm your email first. Open the link we sent to your inbox, then log in.';
    }
    if (code == 'user_already_exists' || msg.contains('already registered')) return 'An account with this email already exists. Log in instead.';
    if (code == 'weak_password' || msg.contains('password should')) return 'Choose a stronger password: at least 8 characters with letters and numbers.';
    if (code == 'same_password' || msg.contains('different from the old password')) return 'Your new password must be different from your old one.';
    if (code.startsWith('over_') || e.statusCode == '429' || msg.contains('rate limit')) {
      return 'Too many attempts. Please wait a minute and try again.';
    }
    if (code == 'email_address_invalid' || (msg.contains('email address') && msg.contains('invalid'))) return 'Enter a valid email address.';
    if (code == 'otp_expired' || msg.contains('expired')) return 'That reset link has expired. Ask for a new one.';
    if (msg.contains('database error saving new user')) return 'That username or email was just taken. Try another one.';
    if (code == 'signup_disabled') return 'Sign-ups are closed right now. Please try again later.';
    if (code == 'email_exists' || msg.contains('already been registered')) return 'An account with this email already exists.';
    return serverMessage;
  }
}

/// 639171234567 → +63 917 123 4567
String formatPhone(String digits) {
  if (digits.length == 12 && digits.startsWith('63')) {
    return '+63 ${digits.substring(2, 5)} ${digits.substring(5, 8)} ${digits.substring(8)}';
  }
  return digits.isEmpty ? '' : '+$digits';
}

/// An ADMIN row as a signed-in user (they only see the review screens).
AppUser adminUserFromRow(String userId, Map<String, dynamic> r) {
  final email = r['email'] as String;
  return AppUser(
    id: userId,
    username: email.split('@').first,
    email: email,
    phone: '',
    country: 'Philippines',
    sex: 'Prefer not to say',
    displayName: '${r['first_name']} ${r['last_name']}'.trim(),
    isAdmin: true,
    adminRole: (r['role'] as String?) ?? 'moderator',
  );
}

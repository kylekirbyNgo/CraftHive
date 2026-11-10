import 'dart:async';
import 'dart:io' show SocketException;

import 'package:supabase_flutter/supabase_flutter.dart';

import '../models.dart';

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
            .select('user_id, full_name, email, username, phone_number, sex, country')
            .eq('user_id', userId)
            .maybeSingle();
        if (row == null) {
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
        );
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

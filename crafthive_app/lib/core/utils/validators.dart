/// Input checks shared by Log in, Sign up and Forgot password.
/// Each returns an error message to show under the field, or null when the value is fine.
/// The same rules are enforced again in the database (CHECK constraints in 01_schema.sql).
abstract final class Validators {
  static final _email = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');
  static final _username = RegExp(r'^[a-z0-9._]{4,20}$');
  static final _name = RegExp(r"^[A-Za-zÀ-ÖØ-öø-ÿÑñ .'-]+$");

  static String? loginId(String? v) => (v == null || v.trim().isEmpty) ? 'Enter your username or email.' : null;

  static String? loginPassword(String? v) => (v == null || v.isEmpty) ? 'Enter your password.' : null;

  static String? email(String? v) {
    final t = v?.trim() ?? '';
    if (t.isEmpty) return 'Enter your email address.';
    if (t.length > 100) return 'Email must be 100 characters or fewer.';
    return _email.hasMatch(t) ? null : 'Enter a valid email address, like you@email.com.';
  }

  static String? fullName(String? v) {
    final t = v?.trim() ?? '';
    if (t.isEmpty) return 'Enter your full name.';
    if (t.length < 2) return 'Name is too short.';
    if (t.length > 100) return 'Name must be 100 characters or fewer.';
    return _name.hasMatch(t) ? null : 'Use letters, spaces, dots, hyphens or apostrophes only.';
  }

  /// Local mobile number without the country code: 10 digits for the Philippines,
  /// 7 to 12 digits for other countries.
  static String? phone(String? v, {required String country}) {
    final digits = (v ?? '').replaceAll(RegExp(r'\D'), '');
    if (digits.isEmpty) return 'Enter your mobile number.';
    if (country == 'Philippines') {
      if (digits.length != 10) return 'Enter the 10-digit mobile number, like 917 123 4567.';
      if (!digits.startsWith('9')) return 'Philippine mobile numbers start with 9.';
      return null;
    }
    return digits.length >= 7 && digits.length <= 12 ? null : 'Enter a valid mobile number (7 to 12 digits).';
  }

  static String? username(String? v) {
    final t = v?.trim() ?? '';
    if (t.isEmpty) return 'Choose a username.';
    if (t != t.toLowerCase()) return 'Use lowercase letters only.';
    if (t.length < 4 || t.length > 20) return 'Use 4 to 20 characters.';
    if (!_username.hasMatch(t)) return 'Use letters, numbers, dots or underscores only.';
    if (t.startsWith('.') || t.endsWith('.')) return 'A username cannot start or end with a dot.';
    return null;
  }

  static String? newPassword(String? v) {
    final t = v ?? '';
    if (t.isEmpty) return 'Create a password.';
    if (t.length < 8) return 'Use at least 8 characters.';
    if (t.length > 72) return 'Use 72 characters or fewer.';
    if (!RegExp(r'[A-Za-z]').hasMatch(t) || !RegExp(r'\d').hasMatch(t)) return 'Include at least one letter and one number.';
    return null;
  }

  /// Digits only, with the country code, as stored in users.phone_number (e.g. 639171234567).
  static String storedPhone(String dialCode, String local) =>
      dialCode.replaceAll(RegExp(r'\D'), '') + local.replaceAll(RegExp(r'\D'), '');
}

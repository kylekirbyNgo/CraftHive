/// Small formatting helpers (kept local to avoid an extra package).
abstract final class Fmt {
  static const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

  /// ₱1,050 or ₱1,050.50
  static String peso(num value) {
    final whole = value.truncate();
    final cents = ((value - whole) * 100).round();
    final digits = whole.abs().toString();
    final buf = StringBuffer();
    for (var i = 0; i < digits.length; i++) {
      if (i > 0 && (digits.length - i) % 3 == 0) buf.write(',');
      buf.write(digits[i]);
    }
    return '₱${value < 0 ? '-' : ''}$buf${cents > 0 ? '.${cents.toString().padLeft(2, '0')}' : ''}';
  }

  /// Dec 18, 2026
  static String date(DateTime d) => '${_months[d.month - 1]} ${d.day}, ${d.year}';

  /// Dec 18
  static String shortDate(DateTime d) => '${_months[d.month - 1]} ${d.day}';

  /// 2:05 PM
  static String time(DateTime d) {
    final h = d.hour % 12 == 0 ? 12 : d.hour % 12;
    return '$h:${d.minute.toString().padLeft(2, '0')} ${d.hour < 12 ? 'AM' : 'PM'}';
  }

  static String timeNow() => time(DateTime.now());

  /// Nov 3, 2:05 PM
  static String stamp(DateTime d) => '${shortDate(d)}, ${time(d)}';

  static String count(int n, String one, [String? many]) => '$n ${n == 1 ? one : (many ?? '${one}s')}';
}

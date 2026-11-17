/// Typo-tolerant word matching for Search (kept local to avoid an extra package).
///
/// Each query word is compared with the words of a listing. A word counts as a
/// match when it is the same, a prefix ("bouq" → "bouquet"), contained in a
/// longer word ("carved" → "handcarved"), or only a few typos away
/// ("boquet", "candel", "keychian"). Short words must match exactly so "mug"
/// does not also find "bag".
abstract final class Fuzzy {
  static const _fold = {
    'á': 'a', 'à': 'a', 'â': 'a', 'ä': 'a', 'ã': 'a', 'é': 'e', 'è': 'e', 'ê': 'e', 'ë': 'e',
    'í': 'i', 'ì': 'i', 'î': 'i', 'ï': 'i', 'ó': 'o', 'ò': 'o', 'ô': 'o', 'ö': 'o', 'õ': 'o',
    'ú': 'u', 'ù': 'u', 'û': 'u', 'ü': 'u', 'ñ': 'n', 'ç': 'c',
  };
  static final _nonWord = RegExp(r'[^a-z0-9]+');

  /// Words skipped in a multi-word query ("bouquet for mom" → bouquet, mom).
  static const stopWords = {'a', 'an', 'the', 'of', 'for', 'and', 'with', 'in', 'to', 'by', 'ng', 'sa', 'na', 'at'};

  /// Lower case, accents removed (Niño → nino), punctuation turned into spaces.
  static String normalize(String s) {
    final lower = s.toLowerCase();
    final buf = StringBuffer();
    for (final ch in lower.split('')) {
      buf.write(_fold[ch] ?? ch);
    }
    return buf.toString().replaceAll(_nonWord, ' ').trim();
  }

  static List<String> words(String s) {
    final n = normalize(s);
    return n.isEmpty ? const [] : n.split(' ');
  }

  /// Query words worth matching: stop words are dropped unless they are all there is.
  static List<String> queryWords(String q) {
    final all = words(q);
    final kept = all.where((w) => !stopWords.contains(w)).toList();
    return kept.isEmpty ? all : kept;
  }

  /// How many typos a query word of [length] letters may have.
  static int allowedTypos(int length) => length <= 3 ? 0 : (length <= 6 ? 1 : 2);

  /// Edit distance where swapping two neighbouring letters counts as one typo
  /// (optimal string alignment). Returns [max] + 1 as soon as it is clear the
  /// distance is larger than [max].
  static int distance(String a, String b, {int max = 1 << 20}) {
    if (a == b) return 0;
    if ((a.length - b.length).abs() > max) return max + 1;
    if (a.isEmpty) return b.length;
    if (b.isEmpty) return a.length;
    var prev2 = List<int>.filled(b.length + 1, 0);
    var prev = List<int>.generate(b.length + 1, (j) => j);
    var cur = List<int>.filled(b.length + 1, 0);
    for (var i = 1; i <= a.length; i++) {
      cur[0] = i;
      var rowMin = cur[0];
      for (var j = 1; j <= b.length; j++) {
        final cost = a.codeUnitAt(i - 1) == b.codeUnitAt(j - 1) ? 0 : 1;
        var v = prev[j] + 1;
        if (cur[j - 1] + 1 < v) v = cur[j - 1] + 1;
        if (prev[j - 1] + cost < v) v = prev[j - 1] + cost;
        if (i > 1 && j > 1 && a.codeUnitAt(i - 1) == b.codeUnitAt(j - 2) && a.codeUnitAt(i - 2) == b.codeUnitAt(j - 1) && prev2[j - 2] + 1 < v) {
          v = prev2[j - 2] + 1;
        }
        cur[j] = v;
        if (v < rowMin) rowMin = v;
      }
      if (rowMin > max) return max + 1;
      final t = prev2;
      prev2 = prev;
      prev = cur;
      cur = t;
    }
    return prev[b.length];
  }

  /// 0 (no match) to 1 (same word). [q] and [w] must already be normalized.
  static double wordScore(String q, String w) {
    if (q.isEmpty || w.isEmpty) return 0;
    if (q == w) return 1;
    if (q.length >= 2 && w.startsWith(q)) return 0.9;
    if (q.length >= 4 && w.contains(q)) return 0.7;
    final typos = allowedTypos(q.length);
    if (typos == 0) return 0;
    final d = distance(q, w, max: typos);
    if (d <= typos) return 0.85 - 0.15 * d;
    // Still typing a long word with a typo in it: "bouqe" → "bouquet".
    if (q.length >= 5 && w.length > q.length) {
      final dp = distance(q, w.substring(0, q.length), max: typos);
      if (dp <= typos) return 0.65 - 0.15 * dp;
    }
    return 0;
  }

  /// Best score of [q] against any of [words].
  static double bestScore(String q, Iterable<String> words) {
    var best = 0.0;
    for (final w in words) {
      final s = wordScore(q, w);
      if (s > best) {
        best = s;
        if (best == 1) break;
      }
    }
    return best;
  }
}

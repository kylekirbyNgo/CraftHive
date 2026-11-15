import 'package:cloud_firestore/cloud_firestore.dart';

import 'chat_repository.dart' show firebaseGuard;

/// Recent searches in Firestore, as in the Milestone II NoSQL model:
///   users/{uid}/recentSearches/{id}   term, filters, createdAt
/// The document ID is the search term in lower case, so searching the same
/// thing again moves it to the top instead of adding it twice.
abstract class RecentSearchRepository {
  /// Newest first, at most [recentSearchLimit].
  Stream<List<String>> watch(String me);
  Future<void> add(String me, String term, {Map<String, Object?>? filters});
  Future<void> remove(String me, String term);
  Future<void> clear(String me);
}

const recentSearchLimit = 10;

/// Firestore document ID for a search term (no slashes, at most 100 characters).
String recentSearchId(String term) {
  final id = term.trim().toLowerCase().replaceAll(RegExp(r'[/\\]'), ' ').replaceAll(RegExp(r'\s+'), ' ');
  final safe = id == '.' || id == '..' || id.startsWith('__') ? '_$id' : id;
  return safe.length > 100 ? safe.substring(0, 100) : safe;
}

class FirestoreRecentSearchRepository implements RecentSearchRepository {
  FirestoreRecentSearchRepository(this._fs);
  final FirebaseFirestore _fs;

  CollectionReference<Map<String, dynamic>> _col(String me) => _fs.collection('users').doc(me).collection('recentSearches');

  @override
  Stream<List<String>> watch(String me) => _col(me)
      .orderBy('createdAt', descending: true)
      .limit(recentSearchLimit)
      .snapshots()
      .map((q) => [for (final d in q.docs) (d.data()['term'] as String?) ?? d.id]);

  @override
  Future<void> add(String me, String term, {Map<String, Object?>? filters}) => firebaseGuard(() async {
        final t = term.trim();
        if (t.isEmpty) return;
        await _col(me).doc(recentSearchId(t)).set({
          'term': t,
          'filters': filters ?? <String, Object?>{},
          'createdAt': FieldValue.serverTimestamp(),
        });
        // Keep only the newest ones.
        final all = await _col(me).orderBy('createdAt', descending: true).get();
        if (all.docs.length > recentSearchLimit) {
          final batch = _fs.batch();
          for (final d in all.docs.skip(recentSearchLimit)) {
            batch.delete(d.reference);
          }
          await batch.commit();
        }
      });

  @override
  Future<void> remove(String me, String term) => firebaseGuard(() => _col(me).doc(recentSearchId(term)).delete());

  @override
  Future<void> clear(String me) => firebaseGuard(() async {
        final all = await _col(me).get();
        final batch = _fs.batch();
        for (final d in all.docs) {
          batch.delete(d.reference);
        }
        await batch.commit();
      });
}

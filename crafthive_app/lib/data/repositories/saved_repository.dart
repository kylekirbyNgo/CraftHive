import 'package:cloud_firestore/cloud_firestore.dart';

import 'chat_repository.dart' show firebaseGuard;

/// Saved items (Favorites) in Firestore, as in the Milestone II NoSQL model:
///   users/{uid}/savedItems/{productId}   savedAt
///   productStats/{productId}             saveCount (how many people saved it)
/// The security rules let the count go up by one only when the item is saved
/// in the same write, and down by one only when it is removed.
abstract class SavedRepository {
  /// IDs of the products I saved.
  Stream<Set<String>> watchSaved(String me);

  Future<void> setSaved(String me, String productId, bool saved);

  /// How many people saved this product.
  Stream<int> watchSaveCount(String productId);
}

class FirestoreSavedRepository implements SavedRepository {
  FirestoreSavedRepository(this._fs);
  final FirebaseFirestore _fs;

  CollectionReference<Map<String, dynamic>> _items(String me) => _fs.collection('users').doc(me).collection('savedItems');
  DocumentReference<Map<String, dynamic>> _stats(String productId) => _fs.collection('productStats').doc(productId);

  @override
  Stream<Set<String>> watchSaved(String me) => _items(me).snapshots().map((q) => {for (final d in q.docs) d.id});

  @override
  Future<void> setSaved(String me, String productId, bool saved) => firebaseGuard(() async {
        final item = _items(me).doc(productId);
        final batch = _fs.batch();
        if (saved) {
          batch.set(item, {'savedAt': FieldValue.serverTimestamp()});
        } else {
          batch.delete(item);
        }
        batch.set(_stats(productId), {'saveCount': FieldValue.increment(saved ? 1 : -1)}, SetOptions(merge: true));
        try {
          await batch.commit();
        } on FirebaseException catch (e) {
          if (e.code != 'permission-denied') rethrow;
          // The count did not match (already saved, or saved before counts existed):
          // keep the user's list right and leave the count as it is.
          saved ? await item.set({'savedAt': FieldValue.serverTimestamp()}) : await item.delete();
        }
      });

  @override
  Stream<int> watchSaveCount(String productId) => _stats(productId).snapshots().map((d) {
        final n = d.data()?['saveCount'];
        return n is num && n > 0 ? n.toInt() : 0;
      });
}

import 'dart:async';

import 'package:firebase_database/firebase_database.dart';

/// Online status and typing in the Firebase Realtime Database (Milestone II):
///   /status/{uid}            online, lastSeen
///   /typing/{chatId}/{uid}   isTyping
/// The Realtime Database notices when a phone loses its connection and runs
/// the onDisconnect() writes, so people show as offline even if the app crashes.
abstract class PresenceRepository {
  /// Marks me online now, and offline when the connection drops.
  Future<void> goOnline(String me);
  Future<void> goOffline(String me);
  Stream<bool> watchOnline(String uid);
  Future<void> setTyping(String chatId, String me, bool typing);
  Stream<bool> watchTyping(String chatId, String uid);
}

class RealtimePresenceRepository implements PresenceRepository {
  RealtimePresenceRepository(this._db);
  final FirebaseDatabase _db;
  StreamSubscription<DatabaseEvent>? _connected;

  @override
  Future<void> goOnline(String me) async {
    await _connected?.cancel();
    final status = _db.ref('status/$me');
    // .info/connected turns true every time the phone (re)connects.
    _connected = _db.ref('.info/connected').onValue.listen((event) async {
      if (event.snapshot.value != true) return;
      try {
        await status.onDisconnect().set({'online': false, 'lastSeen': ServerValue.timestamp});
        await status.set({'online': true, 'lastSeen': ServerValue.timestamp});
      } catch (_) {
        // Signed out meanwhile; the next sign-in tries again.
      }
    });
  }

  @override
  Future<void> goOffline(String me) async {
    await _connected?.cancel();
    _connected = null;
    try {
      await _db.ref('status/$me').set({'online': false, 'lastSeen': ServerValue.timestamp});
    } catch (_) {}
  }

  @override
  Stream<bool> watchOnline(String uid) =>
      uid.isEmpty ? Stream.value(false) : _db.ref('status/$uid/online').onValue.map((e) => e.snapshot.value == true);

  @override
  Future<void> setTyping(String chatId, String me, bool typing) async {
    final ref = _db.ref('typing/$chatId/$me');
    try {
      if (typing) {
        await ref.onDisconnect().remove();
        await ref.set({'isTyping': true, 'at': ServerValue.timestamp});
      } else {
        await ref.remove();
      }
    } catch (_) {
      // Typing dots are only a nicety; never show an error for them.
    }
  }

  @override
  Stream<bool> watchTyping(String chatId, String uid) =>
      uid.isEmpty ? Stream.value(false) : _db.ref('typing/$chatId/$uid/isTyping').onValue.map((e) => e.snapshot.value == true);
}

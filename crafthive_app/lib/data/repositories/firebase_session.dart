import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show SupabaseClient;

/// Signs in to Firebase as the same person who is signed in to Supabase.
///
/// Login stays with Supabase Auth. The firebase-bridge Edge Function checks the
/// user's Supabase session and returns a Firebase custom token whose uid is the
/// Supabase user ID, so Firestore and Realtime Database rules can use
/// request.auth.uid / auth.uid to protect each user's chats and notifications.
abstract class FirebaseSession {
  /// Returns the Firebase uid (equal to [userId]), or throws.
  Future<String> connect(String userId);
  Future<void> disconnect();
}

class FirebaseAuthSession implements FirebaseSession {
  FirebaseAuthSession(this._auth, this._db);
  final FirebaseAuth _auth;
  final SupabaseClient _db;

  @override
  Future<String> connect(String userId) async {
    if (_auth.currentUser?.uid == userId) return userId;
    final res = await _db.functions.invoke('firebase-bridge', body: {'action': 'token'});
    final token = (res.data as Map)['token'] as String;
    final cred = await _auth.signInWithCustomToken(token);
    return cred.user!.uid;
  }

  @override
  Future<void> disconnect() => _auth.signOut();
}

/// A push notification that arrived while the app was open.
class PushBanner {
  const PushBanner({required this.title, required this.body, required this.route, required this.type});
  final String title;
  final String body;
  final String route;

  /// message, quote, payment, request, shipping, review or order
  final String type;
}

/// Push notifications (Firebase Cloud Messaging). This phone's token is saved in
/// Firestore users/{uid}.fcmTokens; the Edge Function sends to those tokens.
abstract class PushService {
  /// Asks for permission (Android 13+) and saves this phone's token.
  Future<void> register(String me);

  /// Removes this phone's token so a signed-out phone gets no pushes.
  Future<void> unregister(String me);

  /// The screen of the notification that started the app, if any.
  Future<String?> initialRoute();

  /// Screens of notifications tapped while the app was in the background.
  Stream<String> get openedRoutes;

  /// Notifications that arrived while the app was open (Android does not show them by itself).
  Stream<PushBanner> get foreground;
}

/// Only screens the app knows are opened from a notification.
String? safeRoute(Object? route) {
  if (route is! String) return null;
  final ok = RegExp(r'^/(chat|order|request)/[A-Za-z0-9_\-]+$').hasMatch(route) || route == '/notifications';
  return ok ? route : null;
}

class FcmPushService implements PushService {
  FcmPushService(this._messaging, this._fs);
  final FirebaseMessaging _messaging;
  final FirebaseFirestore _fs;
  StreamSubscription<String>? _refresh;

  DocumentReference<Map<String, dynamic>> _user(String me) => _fs.collection('users').doc(me);

  Future<void> _save(String me, String token) => _user(me).set({
        'fcmTokens': FieldValue.arrayUnion([token]),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

  @override
  Future<void> register(String me) async {
    try {
      await _messaging.requestPermission();
      final token = await _messaging.getToken();
      if (token != null) await _save(me, token);
      await _refresh?.cancel();
      _refresh = _messaging.onTokenRefresh.listen((t) => _save(me, t).catchError((Object e) => debugPrint('token save failed: $e')));
    } catch (e) {
      // For example an emulator without Google Play: chat still works, only pushes are missing.
      debugPrint('Push notifications are not available: $e');
    }
  }

  @override
  Future<void> unregister(String me) async {
    await _refresh?.cancel();
    _refresh = null;
    try {
      final token = await _messaging.getToken();
      if (token != null) {
        await _user(me).set({'fcmTokens': FieldValue.arrayRemove([token])}, SetOptions(merge: true));
      }
    } catch (e) {
      debugPrint('Could not remove the push token: $e');
    }
  }

  @override
  Future<String?> initialRoute() async {
    try {
      return safeRoute((await _messaging.getInitialMessage())?.data['route']);
    } catch (_) {
      return null;
    }
  }

  @override
  Stream<String> get openedRoutes =>
      FirebaseMessaging.onMessageOpenedApp.map((m) => safeRoute(m.data['route'])).where((r) => r != null).cast<String>();

  @override
  Stream<PushBanner> get foreground => FirebaseMessaging.onMessage.map((m) => PushBanner(
        title: m.notification?.title ?? 'CraftHive',
        body: m.notification?.body ?? '',
        route: safeRoute(m.data['route']) ?? '/notifications',
        type: (m.data['type'] as String?) ?? '',
      ));
}

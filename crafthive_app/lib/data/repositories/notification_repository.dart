import 'package:cloud_firestore/cloud_firestore.dart';

import '../../core/utils/format.dart';
import '../models.dart';
import 'chat_repository.dart' show firebaseGuard;

/// The in-app notification list in Firestore notifications/{uid}/items/{id}:
/// type, title, body, refType (order | request | chat), refId, read, createdAt, expireAt.
/// Items are added by the firebase-bridge Edge Function, which also sends the
/// push notification; the app only reads them and marks them read.
abstract class NotificationRepository {
  Stream<List<AppNotice>> watch(String me);
  Future<void> markRead(String me, String id);
  Future<void> markAllRead(String me, List<String> ids);
}

class FirestoreNotificationRepository implements NotificationRepository {
  FirestoreNotificationRepository(this._fs);
  final FirebaseFirestore _fs;

  CollectionReference<Map<String, dynamic>> _items(String me) => _fs.collection('notifications').doc(me).collection('items');

  @override
  Stream<List<AppNotice>> watch(String me) => _items(me)
      .orderBy('createdAt', descending: true)
      .limit(100)
      .snapshots()
      .map((q) => [for (final d in q.docs) noticeFromDoc(d.id, d.data())]);

  @override
  Future<void> markRead(String me, String id) => firebaseGuard(() => _items(me).doc(id).update({'read': true}));

  @override
  Future<void> markAllRead(String me, List<String> ids) => firebaseGuard(() async {
        if (ids.isEmpty) return;
        final batch = _fs.batch();
        for (final id in ids.take(450)) {
          batch.update(_items(me).doc(id), {'read': true});
        }
        await batch.commit();
      });
}

NoticeKind noticeKindFromName(String? type) => switch (type) {
      'quote' => NoticeKind.quote,
      'payment' => NoticeKind.payment,
      'request' => NoticeKind.request,
      'shipping' => NoticeKind.shipping,
      'review' => NoticeKind.review,
      _ => NoticeKind.order,
    };

/// Screen opened by a notification (also used for push notifications).
String routeForRef(String? refType, String? refId) {
  if (refId == null || refId.isEmpty) return '/notifications';
  return switch (refType) {
    'order' => '/order/$refId',
    'request' => '/request/$refId',
    'chat' => '/chat/$refId',
    _ => '/notifications',
  };
}

/// "Just now", "5m", "3h", "Yesterday", "Nov 3"
String noticeTime(DateTime? t, {DateTime? now}) {
  if (t == null) return 'Just now';
  final n = now ?? DateTime.now();
  final diff = n.difference(t);
  if (diff.inMinutes < 1) return 'Just now';
  if (diff.inMinutes < 60) return '${diff.inMinutes}m';
  if (diff.inHours < 24 && n.day == t.day) return '${diff.inHours}h';
  final yesterday = DateTime(n.year, n.month, n.day).subtract(const Duration(days: 1));
  if (DateTime(t.year, t.month, t.day) == yesterday) return 'Yesterday';
  return Fmt.shortDate(t);
}

AppNotice noticeFromDoc(String id, Map<String, dynamic> d) {
  final created = d['createdAt'];
  return AppNotice(
    id: id,
    kind: noticeKindFromName(d['type'] as String?),
    title: (d['title'] as String?) ?? '',
    body: (d['body'] as String?) ?? '',
    time: noticeTime(created is Timestamp ? created.toDate() : null),
    route: routeForRef(d['refType'] as String?, d['refId'] as String?),
    read: d['read'] == true,
  );
}

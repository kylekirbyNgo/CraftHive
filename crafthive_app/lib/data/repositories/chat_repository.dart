import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show FileOptions, FunctionException, PostgrestException, StorageException, SupabaseClient;

import '../../core/theme/app_colors.dart';
import '../../core/utils/format.dart';
import '../models.dart';
import 'auth_repository.dart';
import 'catalog_repository.dart' show initialsOf;
import 'listing_repository.dart' show photoType;
import 'order_repository.dart' show PickedImage;

/// Buyer–seller chat in Firestore (Milestone II NoSQL model):
///   chats/{buyerUid}_{storeId}          participantUids, buyerUid, sellerUid, storeId,
///                                       buyerName, storeName, lastMessage, lastMessageAt,
///                                       lastSenderUid, unread {uid: n}, lastReadAt {uid: time},
///                                       productId, requestId, requestCode, orderId, orderNumber,
///                                       tagLabel, tagTone
///   chats/{chatId}/messages/{msgId}     senderUid, type (text | quote | system), text, createdAt,
///                                       quoteId, requestCode, item, price, readyBy (quote cards)
///
/// The app writes text messages. Quote cards and order updates are written by
/// the firebase-bridge Edge Function after PostgreSQL saves the change.
abstract class ChatRepository {
  /// My chats, newest first.
  Stream<List<ChatThread>> watchThreads(String me);

  /// Messages of one chat, oldest first.
  Stream<List<ChatMessage>> watchMessages(String chatId, String me);

  /// Opens the chat with a store (as buyer), or the chat of an order or custom
  /// request (as buyer or seller). Creates it the first time. Returns its ID.
  Future<String> open(String me, {String? storeId, String? orderId, String? requestId, String? productId});

  Future<void> sendText(String me, ChatThread thread, String text);

  /// Uploads the photo to the private chat-photos bucket and posts it in the chat.
  Future<void> sendPhoto(String me, ChatThread thread, PickedImage photo);

  /// A link to view a chat photo, valid for an hour.
  Future<String> photoUrl(String path);

  /// Clears my unread count and marks the other person's messages as seen.
  Future<void> markRead(String me, String chatId);
}

/// Private bucket for chat photos: chat-photos/{chatId}/{file}. The storage
/// policies in 08_cron_and_chat_photos.sql let only the buyer and the store
/// owner of that chat upload and open them.
const chatPhotoBucket = 'chat-photos';

/// Preview in the chat list for a photo message.
const photoPreview = '📷 Photo';

/// Turns Firebase and network errors into messages that can be shown on screen.
Future<T> firebaseGuard<T>(Future<T> Function() call, {Duration timeout = const Duration(seconds: 20)}) async {
  try {
    return await call().timeout(timeout);
  } on AppFailure {
    rethrow;
  } on TimeoutException {
    throw const AppFailure('The server took too long to answer. Check your connection and try again.');
  } on FirebaseException catch (e) {
    debugPrint('Firebase error ${e.plugin}/${e.code}: ${e.message}');
    if (e.code == 'unavailable') throw const AppFailure(offlineMessage);
    if (e.code == 'unauthenticated') {
      throw const AppFailure('Your chat session expired. Close and reopen the app, then try again.');
    }
    if (e.code == 'permission-denied') {
      // Firestore rules refused it (for example rules not published yet).
      throw const AppFailure("This couldn't be sent. Close and reopen the app, then try again.");
    }
    throw const AppFailure(serverMessage);
  } on FunctionException {
    throw const AppFailure(serverMessage);
  } on StorageException catch (e) {
    debugPrint('Storage error ${e.statusCode}: ${e.message}');
    if (e.statusCode == '413' || e.message.toLowerCase().contains('size')) throw const AppFailure('That photo is too large. Choose one under 5 MB.');
    throw const AppFailure('The photo could not be sent. Please try again.');
  } on PostgrestException catch (e) {
    // Messages raised by chat_target (SQLSTATE P0001) are written for the user.
    throw AppFailure(e.code == 'P0001' || (e.code ?? '').startsWith('PT') ? e.message : serverMessage);
  } catch (e) {
    final text = e.toString();
    if (RegExp(r'SocketException|Failed host lookup|Network is unreachable', caseSensitive: false).hasMatch(text)) {
      throw const AppFailure(offlineMessage);
    }
    throw const AppFailure(serverMessage);
  }
}

class FirestoreChatRepository implements ChatRepository {
  FirestoreChatRepository(this._fs, this._db);
  final FirebaseFirestore _fs;
  final SupabaseClient _db;

  CollectionReference<Map<String, dynamic>> get _chats => _fs.collection('chats');

  // Sorted on the phone, so Firestore needs no composite index for this query.
  @override
  Stream<List<ChatThread>> watchThreads(String me) => _chats.where('participantUids', arrayContains: me).limit(200).snapshots().map((q) {
        final docs = [...q.docs]..sort((a, b) => _millis(b.data()['lastMessageAt']).compareTo(_millis(a.data()['lastMessageAt'])));
        return [for (final d in docs) threadFromDoc(d.id, d.data(), me)];
      });

  /// A message still being sent has no server time yet: it counts as the newest.
  static int _millis(Object? t) => t is Timestamp ? t.millisecondsSinceEpoch : 1 << 52;

  @override
  Stream<List<ChatMessage>> watchMessages(String chatId, String me) => _chats
      .doc(chatId)
      .collection('messages')
      .orderBy('createdAt')
      .limitToLast(300)
      .snapshots()
      .map((q) => [for (final d in q.docs) messageFromDoc(d.id, d.data(), me)]);

  @override
  Future<String> open(String me, {String? storeId, String? orderId, String? requestId, String? productId}) => firebaseGuard(() async {
        final res = await _db.rpc<dynamic>('chat_target', params: {
          'p_store_id': storeId,
          'p_order_id': orderId,
          'p_request_id': requestId,
        });
        final t = Map<String, dynamic>.from(res as Map);
        final chatId = t['chat_id'] as String;
        final ref = _chats.doc(chatId);
        final snap = await ref.get();
        if (!snap.exists) {
          await ref.set({
            'participantUids': [t['buyer_id'], t['seller_id']],
            'buyerUid': t['buyer_id'],
            'sellerUid': t['seller_id'],
            'storeId': t['store_id'],
            'buyerName': t['buyer_name'],
            'storeName': t['store_name'],
            'productId': productId,
            'lastMessage': '',
            'lastMessageAt': FieldValue.serverTimestamp(),
            'lastSenderUid': null,
            'unread': <String, int>{},
            'lastReadAt': <String, Object>{},
            'tagLabel': 'Inquiry',
            'tagTone': 'neutral',
          });
        } else if (productId != null && snap.data()?['productId'] != productId) {
          await ref.update({'productId': productId});
        }
        return chatId;
      });

  @override
  Future<void> sendText(String me, ChatThread thread, String text) => firebaseGuard(() async {
        final chat = _chats.doc(thread.id);
        final message = chat.collection('messages').doc();
        final batch = _fs.batch()
          ..set(message, {'senderUid': me, 'type': 'text', 'text': text, 'createdAt': FieldValue.serverTimestamp()})
          ..update(chat, {
            'lastMessage': text.length > 120 ? '${text.substring(0, 119)}…' : text,
            'lastMessageAt': FieldValue.serverTimestamp(),
            'lastSenderUid': me,
            if (thread.otherUid.isNotEmpty) 'unread.${thread.otherUid}': FieldValue.increment(1),
          });
        await batch.commit();
        unawaited(_push(thread.id, message.id));
      });

  @override
  Future<void> sendPhoto(String me, ChatThread thread, PickedImage photo) => firebaseGuard(() async {
        final type = photoType(photo.fileName);
        final path = '${thread.id}/${me}_${DateTime.now().millisecondsSinceEpoch}.${type.ext}';
        await _db.storage.from(chatPhotoBucket).uploadBinary(path, photo.bytes, fileOptions: FileOptions(contentType: type.mime));
        final chat = _chats.doc(thread.id);
        final message = chat.collection('messages').doc();
        final batch = _fs.batch()
          ..set(message, {'senderUid': me, 'type': 'photo', 'text': '', 'imagePath': path, 'createdAt': FieldValue.serverTimestamp()})
          ..update(chat, {
            'lastMessage': photoPreview,
            'lastMessageAt': FieldValue.serverTimestamp(),
            'lastSenderUid': me,
            if (thread.otherUid.isNotEmpty) 'unread.${thread.otherUid}': FieldValue.increment(1),
          });
        await batch.commit();
        unawaited(_push(thread.id, message.id));
      }, timeout: const Duration(seconds: 90));

  @override
  Future<String> photoUrl(String path) => firebaseGuard(() => _db.storage.from(chatPhotoBucket).createSignedUrl(path, 60 * 60));

  /// Push to the other phone. The message is already saved, so a failed push is only logged.
  Future<void> _push(String chatId, String messageId) async {
    try {
      await _db.functions.invoke('firebase-bridge', body: {'action': 'chat_push', 'chatId': chatId, 'messageId': messageId});
    } catch (e) {
      debugPrint('chat push failed: $e');
    }
  }

  @override
  Future<void> markRead(String me, String chatId) => firebaseGuard(() => _chats.doc(chatId).update({
        'unread.$me': 0,
        'lastReadAt.$me': FieldValue.serverTimestamp(),
      }));
}

// ---------------------------------------------------------------------------
// Document → model mapping (plain functions so they can be unit-tested)
// ---------------------------------------------------------------------------
const _chatColors = [AppColors.moss, AppColors.clay, AppColors.slateTeal, Color(0xFFB07A16), Color(0xFF7B5A80), Color(0xFF9A6B12)];

DateTime? _time(Object? v) => v is Timestamp ? v.toDate() : (v is DateTime ? v : null);

Tone toneFromName(String? name) => switch (name) {
      'success' => Tone.success,
      'warning' => Tone.warning,
      'error' => Tone.error,
      'info' => Tone.info,
      'seller' => Tone.seller,
      _ => Tone.neutral,
    };

/// 2:05 PM today, "Yesterday", or Nov 3.
String chatTime(DateTime? t, {DateTime? now}) {
  if (t == null) return '';
  final n = now ?? DateTime.now();
  final today = DateTime(n.year, n.month, n.day);
  final day = DateTime(t.year, t.month, t.day);
  if (day == today) return Fmt.time(t);
  if (day == today.subtract(const Duration(days: 1))) return 'Yesterday';
  return Fmt.shortDate(t);
}

ChatThread threadFromDoc(String id, Map<String, dynamic> d, String me) {
  final buying = d['buyerUid'] == me;
  final name = ((buying ? d['storeName'] : d['buyerName']) as String?) ?? (buying ? 'Maker' : 'Buyer');
  final otherUid = ((buying ? d['sellerUid'] : d['buyerUid']) as String?) ?? '';
  final unread = (d['unread'] as Map?)?[me];
  final readAt = (d['lastReadAt'] as Map?)?[otherUid];
  final last = (d['lastMessage'] as String?) ?? '';
  return ChatThread(
    id: id,
    side: buying ? ChatSide.buying : ChatSide.selling,
    name: name,
    initials: initialsOf(name),
    color: _chatColors[id.hashCode.abs() % _chatColors.length],
    messages: const [],
    tag: StatusTag((d['tagLabel'] as String?) ?? (buying ? 'Buying' : 'Inquiry'), toneFromName(d['tagTone'] as String?)),
    // Seller pages are opened by store ID (/seller/{storeId}).
    sellerId: d['storeId'] as String?,
    productId: d['productId'] as String?,
    unread: unread is num ? unread.toInt() : 0,
    lastTime: chatTime(_time(d['lastMessageAt'])),
    preview: last.isEmpty ? '' : (d['lastSenderUid'] == me ? 'You: $last' : last),
    otherUid: otherUid,
    requestCode: d['requestCode'] as String?,
    orderNumber: d['orderNumber'] as String?,
    otherReadAt: _time(readAt),
  );
}

ChatMessage messageFromDoc(String id, Map<String, dynamic> d, String me) {
  final sentAt = _time(d['createdAt']);
  final kind = switch (d['type']) {
    'quote' => MessageKind.quote,
    'system' => MessageKind.system,
    'photo' => MessageKind.photo,
    _ => MessageKind.text,
  };
  final readyBy = DateTime.tryParse((d['readyBy'] as String?) ?? '');
  return ChatMessage(
    id: id,
    fromMe: d['senderUid'] == me,
    text: (d['text'] as String?) ?? '',
    // A message being sent has no server time yet.
    time: kind == MessageKind.system ? '' : Fmt.time(sentAt ?? DateTime.now()),
    sentAt: sentAt,
    kind: kind,
    quoteId: d['quoteId'] as String?,
    requestCode: d['requestCode'] as String?,
    imagePath: d['imagePath'] as String?,
    quote: kind == MessageKind.quote
        ? Quote(item: (d['item'] as String?) ?? 'Custom item', price: (d['price'] as num?)?.toDouble() ?? 0, readyBy: readyBy ?? DateTime.now())
        : null,
  );
}

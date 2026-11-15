import 'package:cloud_firestore/cloud_firestore.dart' show Timestamp;
import 'package:crafthive/data/models.dart';
import 'package:crafthive/data/repositories/chat_repository.dart';
import 'package:crafthive/data/repositories/fake_repositories.dart';
import 'package:crafthive/data/repositories/firebase_session.dart';
import 'package:crafthive/data/repositories/notification_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'test_helpers.dart';

/// Messaging and notifications (Firebase). The Firestore documents are mapped
/// with plain functions, so they are tested here without a Firebase project.
void main() {
  const buyer = '11111111-1111-4111-8111-111111111111';
  const seller = '22222222-2222-4222-8222-222222222222';
  const store = '33333333-3333-4333-8333-333333333333';
  final now = DateTime(2026, 11, 15, 14, 30);

  Map<String, dynamic> chatDoc() => {
        'participantUids': [buyer, seller],
        'buyerUid': buyer,
        'sellerUid': seller,
        'storeId': store,
        'buyerName': 'Jose Cortez',
        'storeName': 'Ana Makes',
        'lastMessage': 'Is this still available?',
        'lastMessageAt': Timestamp.fromDate(now),
        'lastSenderUid': buyer,
        'unread': {seller: 2},
        'lastReadAt': {seller: Timestamp.fromDate(now)},
        'tagLabel': 'Custom · Quoted',
        'tagTone': 'info',
        'requestCode': 'CR-1063',
      };

  group('Chat documents', () {
    test('TC-M01 the buyer sees the store, the seller sees the buyer', () {
      final mine = threadFromDoc('${buyer}_$store', chatDoc(), buyer);
      expect(mine.side, ChatSide.buying);
      expect(mine.name, 'Ana Makes');
      expect(mine.otherUid, seller);
      expect(mine.sellerId, store);
      expect(mine.unread, 0);
      expect(mine.lastMessage, 'You: Is this still available?');
      expect(mine.tag.label, 'Custom · Quoted');
      expect(mine.tag.tone, Tone.info);
      expect(mine.requestCode, 'CR-1063');

      final theirs = threadFromDoc('${buyer}_$store', chatDoc(), seller);
      expect(theirs.side, ChatSide.selling);
      expect(theirs.name, 'Jose Cortez');
      expect(theirs.initials, 'JC');
      expect(theirs.otherUid, buyer);
      expect(theirs.unread, 2);
      expect(theirs.lastMessage, 'Is this still available?');
    });

    test('TC-M02 the seller reading the chat sets the buyer\'s "Seen" time', () {
      final t = threadFromDoc('c', chatDoc(), buyer);
      expect(t.otherReadAt, now);
    });

    test('TC-M03 text, system and quote messages', () {
      final text = messageFromDoc('m1', {'senderUid': buyer, 'type': 'text', 'text': 'Hello', 'createdAt': Timestamp.fromDate(now)}, buyer);
      expect(text.fromMe, isTrue);
      expect(text.kind, MessageKind.text);
      expect(text.time, '2:30 PM');
      expect(text.sentAt, now);

      final note = messageFromDoc('m2', {'senderUid': null, 'type': 'system', 'text': 'Order CH-2026-000047 placed'}, buyer);
      expect(note.kind, MessageKind.system);
      expect(note.fromMe, isFalse);
      expect(note.time, '');

      final quote = messageFromDoc('m3', {
        'senderUid': null,
        'type': 'quote',
        'text': 'Can do!',
        'quoteId': 'q1',
        'requestCode': 'CR-1063',
        'item': 'Crochet Tulip × 2',
        'price': 900,
        'readyBy': '2026-12-10',
      }, buyer);
      expect(quote.kind, MessageKind.quote);
      expect(quote.quote!.price, 900);
      expect(quote.quote!.readyBy, DateTime(2026, 12, 10));
      expect(quote.quoteId, 'q1');
      expect(quote.requestCode, 'CR-1063');
    });

    test('TC-M04 a message still being sent shows the current time', () {
      final m = messageFromDoc('m', {'senderUid': buyer, 'type': 'text', 'text': 'Hi', 'createdAt': null}, buyer);
      expect(m.sentAt, isNull);
      expect(m.time, isNotEmpty);
    });

    test('TC-M05 chat list times', () {
      expect(chatTime(DateTime(2026, 11, 15, 9, 5), now: now), '9:05 AM');
      expect(chatTime(DateTime(2026, 11, 14, 22, 0), now: now), 'Yesterday');
      expect(chatTime(DateTime(2026, 11, 2), now: now), 'Nov 2');
      expect(chatTime(null, now: now), '');
    });
  });

  group('Notification documents', () {
    test('TC-N01 each notification opens its order, request or chat', () {
      expect(routeForRef('order', 'CH-2026-000047'), '/order/CH-2026-000047');
      expect(routeForRef('request', 'CR-1063'), '/request/CR-1063');
      expect(routeForRef('chat', '${buyer}_$store'), '/chat/${buyer}_$store');
      expect(routeForRef('order', null), '/notifications');
    });

    test('TC-N02 notification types and times', () {
      final n = noticeFromDoc('n1', {
        'type': 'payment',
        'title': 'Payment proof received',
        'body': 'Jose sent ₱900',
        'refType': 'order',
        'refId': 'CH-2026-000047',
        'read': false,
        'createdAt': Timestamp.fromDate(now.subtract(const Duration(minutes: 5))),
      });
      expect(n.id, 'n1');
      expect(n.kind, NoticeKind.payment);
      expect(n.read, isFalse);
      expect(n.route, '/order/CH-2026-000047');
      expect(noticeKindFromName('shipping'), NoticeKind.shipping);
      expect(noticeKindFromName('something new'), NoticeKind.order);
      expect(noticeTime(now.subtract(const Duration(seconds: 20)), now: now), 'Just now');
      expect(noticeTime(now.subtract(const Duration(minutes: 5)), now: now), '5m');
      expect(noticeTime(now.subtract(const Duration(hours: 3)), now: now), '3h');
      expect(noticeTime(DateTime(2026, 11, 14, 20), now: now), 'Yesterday');
      expect(noticeTime(DateTime(2026, 10, 28), now: now), 'Oct 28');
    });

    test('TC-N03 a push notification can only open known screens', () {
      expect(safeRoute('/chat/${buyer}_$store'), '/chat/${buyer}_$store');
      expect(safeRoute('/order/CH-2026-000047'), '/order/CH-2026-000047');
      expect(safeRoute('/request/CR-1063'), '/request/CR-1063');
      expect(safeRoute('/notifications'), '/notifications');
      expect(safeRoute('/store/edit'), isNull);
      expect(safeRoute('https://evil.example'), isNull);
      expect(safeRoute(null), isNull);
    });
  });

  group('Messaging screens', () {
    testWidgets('TC-M06 sending a message shows it in the chat and the list', (tester) async {
      final chats = FakeChatRepository();
      await pumpApp(tester, auth: FakeAuthRepository(signedIn: true), chats: chats);
      await tester.tap(find.text('Messages').last);
      await tester.pumpAndSettle();
      await tapText(tester, 'Narra Craft Co.');
      expect(find.text('Hi Ana! I can make a set of 3 with the engraving. Small, medium and large.'), findsOneWidget);

      await tester.enterText(find.byType(TextField).last, 'Can you add a gift box?');
      await tester.pump();
      await tester.tap(find.bySemanticsLabel('Send message'));
      await tester.pumpAndSettle();
      expect(find.text('Can you add a gift box?'), findsOneWidget);
      expect(chats.threads.firstWhere((t) => t.id == 't-narra').messages.last.text, 'Can you add a gift box?');
      // Opening the chat cleared its unread count.
      expect(chats.threads.firstWhere((t) => t.id == 't-narra').unread, 0);
    });

    testWidgets('TC-N04 Mark all read clears the bell count', (tester) async {
      final notices = FakeNotificationRepository();
      await pumpApp(tester, auth: FakeAuthRepository(signedIn: true), notices: notices);
      expect(notices.notices.where((n) => !n.read), isNotEmpty);
      await tester.tap(find.byTooltip('Notifications'));
      await tester.pumpAndSettle();
      await tapText(tester, 'Mark all read');
      expect(notices.notices.where((n) => !n.read), isEmpty);
      expect(find.text('Mark all read'), findsNothing);
    });
  });
}

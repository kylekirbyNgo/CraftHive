import 'package:cloud_firestore/cloud_firestore.dart' show Timestamp;
import 'package:crafthive/data/models.dart';
import 'package:crafthive/data/repositories/chat_repository.dart';
import 'package:crafthive/data/repositories/fake_repositories.dart';
import 'package:crafthive/data/repositories/order_repository.dart' show PickedImage;
import 'package:crafthive/data/repositories/recent_search_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'test_helpers.dart';

/// Recent searches (Firestore users/{uid}/recentSearches) and photos in chat.
void main() {
  group('Recent searches', () {
    testWidgets('TC-R01 a search is kept and shown under Recent searches on Home', (tester) async {
      final recent = FakeRecentSearchRepository();
      await pumpApp(tester, auth: FakeAuthRepository(signedIn: true), recent: recent);

      await tester.tap(find.bySemanticsLabel('Search crafts, shops or makers').first);
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).first, 'crochet tulip');
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pumpAndSettle();
      expect(recent.terms, ['crochet tulip']);

      await tester.tap(find.byTooltip('Go back').last);
      await tester.pumpAndSettle();
      expect(find.text('Recent searches'), findsOneWidget);
      expect(find.text('crochet tulip'), findsWidgets);
    });

    testWidgets('TC-R02 Clear removes all recent searches', (tester) async {
      final recent = FakeRecentSearchRepository(['candles', 'tote bag']);
      await pumpApp(tester, auth: FakeAuthRepository(signedIn: true), recent: recent);
      expect(find.text('Recent searches'), findsOneWidget);

      await tapText(tester, 'Clear');
      expect(recent.terms, isEmpty);
      expect(find.text('Recent searches'), findsNothing);
    });

    test('TC-R03 the same search twice is kept once, newest first, at most 10', () async {
      final recent = FakeRecentSearchRepository();
      for (var i = 0; i < 12; i++) {
        await recent.add('me', 'term $i');
      }
      await recent.add('me', 'TERM 5');
      expect(recent.terms.length, recentSearchLimit);
      expect(recent.terms.first, 'TERM 5');
      expect(recent.terms.where((t) => t.toLowerCase() == 'term 5').length, 1);
    });

    test('TC-R04 search terms become safe Firestore document IDs', () {
      expect(recentSearchId('  Crochet   Tulip '), 'crochet tulip');
      expect(recentSearchId('a/b\\c'), 'a b c');
      expect(recentSearchId('__x'), '___x');
      expect(recentSearchId('x' * 150).length, 100);
    });
  });

  group('Photos in chat', () {
    test('TC-C01 a photo message is read from Firestore', () {
      final m = messageFromDoc('m1', {
        'senderUid': 'me',
        'type': 'photo',
        'text': '',
        'imagePath': 'buyer_store/me_1.jpg',
        'createdAt': Timestamp.fromDate(DateTime(2026, 11, 15, 20, 5)),
      }, 'me');
      expect(m.kind, MessageKind.photo);
      expect(m.imagePath, 'buyer_store/me_1.jpg');
      expect(m.fromMe, isTrue);
      expect(m.time, '8:05 PM');
    });

    test('TC-C02 sending a photo adds it to the chat and the chat list says Photo', () async {
      final chats = FakeChatRepository();
      final thread = chats.threads.firstWhere((t) => t.id == 't-narra');
      await chats.sendPhoto('me', thread, PickedImage(bytes: Uint8List.fromList([1, 2, 3]), fileName: 'gift_box.jpg'));
      final updated = chats.threads.firstWhere((t) => t.id == 't-narra');
      expect(updated.messages.last.kind, MessageKind.photo);
      expect(updated.messages.last.imagePath, 't-narra/gift_box.jpg');
      expect(updated.lastMessage, 'You: 📷 Photo');
    });
  });
}

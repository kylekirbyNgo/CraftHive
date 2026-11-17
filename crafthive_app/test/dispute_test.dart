import 'dart:typed_data';

import 'package:crafthive/data/models.dart';
import 'package:crafthive/data/repositories/dispute_repository.dart';
import 'package:crafthive/data/repositories/fake_repositories.dart';
import 'package:crafthive/data/repositories/order_repository.dart';
import 'package:crafthive/shared/widgets/action_helpers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'test_helpers.dart';

final _png = Uint8List.fromList(const [
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
  0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4, 0x89, 0x00, 0x00, 0x00, 0x0D, 0x49, 0x44, 0x41, 0x54, 0x78, 0x9C, 0x63, 0xF8, 0xCF, 0xC0, 0xF0,
  0x1F, 0x00, 0x05, 0x00, 0x01, 0xFF, 0x89, 0x99, 0x3D, 0x1D, 0x00, 0x00, 0x00, 0x00, 0x49, 0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82,
]);
final _picker = photoPickerProvider.overrideWithValue((_) async => PickedImage(bytes: _png, fileName: 'photo.png'));

const _delivered = 'CH-2026-000977'; // bought from Wick & Wax MNL, delivered
const _sold = 'CH-2026-001003'; // sold by the demo user, delivered

Future<void> _openOrder(WidgetTester tester, String number) async {
  final app = tester.widget<MaterialApp>(find.byType(MaterialApp));
  (app.routerConfig! as GoRouter).go('/order/$number');
  await tester.pumpAndSettle();
}

Future<void> _show(WidgetTester tester, String text) async {
  await tester.scrollUntilVisible(find.text(text), 200, scrollable: find.byType(Scrollable).first);
  await tester.pumpAndSettle();
}

Future<void> _tap(WidgetTester tester, String text) async {
  await _show(tester, text);
  await tapText(tester, text);
}

Dispute _sample({DisputeStatus status = DisputeStatus.open, String orderId = 'id-$_delivered', String? resolution}) => Dispute(
      id: 'd-9',
      orderId: orderId,
      orderNumber: _delivered,
      reason: 'Item arrived damaged: The candle jar was cracked when the box arrived.',
      status: status,
      openedAt: DateTime(2026, 11, 16, 10),
      openedByBuyer: true,
      openedByMe: true,
      storeName: 'Wick & Wax MNL',
      buyerName: 'Ana Reyes',
      orderTotal: 320,
      resolution: resolution,
      resolvedBy: resolution == null ? null : 'CraftHive Admin',
      resolvedAt: resolution == null ? null : DateTime(2026, 11, 17),
      payments: const [DisputePayment(reference: 'GC1234567', amount: 320, status: PaymentStatus.verified)],
      evidence: [DisputeEvidence(path: 'u/id-$_delivered/dispute_1.jpg', byBuyer: true, byMe: true, uploadedAt: DateTime(2026, 11, 16, 10))],
    );

void main() {
  group('Dispute mapping', () {
    test('a dispute with its order, quote, payments and evidence', () {
      final d = disputeFromJson({
        'dispute_id': 'd1',
        'order_id': 'o1',
        'order_number': 'CH-2026-001047',
        'order_status': 'delivered',
        'order_total': 680,
        'is_custom': true,
        'store_name': 'ana.makes',
        'opened_by_role': 'seller',
        'opened_by_me': false,
        'my_role': 'admin',
        'reason': 'Payment not received: the transfer never arrived.',
        'status': 'under_review',
        'opened_at': '2026-11-16T02:00:00Z',
        'quote': {'version': 2, 'price': 680, 'ready_by': '2026-11-30'},
        'payments': [
          {'reference': 'GC99', 'amount': 680, 'status': 'rejected', 'proof_path': 'b/o1/proof.jpg'}
        ],
        'evidence': [
          {'path': 's/o1/dispute_1.jpg', 'by_role': 'seller', 'by_me': false, 'uploaded_at': '2026-11-16T02:00:00Z'}
        ],
      });
      expect(d.status, DisputeStatus.underReview);
      expect(d.status.isActive, isTrue);
      expect(d.openedByBuyer, isFalse);
      expect(d.quoteVersion, 2);
      expect(d.quoteReadyBy, DateTime(2026, 11, 30));
      expect(d.payments.single.status, PaymentStatus.rejected);
      expect(d.evidence.single.byBuyer, isFalse);
    });

    test('status names match the database', () {
      for (final s in DisputeStatus.values) {
        expect(disputeStatusFromDb(disputeStatusToDb(s)), s);
      }
    });
  });

  group('Report a problem', () {
    testWidgets('TC-D01 a buyer reports a damaged item with a photo', (tester) async {
      final orders = FakeOrderRepository(FakeCatalogRepository());
      final repo = FakeDisputeRepository(orders: orders);
      await pumpApp(tester, auth: FakeAuthRepository(signedIn: true), orders: orders, disputes: repo, extra: [_picker]);
      await _openOrder(tester, _delivered);
      await _tap(tester, 'Report a problem');

      await _tap(tester, 'Send report');
      expect(find.text('Choose what went wrong.'), findsOneWidget);

      await tapText(tester, 'Item arrived damaged');
      await tester.enterText(find.byType(TextField).first, 'The candle jar was cracked when the box arrived.');
      await _tap(tester, 'Add photo');
      await _tap(tester, 'Send report');

      expect(repo.disputes.single.reason, 'Item arrived damaged: The candle jar was cracked when the box arrived.');
      expect(repo.disputes.single.evidence, hasLength(1));
      await _show(tester, 'Reported problem');
      expect(find.text('Reported'), findsOneWidget);
      expect(find.text('Report a problem'), findsNothing); // one open report per order
    });

    testWidgets('TC-D02 the seller can report a problem too', (tester) async {
      await pumpApp(tester, auth: FakeAuthRepository(signedIn: true), extra: [_picker]);
      await _openOrder(tester, _sold);
      await _tap(tester, 'Report a problem');
      expect(find.text('Buyer not responding'), findsOneWidget);
      expect(find.text('Item not received'), findsNothing);
    });

    testWidgets('TC-D03 both sides see the admin decision', (tester) async {
      final repo = FakeDisputeRepository(disputes: [_sample(status: DisputeStatus.resolved, resolution: 'The store will send a new candle by Nov 20.')]);
      await pumpApp(tester, auth: FakeAuthRepository(signedIn: true), disputes: repo);
      await _openOrder(tester, _delivered);
      await _show(tester, 'Reported problem');
      expect(find.textContaining('The store will send a new candle'), findsOneWidget);
      expect(find.text('Add a photo'), findsNothing);
      // Decided, so a new report is allowed again.
      await _show(tester, 'Report a problem');
    });
  });

  group('Admin', () {
    testWidgets('TC-D04 an admin reviews and resolves a dispute', (tester) async {
      final repo = FakeDisputeRepository(disputes: [_sample()]);
      await pumpApp(tester, auth: FakeAuthRepository(signedInAsAdmin: true), disputes: repo);
      expect(find.text('Disputes (1)'), findsOneWidget);
      await tapText(tester, 'Disputes (1)');
      await tapText(tester, '$_delivered · Wick & Wax MNL');
      expect(find.textContaining('ref GC1234567'), findsOneWidget);

      await _tap(tester, 'Start review');
      expect(repo.disputes.single.status, DisputeStatus.underReview);

      await _tap(tester, 'Resolve');
      await tester.enterText(find.byType(TextField).last, 'The store will send a new candle by Nov 20.');
      await tapText(tester, 'Resolve'); // the button in the sheet

      final d = repo.disputes.single;
      expect(d.status, DisputeStatus.resolved);
      expect(d.resolution, 'The store will send a new candle by Nov 20.');
      expect(d.resolvedBy, 'CraftHive Admin');
      expect(find.text('No open disputes'), findsOneWidget);
    });

    testWidgets('TC-D05 a decision needs a written reason', (tester) async {
      final repo = FakeDisputeRepository(disputes: [_sample()]);
      await pumpApp(tester, auth: FakeAuthRepository(signedInAsAdmin: true), disputes: repo);
      await tapText(tester, 'Disputes (1)');
      await tapText(tester, '$_delivered · Wick & Wax MNL');
      await _tap(tester, 'Close without action');
      await tester.enterText(find.byType(TextField).last, 'No');
      await tapText(tester, 'Close report');
      expect(find.text('Write at least 10 characters.'), findsOneWidget);
      expect(repo.disputes.single.status, DisputeStatus.open);
    });
  });
}

import 'package:crafthive/data/models.dart';
import 'package:crafthive/data/repositories/auth_repository.dart';
import 'package:crafthive/data/repositories/custom_order_repository.dart';
import 'package:crafthive/data/repositories/fake_repositories.dart';
import 'package:crafthive/data/repositories/order_repository.dart';
import 'package:crafthive/data/sample_ids.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'test_helpers.dart';

/// Opens a screen by its route, like tapping a link.
Future<void> open(WidgetTester tester, String location) async {
  GoRouter.of(tester.element(find.byType(Scaffold).first)).push(location);
  await tester.pumpAndSettle();
}

void main() {
  group('Orders', () {
    testWidgets('TC-O01 Buy now places an order and opens it awaiting payment', (tester) async {
      final catalog = FakeCatalogRepository();
      final orders = FakeOrderRepository(catalog);
      await pumpApp(tester, auth: FakeAuthRepository(signedIn: true), orders: orders);

      await open(tester, '/product/${SampleIds.p1}');
      await tapText(tester, 'Buy now');
      expect(find.text('Checkout'), findsOneWidget);
      await tester.tap(find.byTooltip('Increase quantity'));
      await tester.pumpAndSettle();
      await tapText(tester, 'Place order · ₱700');

      expect(orders.orders.first.quantity, 2);
      expect(orders.orders.first.total, 700);
      expect(find.text('Order details'), findsOneWidget);
      expect(find.text('Awaiting payment'), findsWidgets);
      expect(find.text('Upload payment proof'), findsOneWidget);
    });

    testWidgets('TC-O02 seller confirms a payment proof and the order moves to Confirmed', (tester) async {
      await pumpApp(tester, auth: FakeAuthRepository(signedIn: true));
      await open(tester, '/order/CH-2026-001047');
      expect(find.text('Confirm payment'), findsOneWidget);
      await tapText(tester, 'Confirm payment');
      expect(find.text('Confirmed'), findsWidgets);
      expect(find.text('Start making it'), findsOneWidget);
    });

    testWidgets('TC-O03 a server message is shown when placing the order fails', (tester) async {
      final orders = FakeOrderRepository(FakeCatalogRepository());
      await pumpApp(tester, auth: FakeAuthRepository(signedIn: true), orders: orders);
      await open(tester, '/product/${SampleIds.p1}');
      await tapText(tester, 'Buy now');
      orders.failWith = const AppFailure('Only 1 left in stock. Lower the quantity and try again.');
      await tapText(tester, 'Place order · ₱350');
      expect(find.text('Only 1 left in stock. Lower the quantity and try again.'), findsOneWidget);
      expect(find.text('Checkout'), findsOneWidget);
    });

    test('TC-O04 my_orders JSON maps to the Order model', () {
      final o = orderFromJson({
        'order_id': 'abc',
        'order_number': 'CH-2026-000038',
        'side': 'selling',
        'counterpart': 'Juan Dela Cruz',
        'order_date': '2026-11-11T08:00:00Z',
        'total_amount': 1050,
        'status': 'completed',
        'due_date': '2026-11-20',
        'is_custom': true,
        'request_number': 'CR-1063',
        'product_id': SampleIds.p1,
        'product_title': 'Hand-carved Wooden Spoon',
        'quantity': 3,
        'payment': {'reference_number': '5012345678', 'status': 'verified', 'proof_image_path': 'u/abc/proof.jpg'},
        'reviewed': true,
        'history': [
          {'to_status': 'pending', 'note': 'Quote v1 accepted.', 'changed_at': '2026-11-11T08:00:00Z'},
          {'to_status': 'completed', 'note': null, 'changed_at': '2026-11-15T08:00:00Z'},
        ],
      });
      expect(o.side, ChatSide.selling);
      expect(o.status, OrderStatus.delivered);
      expect(o.paymentStatus, PaymentStatus.verified);
      expect(o.isCustom, isTrue);
      expect(o.requestCode, 'CR-1063');
      expect(o.history.length, 2);
      expect(o.needsProof, isFalse);
    });
  });

  group('Custom orders', () {
    testWidgets('TC-C01 buyer sends a request, the maker quotes, the buyer accepts and an order is created', (tester) async {
      final orders = FakeOrderRepository(FakeCatalogRepository());
      final requests = FakeCustomOrderRepository(orders);
      await pumpApp(tester, auth: FakeAuthRepository(signedIn: true), requests: requests);

      await open(tester, '/product/${SampleIds.p1}');
      await tapText(tester, 'Custom order');
      await tester.enterText(find.byType(TextFormField).first, 'Engrave "Lola Nena" on the handle, set of 3.');
      await tapText(tester, 'Engraving');
      // Needed-by date: open the picker and accept its suggested date.
      await tapText(tester, 'Choose a date');
      await tapText(tester, 'OK');
      await tapText(tester, 'Send request');

      expect(find.text('Waiting for the seller'), findsOneWidget);
      expect(requests.requests.single.options, ['Engraving']);
      final code = requests.requests.single.code;

      // The maker replies with a quote (as the database would after send_quote).
      await tester.runAsync(() => requests.sendQuote(request: requests.requests.single, price: 1050, readyBy: DateTime.now().add(const Duration(days: 10))));
      await tapText(tester, 'View request');
      expect(find.text('Custom request'), findsOneWidget);
      expect(find.text(code), findsWidgets);

      await tapText(tester, 'Accept quote · ₱1,050');
      await tapText(tester, 'Accept and order');
      expect(requests.requests.single.status, RequestStatus.accepted);
      expect(orders.orders.first.isCustom, isTrue);
      expect(orders.orders.first.total, 1050);
      expect(find.text('Order details'), findsOneWidget);
    });

    testWidgets('TC-C02 seller sends a quote from the request page', (tester) async {
      final orders = FakeOrderRepository(FakeCatalogRepository());
      final requests = FakeCustomOrderRepository(orders);
      final code = (await tester.runAsync(() => requests.submitRequest(CustomRequestInput(
          productId: SampleIds.p1, description: 'Ten spoons with names', options: const [], quantity: 10, neededBy: DateTime.now().add(const Duration(days: 20))))))!;
      requests.showAsSeller(code);
      await pumpApp(tester, auth: FakeAuthRepository(signedIn: true), requests: requests);

      await open(tester, '/requests?side=selling');
      expect(find.text('Send a quote or decline'), findsOneWidget);
      await tapText(tester, code);
      await tapText(tester, 'Send a quote');
      await tester.enterText(find.byType(TextField).first, '3200');
      await tapText(tester, 'Send quote');

      expect(requests.requests.single.status, RequestStatus.quoted);
      expect(requests.requests.single.latestQuote!.price, 3200);
      expect(find.text('Quoted'), findsWidgets);
    });

    test('TC-C03 my_custom_requests JSON maps to the request model', () {
      final r = customRequestFromJson({
        'request_id': 'r1',
        'request_number': 'CR-1063',
        'side': 'buying',
        'counterpart': 'Narra Craft Co.',
        'product_id': SampleIds.p1,
        'product_title': 'Hand-carved Wooden Spoon',
        'description': 'Engrave my name',
        'quantity': 3,
        'budget': 1200,
        'needed_by_date': '2026-12-18',
        'status': 'quoted',
        'created_at': '2026-11-11T08:00:00Z',
        'options': ['Engraving'],
        'image_paths': [],
        'quotes': [
          {'quote_id': 'q1', 'version_no': 1, 'offered_price': 1200, 'estimated_completion_date': '2026-12-10', 'status': 'changes_requested', 'decline_reason': 'Lower price?', 'created_at': '2026-11-11T09:00:00Z'},
          {'quote_id': 'q2', 'version_no': 2, 'offered_price': 1050, 'estimated_completion_date': '2026-12-10', 'status': 'sent', 'created_at': '2026-11-11T10:00:00Z'},
        ],
      });
      expect(r.openQuote?.id, 'q2');
      expect(r.needsMyAction, isTrue);
      expect(r.quotes.first.status, OfferStatus.changesRequested);
    });
  });
}

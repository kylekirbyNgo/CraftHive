import 'package:crafthive/data/mock_data.dart';
import 'package:crafthive/data/reports.dart';
import 'package:crafthive/data/repositories/fake_repositories.dart';
import 'package:crafthive/data/sample_ids.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'test_helpers.dart';

List<String> _labels(ReportRecord r) => [for (final f in r.fields) f.$1];
final _rows = FakeReportRepository.sampleRows;

void main() {
  group('Report columns (Milestone II)', () {
    test('1 Store Directory', () {
      final r = storeDirectoryReport(_rows[ReportKind.storeDirectory]);
      expect(r.records.first.title, 'Petal & Twine');
      expect(_labels(r.records.first), ['Seller Username', 'Store Description', 'Address', 'Category Count', 'Active Listings', 'Average Rating', 'Items Sold', 'Verified Status']);
      expect(r.records[1].fields.firstWhere((f) => f.$1 == 'Average Rating').$2, 'No reviews');
    });

    test('2 Product Listing', () {
      final r = productListingReport(_rows[ReportKind.productListing]);
      expect(_labels(r.records.single),
          ['Category Name', 'Store Name', 'Price', 'Stock Quantity', 'Has Custom Option', 'Date Created', 'Number of Images', 'Number of Reviews', 'Average Rating']);
    });

    test('4 Custom Request and Quote: request once, quote versions in order', () {
      final r = customRequestReport(_rows[ReportKind.customRequests]);
      final rec = r.records.single;
      expect(rec.title, 'CR-1063');
      expect(rec.lineColumns, ['Quote Number', 'Offered Price', 'Estimated Completion Date', 'Quote Status', 'Date Quoted']);
      expect([for (final l in rec.lines) l.first], ['v1', 'v2']);
      expect(rec.lines.last[3], 'accepted');
    });

    test('5 Order and Payment: order once, items and payments under it', () {
      final r = orderPaymentReport(_rows[ReportKind.orderPayment]);
      final rec = r.records.single;
      expect(rec.fields.map((f) => f.$1), containsAll(['Customer Full Name', 'Customer Username', 'Merchant Store Name', 'Transaction Date', 'Overall Amount', 'Current Order State', 'Total Paid']));
      expect(rec.lineColumns, containsAll(['Purchased Item Name', 'Order Quantity', 'Unit Cost at Sale', 'Payment Transaction Reference', 'Verification Status of Payment', 'Date Confirmed']));
      expect(rec.lines, hasLength(2)); // one item, one payment
    });

    test('6 Seller Reliability with trust score', () {
      final rec = sellerReliabilityReport(_rows[ReportKind.sellerReliability]).records.single;
      final f = {for (final x in rec.fields) x.$1: x.$2};
      expect(f['On-Time Completion Rate'], '94%');
      expect(f['Request-to-Order Conversion Rate'], '67%');
      expect(f['Trust Score'], '86');
      expect(rec.badge, 'Trust 86');
    });

    test('7 Marketplace Activity per category', () {
      final r = marketplaceReport(_rows[ReportKind.marketplaceActivity]);
      expect(r.records.map((x) => x.title), ['Crochet', 'Flowers']);
      expect(_labels(r.records.first), ['Starting Date', 'Ending Date', 'Number of Listings', 'Number of Orders', 'Number of Custom Requests', 'Total Order Value', 'Number of Verified Sellers', 'Average Trust Score']);
      expect(r.summary.last.$2, '₱32,430');
    });

    test('3 Search and Browse uses the fuzzy search, distance and trust', () {
      final r = searchBrowseReport(
        products: MockData.products,
        sellers: MockData.sellers,
        categories: MockData.categories,
        filters: const ReportFilters(query: 'boquet', nearCity: 'Cebu City'),
        trust: const {SampleIds.storePetal: 91},
        today: DateTime(2026, 11, 17),
      );
      final rec = r.records.firstWhere((x) => x.title == 'Hand-tied Sunflower Bouquet');
      final f = {for (final x in rec.fields) x.$1: x.$2};
      expect(f['Search Term'], 'boquet');
      expect(f['Filters Applied'], 'near Cebu City');
      expect(f['Seller Trust Score'], '91');
      expect(f['Distance'], endsWith('km'));
      expect(f['Ready-By Date'], isNot('—'));
    });

    test('CSV repeats the header on each line and quotes commas', () {
      final csv = orderPaymentReport(_rows[ReportKind.orderPayment]).toCsv().trim().split('\n');
      expect(csv.first, startsWith('Order Number,Customer Full Name'));
      expect(csv, hasLength(3)); // header + item line + payment line
      expect(csv[1], startsWith('CH-2026-001047,Bea Lim'));
      final dir = storeDirectoryReport(_rows[ReportKind.storeDirectory]).toCsv();
      expect(dir, contains('"88 Maginhawa Street, Quezon City 1101"'));
    });
  });

  group('Reports screens', () {
    late List<String> copied;
    setUp(() {
      copied = [];
      TestWidgetsFlutterBinding.ensureInitialized().defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'Clipboard.setData') copied.add((call.arguments as Map)['text'] as String);
        return null;
      });
    });

    testWidgets('TC-R01 an admin opens the Store Directory and copies it as CSV', (tester) async {
      await pumpApp(tester, auth: FakeAuthRepository(signedInAsAdmin: true));
      await tapText(tester, 'Reports');
      await tapText(tester, 'Store Directory');
      expect(find.text('Petal & Twine'), findsOneWidget);
      expect(find.text('LayerLab PH'), findsOneWidget);
      await tester.tap(find.byTooltip('Copy as CSV'));
      await tester.pumpAndSettle();
      expect(copied.single, startsWith('Store Name,Seller Username'));
    });

    testWidgets('TC-R02 a seller sees only their own store reports', (tester) async {
      final reports = FakeReportRepository();
      await pumpApp(tester, auth: FakeAuthRepository(signedIn: true), reports: reports);
      await tester.tap(find.bySemanticsLabel('My profile and store'));
      await tester.pumpAndSettle();
      await tapText(tester, 'Store reports');
      expect(find.text('Store Directory'), findsNothing);
      expect(find.text('Marketplace Activity'), findsNothing);
      await tapText(tester, 'Seller Reliability');
      expect(find.text('Trust 86'), findsOneWidget);
      expect(reports.calls.last.$2.storeId, 'store-me');
      expect(reports.calls.last.$2.from, isNotNull);

      await tapText(tester, 'All time');
      expect(reports.calls.last.$2.from, DateTime(2020));
    });

    testWidgets('TC-R03 Search and Browse runs a misspelled search', (tester) async {
      await pumpApp(tester, auth: FakeAuthRepository(signedInAsAdmin: true));
      await tapText(tester, 'Reports');
      await tapText(tester, 'Search and Browse');
      await tester.enterText(find.byType(TextField).first, 'boquet');
      await tapText(tester, 'Run search');
      expect(find.text('Hand-tied Sunflower Bouquet'), findsOneWidget);
      expect(find.text('Trust 91'), findsWidgets);
    });
  });
}

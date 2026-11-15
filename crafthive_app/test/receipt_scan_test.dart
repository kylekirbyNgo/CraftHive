import 'dart:typed_data';

import 'package:crafthive/data/repositories/receipt_scanner.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

/// Receipt scanning (payment proof). The OCR itself runs in the scan-receipt
/// Edge Function; these tests cover the app side.
void main() {
  group('Receipt scan', () {
    test('TC-P01 GCash reference numbers are shown in groups like on the receipt', () {
      expect(formatReference('5012345678901'), '5012 345 678901');
      expect(formatReference('1A2B3C4D5E6F'), '1A2B3C4D5E6F');
      expect(formatReference('123456'), '123456');
    });

    test('TC-P02 the file type is read from the image bytes', () {
      final png = Uint8List.fromList(img.encodePng(img.Image(width: 4, height: 4)));
      final jpg = img.encodeJpg(img.Image(width: 4, height: 4));
      expect(imageMime(png), 'image/png');
      expect(imageMime(jpg), 'image/jpeg');
    });

    test('TC-P03 a large screenshot is made smaller than 900 KB for the OCR service', () {
      // A 2000×3000 PNG with photo-like grain is about 6 MB, like a long phone screenshot.
      final big = img.Image(width: 2000, height: 3000);
      var seed = 7;
      for (var y = 0; y < big.height; y++) {
        for (var x = 0; x < big.width; x++) {
          seed = (seed * 1103515245 + 12345) & 0x7fffffff;
          final grain = (seed >> 16) % 24;
          big.setPixelRgb(x, y, (x ~/ 8 + grain) % 256, (y ~/ 12 + grain) % 256, (200 + grain) % 256);
        }
      }
      final bytes = Uint8List.fromList(img.encodePng(big));
      expect(bytes.lengthInBytes, greaterThan(900 * 1024));
      final small = shrinkForOcr(bytes);
      expect(small.lengthInBytes, lessThanOrEqualTo(900 * 1024));
      expect(imageMime(small), 'image/jpeg');
    });

    test('TC-P04 a small screenshot is sent as it is', () {
      final bytes = Uint8List.fromList(img.encodePng(img.Image(width: 300, height: 600)));
      expect(identical(shrinkForOcr(bytes), bytes), isTrue);
    });

    test('TC-P05 scan results: reference, amount check and duplicates', () {
      final ok = ReceiptScan.fromJson({
        'reference': '5012345678901',
        'candidates': ['5012345678901'],
        'amount': 900,
        'orderTotal': 900,
        'amountMatches': true,
        'referenceUsed': false,
        'screenshotUsed': false,
        'provider': 'gcash',
      });
      expect(ok.reference, '5012345678901');
      expect(ok.amount, 900.0);
      expect(ok.amountMatches, isTrue);
      expect(ok.provider, 'gcash');

      final short = ReceiptScan.fromJson({'reference': null, 'amount': 450, 'orderTotal': 900, 'amountMatches': false, 'referenceUsed': true});
      expect(short.reference, isNull);
      expect(short.amountMatches, isFalse);
      expect(short.referenceUsed, isTrue);
      expect(short.screenshotUsed, isFalse);
      expect(short.candidates, isEmpty);
    });
  });
}

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:supabase_flutter/supabase_flutter.dart' show FunctionException, SupabaseClient;

import 'auth_repository.dart';
import 'order_repository.dart' show PickedImage;

/// What the scan-receipt Edge Function read from a payment screenshot.
class ReceiptScan {
  const ReceiptScan({
    required this.orderTotal,
    this.reference,
    this.candidates = const [],
    this.amount,
    this.amountMatches,
    this.referenceUsed = false,
    this.screenshotUsed = false,
    this.provider,
  });

  /// Best reference number found (spaces removed), or null if none was readable.
  final String? reference;

  /// Other numbers that looked like references, best first.
  final List<String> candidates;

  /// Amount on the receipt, if readable.
  final double? amount;
  final double orderTotal;

  /// Null when no amount was read.
  final bool? amountMatches;

  /// The reference number is already saved for another payment.
  final bool referenceUsed;

  /// This exact screenshot was already uploaded for a payment.
  final bool screenshotUsed;

  /// gcash, maya or bank
  final String? provider;

  factory ReceiptScan.fromJson(Map<String, dynamic> j) => ReceiptScan(
        reference: j['reference'] as String?,
        candidates: [for (final c in (j['candidates'] as List?) ?? const []) c as String],
        amount: (j['amount'] as num?)?.toDouble(),
        orderTotal: (j['orderTotal'] as num?)?.toDouble() ?? 0,
        amountMatches: j['amountMatches'] as bool?,
        referenceUsed: j['referenceUsed'] == true,
        screenshotUsed: j['screenshotUsed'] == true,
        provider: j['provider'] as String?,
      );
}

/// Reads the reference number and amount from a receipt screenshot (OCR) and
/// checks them against the database, so the payment form can be filled in.
/// The buyer still confirms the values before sending.
abstract class ReceiptScanner {
  /// Throws [AppFailure] with a message to show when the receipt cannot be read.
  Future<ReceiptScan> scan({required String orderId, required PickedImage image});
}

class EdgeReceiptScanner implements ReceiptScanner {
  EdgeReceiptScanner(this._db);
  final SupabaseClient _db;

  @override
  Future<ReceiptScan> scan({required String orderId, required PickedImage image}) => SupabaseAuthRepository.guard(() async {
        // The free OCR plan takes files up to 1 MB; the original stays untouched for upload.
        final small = await compute(shrinkForOcr, image.bytes);
        try {
          final res = await _db.functions.invoke('scan-receipt', body: {
            'orderId': orderId,
            'image': base64Encode(small),
            'mime': imageMime(small),
            'hash': image.hash,
          });
          return ReceiptScan.fromJson(Map<String, dynamic>.from(res.data as Map));
        } on FunctionException catch (e) {
          final details = e.details;
          final message = details is Map ? details['error'] as String? : null;
          debugPrint('CraftHive: receipt scan failed: ${e.status} $details');
          throw AppFailure(message ?? 'The receipt could not be read. Type the reference number instead.');
        }
      });
}

/// image/png, image/webp or image/jpeg, from the first bytes of the file.
String imageMime(Uint8List b) {
  if (b.length > 4 && b[0] == 0x89 && b[1] == 0x50 && b[2] == 0x4E && b[3] == 0x47) return 'image/png';
  if (b.length > 12 && b[8] == 0x57 && b[9] == 0x45 && b[10] == 0x42 && b[11] == 0x50) return 'image/webp';
  return 'image/jpeg';
}

const _ocrMaxBytes = 900 * 1024;

/// Makes a copy under 900 KB for the OCR service: smaller width, then lower JPEG quality.
/// Runs in a background isolate on phones (compute).
Uint8List shrinkForOcr(Uint8List bytes) {
  if (bytes.lengthInBytes <= _ocrMaxBytes) return bytes;
  final decoded = img.decodeImage(bytes);
  if (decoded == null) return bytes;
  var image = decoded.width > 1400 ? img.copyResize(decoded, width: 1400) : decoded;
  var quality = 85;
  var out = img.encodeJpg(image, quality: quality);
  while (out.lengthInBytes > _ocrMaxBytes && quality > 45) {
    quality -= 15;
    out = img.encodeJpg(image, quality: quality);
  }
  if (out.lengthInBytes > _ocrMaxBytes) {
    image = img.copyResize(image, width: 1000);
    out = img.encodeJpg(image, quality: 70);
  }
  return out;
}

/// "5012345678901" → "5012 345 678901" (GCash style) so it is easy to compare with the receipt.
String formatReference(String ref) {
  if (RegExp(r'^\d{13}$').hasMatch(ref)) return '${ref.substring(0, 4)} ${ref.substring(4, 7)} ${ref.substring(7)}';
  return ref;
}

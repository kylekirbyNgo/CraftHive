import 'package:flutter/foundation.dart' show debugPrint;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models.dart';
import 'auth_repository.dart';
import 'listing_repository.dart' show photoType;
import 'order_repository.dart' show PickedImage, privateBucket;

/// Verified Maker: the maker sends a government ID and portfolio photos, an
/// admin approves or rejects, and the ID photo is deleted 30 days after the
/// decision (database/06_verified_maker.sql, Data Privacy Act of 2012).
abstract class VerificationRepository {
  /// The signed-in maker's status.
  Future<MyVerification> loadMine();

  /// Uploads the ID and 2–6 portfolio photos to private-files/{user_id}/verification/
  /// and sends them for review.
  Future<void> submit({required String idType, required PickedImage id, required List<PickedImage> portfolio});

  /// Admin: applications waiting for review ([pending]) or already decided.
  Future<List<VerificationApplication>> loadQueue({bool pending = true});

  /// Admin: approve, or reject with a reason the maker will see.
  Future<void> review({required String sellerId, required bool approve, String? note});
}

/// How long ID photos are kept after the decision (id_retention_days() in SQL).
const idRetentionDays = 30;

Future<T> _run<T>(String what, Future<T> Function() call) => SupabaseAuthRepository.guard(() async {
      try {
        return await call();
      } on PostgrestException catch (e) {
        debugPrint('CraftHive: $what failed: ${e.code} ${e.message}');
        if (e.code == 'P0001' || (e.code ?? '').startsWith('PT')) throw AppFailure(e.message);
        if (e.code == 'PGRST202' || e.code == '42883') {
          throw const AppFailure('Verification is not set up on the server yet. Run database/06_verified_maker.sql in Supabase.');
        }
        rethrow;
      } on StorageException catch (e) {
        debugPrint('CraftHive: $what failed: ${e.statusCode} ${e.message}');
        throw const AppFailure("A photo didn't upload. Check your connection and try again.");
      }
    });

class SupabaseVerificationRepository implements VerificationRepository {
  SupabaseVerificationRepository(this._db);
  final SupabaseClient _db;

  String get _me => _db.auth.currentUser?.id ?? '';

  @override
  Future<MyVerification> loadMine() => _run('load verification', () async {
        final row = await _db.rpc<dynamic>('my_verification');
        return row == null ? const MyVerification() : myVerificationFromJson(Map<String, dynamic>.from(row as Map));
      });

  @override
  Future<void> submit({required String idType, required PickedImage id, required List<PickedImage> portfolio}) async {
    final stamp = DateTime.now().millisecondsSinceEpoch;
    final folder = '$_me/verification';
    final uploaded = <String>[];
    try {
      Future<String> upload(PickedImage img, String name) async {
        final type = photoType(img.fileName);
        final path = '$folder/${name}_$stamp.${type.ext}';
        await _run('upload $name', () => _db.storage.from(privateBucket).uploadBinary(path, img.bytes, fileOptions: FileOptions(contentType: type.mime)));
        uploaded.add(path);
        return path;
      }

      final idPath = await upload(id, 'id');
      final portfolioPaths = [for (var i = 0; i < portfolio.length; i++) await upload(portfolio[i], 'portfolio${i + 1}')];
      await _run('submit verification', () => _db.rpc<dynamic>('submit_verification', params: {
            'p_id_type': idType,
            'p_id_path': idPath,
            'p_portfolio_paths': portfolioPaths,
          }));
    } catch (_) {
      // Nothing was sent for review, so don't leave the ID photo behind.
      if (uploaded.isNotEmpty) {
        try {
          await _db.storage.from(privateBucket).remove(uploaded);
        } catch (e) {
          debugPrint('CraftHive: clean-up of verification photos failed: $e');
        }
      }
      rethrow;
    }
  }

  @override
  Future<List<VerificationApplication>> loadQueue({bool pending = true}) => _run('load applications', () async {
        final rows = await _db.rpc<dynamic>('verification_queue', params: {'p_status': pending ? 'pending' : 'reviewed'});
        return [for (final r in (rows as List? ?? const [])) applicationFromJson(Map<String, dynamic>.from(r as Map))];
      });

  @override
  Future<void> review({required String sellerId, required bool approve, String? note}) => _run('review maker', () async {
        await _db.rpc<dynamic>('review_verification', params: {'p_seller_id': sellerId, 'p_approve': approve, 'p_note': note});
      });
}

// ---------------------------------------------------------------------------
// JSON → model (plain functions so they can be unit-tested)
// ---------------------------------------------------------------------------
VerificationStatus verificationStatusFromDb(String? s) => switch (s) {
      'pending' => VerificationStatus.pending,
      'verified' => VerificationStatus.verified,
      'rejected' => VerificationStatus.rejected,
      _ => VerificationStatus.unverified,
    };

DateTime? _date(Object? v) => v == null ? null : DateTime.tryParse(v as String)?.toLocal();
List<String> _paths(Object? v) => [for (final p in (v as List?) ?? const []) p as String];

MyVerification myVerificationFromJson(Map<String, dynamic> j) => MyVerification(
      status: verificationStatusFromDb(j['status'] as String?),
      idType: j['id_type'] as String?,
      submittedAt: _date(j['submitted_at']),
      verifiedAt: _date(j['verified_at']),
      reviewNote: j['review_note'] as String?,
      idPurgeDate: _date(j['id_purge_date']),
      idOnFile: j['id_on_file'] == true,
      portfolio: _paths(j['portfolio']),
    );

VerificationApplication applicationFromJson(Map<String, dynamic> j) => VerificationApplication(
      sellerId: j['seller_id'] as String,
      storeName: (j['store_name'] as String?) ?? '',
      ownerName: (j['full_name'] as String?) ?? '',
      username: (j['username'] as String?) ?? '',
      city: (j['city'] as String?) ?? '',
      storeDescription: (j['store_description'] as String?) ?? '',
      status: verificationStatusFromDb(j['status'] as String?),
      submittedAt: _date(j['submitted_at']) ?? DateTime.now(),
      idType: j['id_type'] as String?,
      idImagePath: j['id_image_path'] as String?,
      portfolio: _paths(j['portfolio']),
      reviewNote: j['review_note'] as String?,
      verifiedAt: _date(j['verified_at']),
      idPurgeDate: _date(j['id_purge_date']),
    );

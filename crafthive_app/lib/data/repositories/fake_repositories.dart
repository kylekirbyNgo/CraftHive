import 'dart:async';

import '../mock_data.dart';
import '../models.dart';
import 'auth_repository.dart';
import 'catalog_repository.dart';
import 'listing_repository.dart';

/// In-memory stand-ins for Supabase, used by the automated tests so they run
/// without the internet. The app itself always uses the Supabase versions.
class FakeAuthRepository implements AuthRepository {
  FakeAuthRepository({bool signedIn = false}) {
    _accounts[demoUser.email] = (user: demoUser, password: demoPassword);
    if (signedIn) _current = demoUser.id;
  }

  static const demoPassword = 'craftlover8';
  static final demoUser = AppUser(
    id: 'demo-user',
    username: MockData.demoUser.username,
    email: MockData.demoUser.email,
    phone: MockData.demoUser.phone,
    country: MockData.demoUser.country,
    sex: MockData.demoUser.sex,
    displayName: MockData.demoUser.displayName,
    bio: MockData.demoUser.bio,
    location: MockData.demoUser.location,
    isVerified: true,
  );

  final _accounts = <String, ({AppUser user, String password})>{};
  final _changes = StreamController<String?>.broadcast();
  final _recovery = StreamController<void>.broadcast();
  String? _current;

  /// When set, every call fails with this (for testing error messages).
  AppFailure? failWith;
  String? lastResetEmail;

  @override
  String? get currentUserId => _current;

  @override
  Stream<String?> get userIdChanges async* {
    yield _current;
    yield* _changes.stream;
  }

  void _set(String? id) {
    _current = id;
    _changes.add(id);
  }

  Future<void> _check() async {
    await Future<void>.delayed(const Duration(milliseconds: 10));
    final f = failWith;
    if (f != null) throw f;
  }

  @override
  Future<AppUser> loadProfile(String userId) async {
    await _check();
    return _accounts.values.firstWhere((a) => a.user.id == userId).user;
  }

  @override
  Future<void> logIn(String usernameOrEmail, String password) async {
    await _check();
    final id = usernameOrEmail.trim().toLowerCase();
    final account = _accounts.values.where((a) => a.user.email == id || a.user.username == id).firstOrNull;
    if (account == null || account.password != password) throw const AppFailure(wrongLoginMessage);
    _set(account.user.id);
  }

  @override
  Future<SignUpOutcome> signUp(SignUpData d) async {
    await _check();
    final username = d.username.trim().toLowerCase();
    final email = d.email.trim().toLowerCase();
    if (_accounts.values.any((a) => a.user.username == username)) {
      throw const AppFailure('That username is already taken. Try another one.', field: AuthField.username);
    }
    if (_accounts.containsKey(email)) {
      throw const AppFailure('An account with this email already exists. Log in instead.', field: AuthField.email);
    }
    final user = AppUser(
      id: 'user-${_accounts.length + 1}',
      username: username,
      email: email,
      phone: formatPhone(d.phone),
      country: d.country,
      sex: d.sex,
      displayName: d.fullName.trim(),
      location: d.country,
    );
    _accounts[email] = (user: user, password: d.password);
    _set(user.id);
    return SignUpOutcome.signedIn;
  }

  @override
  Future<void> sendPasswordResetLink(String email) async {
    await _check();
    lastResetEmail = email.trim().toLowerCase();
  }

  /// What happens when the user taps the emailed link on the phone.
  void openResetLink() {
    final account = _accounts[lastResetEmail];
    if (account == null) return;
    _recovery.add(null);
    _set(account.user.id);
  }

  @override
  Stream<void> get passwordRecoveryEvents => _recovery.stream;

  @override
  Future<void> updatePassword(String newPassword) async {
    await _check();
    final account = _accounts.values.firstWhere((a) => a.user.id == _current);
    _accounts[account.user.email] = (user: account.user, password: newPassword);
  }

  @override
  Future<void> signOut() async {
    await _check();
    _set(null);
  }
}

class FakeCatalogRepository implements CatalogRepository {
  /// When set, loading fails with this (for testing the error state).
  AppFailure? failWith;
  int loads = 0;

  /// The demo user's store; null means they have not opened one yet.
  String? myStoreId = 'store-me';

  /// Listings saved through [FakeListingRepository], newest first.
  final added = <Product>[];

  @override
  Future<CatalogData> load({required String myUserId}) async {
    loads++;
    await Future<void>.delayed(const Duration(milliseconds: 10));
    final f = failWith;
    if (f != null) throw f;
    final addedIds = {for (final p in added) p.id};
    return CatalogData(
      categories: MockData.categories,
      sellers: MockData.sellers,
      products: [...added, for (final p in MockData.products) if (!addedIds.contains(p.id)) p],
      myStoreId: myStoreId,
    );
  }
}

class FakeListingRepository implements ListingRepository {
  FakeListingRepository(this.catalog);
  final FakeCatalogRepository catalog;

  /// When set, every call fails with this (for testing error messages).
  AppFailure? failWith;
  int _next = 1;

  Future<void> _check() async {
    await Future<void>.delayed(const Duration(milliseconds: 10));
    final f = failWith;
    if (f != null) throw f;
  }

  Product _toProduct(String id, ListingInput i, {ListingStatus? status}) => Product(
        id: id,
        title: i.title,
        sellerId: 'me',
        categoryId: i.categoryId,
        price: i.price,
        description: i.description,
        stock: i.stock,
        leadDays: i.leadDays,
        acceptsCustom: i.acceptsCustom,
        customOptions: i.customOptions,
        photoCount: i.photos.isEmpty ? 1 : i.photos.length,
        status: status ?? (i.isDraft ? ListingStatus.hidden : ListingStatus.active),
      );

  @override
  Future<String?> findMyStoreId(String userId) async {
    await _check();
    return catalog.myStoreId;
  }

  @override
  Future<String> openStore(String userId, StoreInput store) async {
    await _check();
    return catalog.myStoreId = 'store-me';
  }

  @override
  Future<String> createListing({required String storeId, required ListingInput input}) async {
    await _check();
    final id = 'new-${_next++}';
    catalog.added.insert(0, _toProduct(id, input));
    return id;
  }

  @override
  Future<void> updateListing({
    required String storeId,
    required String productId,
    required ListingInput input,
    required List<String> previousPaths,
    required List<String> previousOptions,
  }) async {
    await _check();
    catalog.added
      ..removeWhere((p) => p.id == productId)
      ..insert(0, _toProduct(productId, input));
  }

  @override
  Future<void> archiveListing(String productId) async {
    await _check();
    final p = [...catalog.added, ...MockData.products].firstWhere((p) => p.id == productId);
    catalog.added
      ..removeWhere((x) => x.id == productId)
      ..insert(0, p.copyWith(status: ListingStatus.archived));
  }
}

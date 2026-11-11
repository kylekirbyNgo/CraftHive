import 'dart:async';

import '../mock_data.dart';
import '../models.dart';
import 'auth_repository.dart';
import 'catalog_repository.dart';
import 'custom_order_repository.dart';
import 'listing_repository.dart';
import 'order_repository.dart';

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

/// Orders kept in memory, starting with the sample orders.
class FakeOrderRepository implements OrderRepository {
  FakeOrderRepository(this.catalog);
  final FakeCatalogRepository catalog;

  /// When set, every call fails with this (for testing error messages).
  AppFailure? failWith;
  final orders = [for (final o in MockData.orders) _withId(o)];
  final usedReferences = <String>{};
  int nextNumber = 48;

  static Order _withId(Order o) => Order(
        id: 'id-${o.number}', number: o.number, side: o.side, productId: o.productId, itemLabel: o.itemLabel, quantity: o.quantity,
        total: o.total, status: o.status, counterpart: o.counterpart, placedOn: o.placedOn, isCustom: o.isCustom, history: o.history,
        fulfillment: o.fulfillment, paymentRef: o.paymentRef, chatId: o.chatId,
        paymentStatus: o.paymentRef == null ? null : (o.status == OrderStatus.pending ? PaymentStatus.submitted : PaymentStatus.verified),
      );

  Future<void> _check() async {
    await Future<void>.delayed(const Duration(milliseconds: 10));
    final f = failWith;
    if (f != null) throw f;
  }

  void _replace(Order o) => orders[orders.indexWhere((x) => x.id == o.id)] = o;

  OrderEvent _event(OrderStatus s, String note) => OrderEvent(s, 'Just now', note);

  String newNumber() => 'CH-2026-${(nextNumber++).toString().padLeft(6, '0')}';

  @override
  Future<List<Order>> loadOrders() async {
    await _check();
    return [...orders];
  }

  @override
  Future<String> placeOrder({required String productId, required int quantity}) async {
    await _check();
    final p = [...catalog.added, ...MockData.products].firstWhere((p) => p.id == productId);
    if (p.stock > 0 && p.stock < quantity) throw AppFailure('Only ${p.stock} left in stock. Lower the quantity and try again.');
    final number = newNumber();
    final seller = MockData.sellers.where((s) => s.id == p.sellerId).firstOrNull;
    orders.insert(
      0,
      Order(
        id: 'id-$number', number: number, side: ChatSide.buying, productId: p.id, itemLabel: p.title, quantity: quantity,
        total: p.price * quantity, status: OrderStatus.pending, counterpart: seller?.name ?? 'Seller', placedOn: 'Today', isCustom: false,
        history: [_event(OrderStatus.pending, 'Order placed. Your items are reserved for 24 hours while you pay.')],
      ),
    );
    return number;
  }

  @override
  Future<void> submitPayment({required Order order, required String reference, required PickedImage proof}) async {
    await _check();
    final ref = reference.replaceAll(' ', '');
    if (!usedReferences.add(ref)) throw const AppFailure('This reference number was already used for another payment.');
    _replace(order.copyWith(
        paymentRef: ref, paymentStatus: PaymentStatus.submitted, history: [...order.history, _event(order.status, 'Payment proof uploaded (reference $ref).')]));
  }

  @override
  Future<void> reviewPayment({required Order order, required bool accept, String? reason}) async {
    await _check();
    _replace(accept
        ? order.copyWith(
            status: OrderStatus.confirmed, paymentStatus: PaymentStatus.verified, history: [...order.history, _event(OrderStatus.confirmed, 'Payment confirmed by the seller.')])
        : order.copyWith(paymentStatus: PaymentStatus.rejected, history: [...order.history, _event(order.status, 'Payment proof rejected: $reason')]));
  }

  @override
  Future<void> setStatus({required Order order, required String status, String? note}) async {
    await _check();
    final to = orderStatusFromDb(status);
    _replace(order.copyWith(status: to, history: [...order.history, _event(to, note ?? status)]));
  }

  @override
  Future<void> postReview({required Order order, required int rating, String? comment}) async {
    await _check();
    _replace(order.copyWith(reviewed: true));
  }

  @override
  Future<String> privateImageUrl(String path) async => '';
}

/// Custom requests kept in memory; quotes are added with [sendQuote].
class FakeCustomOrderRepository implements CustomOrderRepository {
  FakeCustomOrderRepository(this.orders);
  final FakeOrderRepository orders;

  AppFailure? failWith;
  final requests = <CustomRequest>[];
  int _next = 1063;

  Future<void> _check() async {
    await Future<void>.delayed(const Duration(milliseconds: 10));
    final f = failWith;
    if (f != null) throw f;
  }

  CustomRequest _copy(CustomRequest r, {RequestStatus? status, List<QuoteOffer>? quotes, String? orderNumber, ChatSide? side}) => CustomRequest(
        id: r.id, code: r.code, side: side ?? r.side, counterpart: r.counterpart, productId: r.productId, productTitle: r.productTitle,
        description: r.description, options: r.options, quantity: r.quantity, budget: r.budget, neededBy: r.neededBy, sentAt: r.sentAt,
        status: status ?? r.status, quotes: quotes ?? r.quotes, orderNumber: orderNumber ?? r.orderNumber, imagePaths: r.imagePaths,
      );

  void _replace(CustomRequest r) => requests[requests.indexWhere((x) => x.id == r.id)] = r;

  /// Shows a request as if it had been sent to the demo user's store (for seller-side tests).
  void showAsSeller(String code) {
    final r = requests.firstWhere((x) => x.code == code);
    _replace(_copy(r, side: ChatSide.selling));
  }

  QuoteOffer _withStatus(QuoteOffer q, OfferStatus s, [String? reason]) => QuoteOffer(
      id: q.id, version: q.version, price: q.price, readyBy: q.readyBy, status: s, createdAt: q.createdAt, message: q.message, declineReason: reason ?? q.declineReason);

  @override
  Future<List<CustomRequest>> loadRequests() async {
    await _check();
    return [...requests];
  }

  @override
  Future<String> submitRequest(CustomRequestInput i) async {
    await _check();
    final p = MockData.products.firstWhere((p) => p.id == i.productId);
    final code = 'CR-${_next++}';
    requests.insert(
      0,
      CustomRequest(
        id: 'id-$code', code: code, side: ChatSide.buying, counterpart: MockData.sellers.where((s) => s.id == p.sellerId).firstOrNull?.name ?? '',
        productId: p.id, productTitle: p.title, description: i.description, options: i.options, quantity: i.quantity,
        budget: i.budget, neededBy: i.neededBy, sentAt: DateTime.now(),
      ),
    );
    return code;
  }

  @override
  Future<void> cancelRequest(CustomRequest r) async {
    await _check();
    _replace(_copy(r, status: RequestStatus.cancelled));
  }

  @override
  Future<void> sendQuote({required CustomRequest request, required double price, required DateTime readyBy, String? message}) async {
    await _check();
    final r = requests.firstWhere((x) => x.id == request.id);
    final quotes = [for (final q in r.quotes) q.status == OfferStatus.sent ? _withStatus(q, OfferStatus.superseded) : q];
    quotes.add(QuoteOffer(
        id: 'q-${r.code}-${quotes.length + 1}', version: quotes.length + 1, price: price, readyBy: readyBy, status: OfferStatus.sent, createdAt: DateTime.now(), message: message));
    _replace(_copy(r, status: RequestStatus.quoted, quotes: quotes));
  }

  @override
  Future<void> declineRequest({required CustomRequest request, required String reason}) async {
    await _check();
    _replace(_copy(request, status: RequestStatus.declined));
  }

  @override
  Future<String> acceptQuote(QuoteOffer quote) async {
    await _check();
    final r = requests.firstWhere((x) => x.quotes.any((q) => q.id == quote.id));
    final number = orders.newNumber();
    orders.orders.insert(
      0,
      Order(
        id: 'id-$number', number: number, side: ChatSide.buying, productId: r.productId, itemLabel: r.productTitle, quantity: r.quantity,
        total: quote.price, status: OrderStatus.pending, counterpart: r.counterpart, placedOn: 'Today', isCustom: true, requestCode: r.code,
        history: [OrderEvent(OrderStatus.pending, 'Just now', 'Quote v${quote.version} accepted. Waiting for your payment.')],
      ),
    );
    _replace(_copy(r,
        status: RequestStatus.accepted, orderNumber: number, quotes: [for (final q in r.quotes) q.id == quote.id ? _withStatus(q, OfferStatus.accepted) : q]));
    return number;
  }

  @override
  Future<void> requestChanges(QuoteOffer quote, String note) async {
    await _check();
    final r = requests.firstWhere((x) => x.quotes.any((q) => q.id == quote.id));
    _replace(_copy(r, status: RequestStatus.pending, quotes: [for (final q in r.quotes) q.id == quote.id ? _withStatus(q, OfferStatus.changesRequested, note) : q]));
  }
}

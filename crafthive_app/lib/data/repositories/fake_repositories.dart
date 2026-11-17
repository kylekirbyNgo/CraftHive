import 'dart:async';
import 'dart:typed_data';

import '../../core/utils/format.dart';
import '../mock_data.dart';
import '../sample_ids.dart';
import '../models.dart';
import '../reports.dart';
import 'admin_repository.dart';
import 'auth_repository.dart';
import 'catalog_repository.dart';
import 'chat_repository.dart';
import 'custom_order_repository.dart';
import 'dispute_repository.dart';
import 'firebase_session.dart';
import 'listing_repository.dart';
import 'notification_repository.dart';
import 'order_repository.dart';
import 'presence_repository.dart';
import 'receipt_scanner.dart';
import 'report_repository.dart';
import 'recent_search_repository.dart';
import 'saved_repository.dart';
import 'verification_repository.dart';

/// In-memory stand-ins for Supabase, used by the automated tests so they run
/// without the internet. The app itself always uses the Supabase versions.
class FakeAuthRepository implements AuthRepository {
  FakeAuthRepository({bool signedIn = false, bool signedInAsAdmin = false, bool signedInAsModerator = false}) {
    _accounts[demoUser.email] = (user: demoUser, password: demoPassword);
    _accounts[adminUser.email] = (user: signedInAsModerator ? moderatorUser : adminUser, password: demoPassword);
    if (signedIn) _current = demoUser.id;
    if (signedInAsAdmin || signedInAsModerator) _current = adminUser.id;
  }

  /// The same staff account with the moderator role (cannot manage staff).
  static const moderatorUser = AppUser(
    id: 'admin-1',
    username: 'admin',
    email: 'admin@crafthive.test',
    phone: '',
    country: 'Philippines',
    sex: 'Prefer not to say',
    displayName: 'CraftHive Admin',
    isAdmin: true,
    adminRole: 'moderator',
  );

  /// CraftHive staff account (ADMIN table); same password as the demo user.
  static const adminUser = AppUser(
    id: 'admin-1',
    username: 'admin',
    email: 'admin@crafthive.test',
    phone: '',
    country: 'Philippines',
    sex: 'Prefer not to say',
    displayName: 'CraftHive Admin',
    isAdmin: true,
    adminRole: 'superadmin',
  );

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
    hasStore: true,
    phoneDigits: MockData.demoUser.phone.replaceAll(RegExp(r'\D'), ''),
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

  /// Email waiting for confirmation after [changeEmail].
  String? pendingEmail;

  void _replaceUser(AppUser Function(AppUser u) change) {
    final key = _accounts.entries.firstWhere((e) => e.value.user.id == _current).key;
    final account = _accounts[key]!;
    _accounts[key] = (user: change(account.user), password: account.password);
  }

  @override
  Future<void> updateProfile(ProfileUpdate u) async {
    await _check();
    _replaceUser((user) => user.copyWith(
          displayName: u.fullName.trim(),
          phone: formatPhone(u.phoneDigits),
          phoneDigits: u.phoneDigits,
          bio: u.storeDescription?.trim(),
          location: u.city?.trim(),
        ));
  }

  @override
  Future<String> uploadAvatar(Uint8List bytes, String fileName) async {
    await _check();
    const url = 'https://example.com/avatar.jpg';
    _replaceUser((user) => user.copyWith(avatarUrl: url));
    return url;
  }

  @override
  Future<void> changeEmail(String newEmail) async {
    await _check();
    final email = newEmail.trim().toLowerCase();
    if (_accounts.containsKey(email)) throw const AppFailure('An account with this email already exists.', field: AuthField.email);
    pendingEmail = email;
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


// ---------------------------------------------------------------------------
// Firebase stand-ins: sample chats and notifications kept in memory. Also used
// by the app until FirebaseConfig is filled in.
// ---------------------------------------------------------------------------
class FakeFirebaseSession implements FirebaseSession {
  @override
  Future<String> connect(String userId) async => userId;

  @override
  Future<void> disconnect() async {}
}

class FakePushService implements PushService {
  final registered = <String>{};

  @override
  Future<void> register(String me) async => registered.add(me);

  @override
  Future<void> unregister(String me) async => registered.remove(me);

  @override
  Future<String?> initialRoute() async => null;

  @override
  Stream<String> get openedRoutes => const Stream.empty();

  @override
  Stream<PushBanner> get foreground => const Stream.empty();
}

class FakePresenceRepository implements PresenceRepository {
  final online = <String>{};

  @override
  Future<void> goOnline(String me) async => online.add(me);

  @override
  Future<void> goOffline(String me) async => online.remove(me);

  @override
  Stream<bool> watchOnline(String uid) => Stream.value(online.contains(uid));

  @override
  Future<void> setTyping(String chatId, String me, bool typing) async {}

  @override
  Stream<bool> watchTyping(String chatId, String uid) => Stream.value(false);
}

class FakeChatRepository implements ChatRepository {
  FakeChatRepository({List<ChatThread>? threads}) : threads = [...(threads ?? MockData.threads)];

  final List<ChatThread> threads;
  final _changes = StreamController<void>.broadcast();

  void _set(List<ChatThread> next) {
    threads
      ..clear()
      ..addAll(next);
    _changes.add(null);
  }

  @override
  Stream<List<ChatThread>> watchThreads(String me) async* {
    yield [...threads];
    yield* _changes.stream.map((_) => [...threads]);
  }

  @override
  Stream<List<ChatMessage>> watchMessages(String chatId, String me) async* {
    List<ChatMessage> current() => threads.where((t) => t.id == chatId).firstOrNull?.messages ?? const [];
    yield current();
    yield* _changes.stream.map((_) => current());
  }

  @override
  Future<String> open(String me, {String? storeId, String? orderId, String? requestId, String? productId}) async {
    final existing = threads.where((t) => t.side == ChatSide.buying && storeId != null && t.sellerId == storeId).firstOrNull;
    if (existing != null) return existing.id;
    if (storeId == null) {
      throw const AppFailure('Chats for orders and requests need Firebase. Fill in lib/core/config/firebase_config.dart.');
    }
    final store = MockData.sellers.where((s) => s.id == storeId).firstOrNull;
    final name = store?.name ?? 'Maker';
    final id = 't-$storeId';
    _set([
      ChatThread(
        id: id,
        side: ChatSide.buying,
        name: name,
        initials: initialsOf(name),
        color: store?.color ?? MockData.sellers.first.color,
        sellerId: storeId,
        productId: productId,
        lastTime: Fmt.timeNow(),
        tag: const StatusTag('Inquiry', Tone.neutral),
        messages: const [],
      ),
      ...threads,
    ]);
    return id;
  }

  @override
  Future<void> sendText(String me, ChatThread thread, String text) async {
    _set([
      for (final t in threads)
        if (t.id == thread.id)
          t.copyWith(messages: [...t.messages, ChatMessage(fromMe: true, text: text, time: Fmt.timeNow(), sentAt: DateTime.now())], lastTime: Fmt.timeNow())
        else
          t,
    ]);
  }

  @override
  Future<void> sendPhoto(String me, ChatThread thread, PickedImage photo) async {
    _set([
      for (final t in threads)
        if (t.id == thread.id)
          t.copyWith(
            messages: [
              ...t.messages,
              ChatMessage(fromMe: true, text: '', time: Fmt.timeNow(), sentAt: DateTime.now(), kind: MessageKind.photo, imagePath: '${thread.id}/${photo.fileName}'),
            ],
            lastTime: Fmt.timeNow(),
          )
        else
          t,
    ]);
  }

  @override
  Future<String> photoUrl(String path) async => '';

  @override
  Future<void> markRead(String me, String chatId) async {
    if (!threads.any((t) => t.id == chatId && t.unread > 0)) return;
    _set([for (final t in threads) t.id == chatId ? t.copyWith(unread: 0) : t]);
  }
}

class FakeNotificationRepository implements NotificationRepository {
  FakeNotificationRepository({List<AppNotice>? notices})
      : notices = [
          for (final (i, n) in (notices ?? MockData.notices).indexed)
            AppNotice(id: n.id.isEmpty ? 'n$i' : n.id, kind: n.kind, title: n.title, body: n.body, time: n.time, route: n.route, read: n.read),
        ];

  final List<AppNotice> notices;
  final _changes = StreamController<void>.broadcast();

  @override
  Stream<List<AppNotice>> watch(String me) async* {
    yield [...notices];
    yield* _changes.stream.map((_) => [...notices]);
  }

  void _mark(bool Function(AppNotice n) which) {
    for (var i = 0; i < notices.length; i++) {
      if (which(notices[i])) notices[i] = notices[i].markRead();
    }
    _changes.add(null);
  }

  @override
  Future<void> markRead(String me, String id) async => _mark((n) => n.id == id);

  @override
  Future<void> markAllRead(String me, List<String> ids) async => _mark((n) => ids.contains(n.id));
}

/// Receipt scanning without the OCR service: returns [result], or throws [failWith].
class FakeReceiptScanner implements ReceiptScanner {
  FakeReceiptScanner({this.result, this.failWith});
  ReceiptScan? result;
  AppFailure? failWith;
  int calls = 0;

  @override
  Future<ReceiptScan> scan({required String orderId, required PickedImage image}) async {
    calls++;
    await Future<void>.delayed(const Duration(milliseconds: 10));
    final f = failWith;
    if (f != null) throw f;
    return result ?? const ReceiptScan(orderTotal: 0);
  }
}

/// Saved items kept in memory (three sample items, like the Milestone 2 build).
class FakeSavedRepository implements SavedRepository {
  FakeSavedRepository({Set<String>? saved, Map<String, int>? counts})
      : saved = saved ?? {SampleIds.p2, SampleIds.p5, SampleIds.p9},
        counts = counts ?? {};

  final Set<String> saved;
  final Map<String, int> counts;
  final _changes = StreamController<void>.broadcast();

  /// When set, saving fails with this (for testing).
  AppFailure? failWith;

  @override
  Stream<Set<String>> watchSaved(String me) async* {
    yield {...saved};
    yield* _changes.stream.map((_) => {...saved});
  }

  @override
  Future<void> setSaved(String me, String productId, bool save) async {
    await Future<void>.delayed(const Duration(milliseconds: 10));
    final f = failWith;
    if (f != null) throw f;
    final changed = save ? saved.add(productId) : saved.remove(productId);
    if (changed) counts[productId] = ((counts[productId] ?? 0) + (save ? 1 : -1)).clamp(0, 1 << 30);
    _changes.add(null);
  }

  @override
  Stream<int> watchSaveCount(String productId) async* {
    yield counts[productId] ?? 0;
    yield* _changes.stream.map((_) => counts[productId] ?? 0);
  }
}

/// Recent searches kept in memory.
class FakeRecentSearchRepository implements RecentSearchRepository {
  FakeRecentSearchRepository([List<String>? terms]) : terms = [...?terms];
  final List<String> terms;
  final _changes = StreamController<void>.broadcast();

  @override
  Stream<List<String>> watch(String me) async* {
    yield [...terms];
    yield* _changes.stream.map((_) => [...terms]);
  }

  @override
  Future<void> add(String me, String term, {Map<String, Object?>? filters}) async {
    final t = term.trim();
    if (t.isEmpty) return;
    terms
      ..removeWhere((x) => x.toLowerCase() == t.toLowerCase())
      ..insert(0, t);
    if (terms.length > recentSearchLimit) terms.removeRange(recentSearchLimit, terms.length);
    _changes.add(null);
  }

  @override
  Future<void> remove(String me, String term) async {
    terms.removeWhere((x) => x.toLowerCase() == term.toLowerCase());
    _changes.add(null);
  }

  @override
  Future<void> clear(String me) async {
    terms.clear();
    _changes.add(null);
  }
}

/// Verified Maker applications kept in memory. [mine] is the demo user's own
/// status; [applications] is what admins see.
class FakeVerificationRepository implements VerificationRepository {
  FakeVerificationRepository({MyVerification? mine, List<VerificationApplication>? applications})
      : mine = mine ??
            MyVerification(
              status: VerificationStatus.verified,
              idType: 'PhilSys National ID',
              submittedAt: DateTime(2026, 10, 14),
              verifiedAt: DateTime(2026, 10, 15),
              idPurgeDate: DateTime(2026, 11, 14),
            ),
        applications = applications ?? [sampleApplication];

  static final sampleApplication = VerificationApplication(
    sellerId: 'seller-layerlab',
    storeName: 'LayerLab PH',
    ownerName: 'Paolo Santos',
    username: 'layerlab.ph',
    city: 'Makati City',
    storeDescription: 'Small 3D-printed gifts, planters and keychains.',
    status: VerificationStatus.pending,
    submittedAt: DateTime(2026, 11, 15, 9, 30),
    idType: "Driver's License",
    idImagePath: 'seller-layerlab/verification/id_1.jpg',
    portfolio: const ['seller-layerlab/verification/portfolio1_1.jpg', 'seller-layerlab/verification/portfolio2_1.jpg'],
  );

  MyVerification mine;
  final List<VerificationApplication> applications;

  /// When set, every call fails with this (for testing error messages).
  AppFailure? failWith;

  Future<void> _check() async {
    await Future<void>.delayed(const Duration(milliseconds: 10));
    final f = failWith;
    if (f != null) throw f;
  }

  @override
  Future<MyVerification> loadMine() async {
    await _check();
    return mine;
  }

  @override
  Future<void> submit({required String idType, required PickedImage id, required List<PickedImage> portfolio}) async {
    await _check();
    if (!mine.status.canApply) throw const AppFailure('Your documents are already being reviewed.');
    if (portfolio.length < 2 || portfolio.length > 6) throw const AppFailure('Add 2 to 6 photos of your work.');
    final now = DateTime.now();
    final me = FakeAuthRepository.demoUser;
    final paths = [for (var i = 0; i < portfolio.length; i++) '${me.id}/verification/portfolio${i + 1}.jpg'];
    mine = MyVerification(status: VerificationStatus.pending, idType: idType, submittedAt: now, idOnFile: true, portfolio: paths);
    applications
      ..removeWhere((a) => a.sellerId == me.id)
      ..add(VerificationApplication(
        sellerId: me.id,
        storeName: me.username,
        ownerName: me.displayName,
        username: me.username,
        city: me.location,
        status: VerificationStatus.pending,
        submittedAt: now,
        idType: idType,
        idImagePath: '${me.id}/verification/id.jpg',
        portfolio: paths,
      ));
  }

  @override
  Future<List<VerificationApplication>> loadQueue({bool pending = true}) async {
    await _check();
    return [for (final a in applications) if ((a.status == VerificationStatus.pending) == pending) a];
  }

  @override
  Future<void> review({required String sellerId, required bool approve, String? note}) async {
    await _check();
    final i = applications.indexWhere((a) => a.sellerId == sellerId && a.status == VerificationStatus.pending);
    if (i < 0) throw const AppFailure('This application was already reviewed. Refresh the list.');
    if (!approve && (note ?? '').trim().length < 5) throw const AppFailure('Tell the maker why the application was not approved.');
    final a = applications[i];
    final now = DateTime.now();
    final purge = DateTime(now.year, now.month, now.day + idRetentionDays);
    final status = approve ? VerificationStatus.verified : VerificationStatus.rejected;
    final reason = approve ? null : note!.trim();
    applications[i] = VerificationApplication(
      sellerId: a.sellerId,
      storeName: a.storeName,
      ownerName: a.ownerName,
      username: a.username,
      city: a.city,
      storeDescription: a.storeDescription,
      status: status,
      submittedAt: a.submittedAt,
      idType: a.idType,
      idImagePath: a.idImagePath,
      portfolio: a.portfolio,
      reviewNote: reason,
      verifiedAt: approve ? now : null,
      idPurgeDate: purge,
    );
    if (sellerId == FakeAuthRepository.demoUser.id) {
      mine = MyVerification(
        status: status,
        idType: a.idType,
        submittedAt: a.submittedAt,
        verifiedAt: approve ? now : null,
        reviewNote: reason,
        idPurgeDate: purge,
        idOnFile: true,
        portfolio: a.portfolio,
      );
    }
  }
}

/// Reports kept in memory. Order details come from [orders] when given.
class FakeDisputeRepository implements DisputeRepository {
  FakeDisputeRepository({this.orders, List<Dispute>? disputes}) : disputes = disputes ?? [];
  final FakeOrderRepository? orders;
  final List<Dispute> disputes;
  int _next = 1;

  /// When set, every call fails with this (for testing error messages).
  AppFailure? failWith;

  Future<void> _check() async {
    await Future<void>.delayed(const Duration(milliseconds: 10));
    final f = failWith;
    if (f != null) throw f;
  }

  void _put(Dispute d) {
    final i = disputes.indexWhere((x) => x.id == d.id);
    if (i < 0) {
      disputes.add(d);
    } else {
      disputes[i] = d;
    }
  }

  Dispute _copy(Dispute d, {DisputeStatus? status, String? resolution, DateTime? resolvedAt, String? resolvedBy, List<DisputeEvidence>? evidence, String? myRole}) => Dispute(
        id: d.id, orderId: d.orderId, orderNumber: d.orderNumber, reason: d.reason, status: status ?? d.status, openedAt: d.openedAt,
        openedByBuyer: d.openedByBuyer, openedByMe: d.openedByMe, myRole: myRole ?? d.myRole, orderStatus: d.orderStatus, orderTotal: d.orderTotal,
        isCustom: d.isCustom, buyerName: d.buyerName, buyerUsername: d.buyerUsername, storeName: d.storeName,
        resolution: resolution ?? d.resolution, resolvedAt: resolvedAt ?? d.resolvedAt, resolvedBy: resolvedBy ?? d.resolvedBy,
        quoteVersion: d.quoteVersion, quotePrice: d.quotePrice, quoteReadyBy: d.quoteReadyBy, payments: d.payments, evidence: evidence ?? d.evidence,
      );

  List<DisputeEvidence> _evidence(List<PickedImage> photos, {required bool byBuyer, String? note}) => [
        for (var i = 0; i < photos.length; i++)
          DisputeEvidence(path: 'me/dispute_${_next}_$i.jpg', byBuyer: byBuyer, byMe: true, uploadedAt: DateTime.now(), description: note),
      ];

  @override
  Future<Dispute?> forOrder(String orderId) async {
    await _check();
    return disputes.where((d) => d.orderId == orderId).lastOrNull;
  }

  @override
  Future<Dispute> open({required String orderId, required String reason, List<PickedImage> photos = const [], String? note}) async {
    await _check();
    if (disputes.any((d) => d.orderId == orderId && d.status.isActive)) {
      throw const AppFailure('This order already has an open report. Add your photos to it instead.');
    }
    if (reason.trim().length < 15) throw const AppFailure('Describe the problem in at least 15 characters.');
    if (photos.length > 5) throw const AppFailure('Add at most 5 photos at a time.');
    final o = orders?.orders.where((x) => x.id == orderId).firstOrNull;
    final buyer = o == null || o.side == ChatSide.buying;
    final d = Dispute(
      id: 'd-${_next++}',
      orderId: orderId,
      orderNumber: o?.number ?? orderId,
      reason: reason.trim(),
      status: DisputeStatus.open,
      openedAt: DateTime.now(),
      openedByBuyer: buyer,
      openedByMe: true,
      myRole: buyer ? 'buyer' : 'seller',
      orderTotal: o?.total ?? 0,
      isCustom: o?.isCustom ?? false,
      storeName: buyer ? (o?.counterpart ?? '') : FakeAuthRepository.demoUser.username,
      buyerName: buyer ? FakeAuthRepository.demoUser.displayName : o.counterpart,
      evidence: _evidence(photos, byBuyer: buyer, note: note),
    );
    _put(d);
    return d;
  }

  @override
  Future<Dispute> addEvidence({required Dispute dispute, required List<PickedImage> photos, String? note}) async {
    await _check();
    final d = disputes.firstWhere((x) => x.id == dispute.id);
    if (!d.status.isActive) throw const AppFailure('This report is already closed.');
    if (photos.isEmpty) throw const AppFailure('Add at least one photo.');
    final updated = _copy(d, evidence: [...d.evidence, ..._evidence(photos, byBuyer: d.myRole != 'seller', note: note)]);
    _put(updated);
    return updated;
  }

  @override
  Future<List<Dispute>> queue({bool active = true}) async {
    await _check();
    return [for (final d in disputes) if (d.status.isActive == active) _copy(d, myRole: 'admin')];
  }

  @override
  Future<Dispute> update({required String disputeId, required String status, String? resolution}) async {
    await _check();
    final d = disputes.firstWhere((x) => x.id == disputeId);
    if (!d.status.isActive) throw const AppFailure('This report was already decided. Refresh the list.');
    final next = disputeStatusFromDb(status);
    if (next != DisputeStatus.underReview && (resolution ?? '').trim().length < 10) {
      throw const AppFailure('Write the decision for both sides (at least 10 characters).');
    }
    final updated = next == DisputeStatus.underReview
        ? _copy(d, status: next, resolvedBy: 'CraftHive Admin')
        : _copy(d, status: next, resolution: resolution!.trim(), resolvedAt: DateTime.now(), resolvedBy: 'CraftHive Admin');
    _put(updated);
    return updated;
  }
}

/// Admin dashboard numbers and staff kept in memory.
class FakeAdminRepository implements AdminRepository {
  FakeAdminRepository({AdminDashboard? dashboard, List<StaffMember>? staff})
      : dashboard = dashboard ??
            AdminDashboard(
              myRole: 'superadmin',
              makersWaiting: 1,
              oldestWaitingAt: DateTime(2026, 11, 15, 9, 30),
              makersVerified: 5,
              approved7d: 1,
              idsOnFile: 2,
              idsDue7d: 1,
              idsDeleted30d: 3,
              disputesOpen: 0,
              stores: 7,
              staff: 2,
            ),
        staff = staff ??
            [
              const StaffMember(adminId: 'a-1', firstName: 'CraftHive', lastName: 'Admin', email: 'admin@crafthive.test', role: 'superadmin', isMe: true, decisions: 6),
              const StaffMember(adminId: 'a-2', firstName: 'Lea', lastName: 'Santos', email: 'lea@crafthive.test', role: 'moderator', decisions: 2),
            ];

  AdminDashboard dashboard;
  final List<StaffMember> staff;
  final invited = <String>[];

  /// When set, every call fails with this (for testing error messages).
  AppFailure? failWith;

  Future<void> _check() async {
    await Future<void>.delayed(const Duration(milliseconds: 10));
    final f = failWith;
    if (f != null) throw f;
  }

  StaffMember _with(StaffMember s, {String? role, bool? isActive}) => StaffMember(
        adminId: s.adminId, firstName: s.firstName, lastName: s.lastName, email: s.email, role: role ?? s.role,
        isActive: isActive ?? s.isActive, isMe: s.isMe, createdAt: s.createdAt, lastSignInAt: s.lastSignInAt, decisions: s.decisions,
      );

  bool get _amSuper => staff.any((s) => s.isMe && s.isSuperadmin);

  @override
  Future<AdminDashboard> loadDashboard() async {
    await _check();
    return dashboard;
  }

  @override
  Future<List<StaffMember>> loadStaff() async {
    await _check();
    return List.of(staff);
  }

  @override
  Future<void> invite({required String email, required String firstName, required String lastName, required String role}) async {
    await _check();
    if (!_amSuper) throw const AppFailure('Only a superadmin can manage staff accounts.');
    final e = email.trim().toLowerCase();
    if (staff.any((s) => s.email == e)) throw const AppFailure('This email is already a staff account.');
    if (e == FakeAuthRepository.demoUser.email) throw const AppFailure('This email belongs to a marketplace account. Use a separate work email for staff.');
    invited.add(e);
    staff.add(StaffMember(adminId: 'a-${staff.length + 1}', firstName: firstName.trim(), lastName: lastName.trim(), email: e, role: role, createdAt: DateTime.now()));
  }

  @override
  Future<void> setRole(String adminId, String role) async {
    await _check();
    if (!_amSuper) throw const AppFailure('Only a superadmin can change staff roles.');
    final i = staff.indexWhere((s) => s.adminId == adminId);
    if (staff[i].isSuperadmin && role != 'superadmin' && staff.where((s) => s.isSuperadmin && s.isActive).length <= 1) {
      throw const AppFailure('CraftHive needs at least one superadmin.');
    }
    staff[i] = _with(staff[i], role: role);
  }

  @override
  Future<void> setActive(String adminId, bool active) async {
    await _check();
    if (!_amSuper) throw const AppFailure('Only a superadmin can manage staff accounts.');
    final i = staff.indexWhere((s) => s.adminId == adminId);
    if (staff[i].isMe) throw const AppFailure("You can't deactivate your own account.");
    staff[i] = _with(staff[i], isActive: active);
  }
}

/// Report rows kept in memory, shaped like the database functions' JSON.
class FakeReportRepository implements ReportRepository {
  FakeReportRepository({Map<ReportKind, Object?>? rows, Map<String, int>? trust})
      : data = rows ?? sampleRows,
        trust = trust ?? const {SampleIds.storeNarra: 88, SampleIds.storePetal: 91, SampleIds.storeLayer: 64, 'store-me': 86};

  final Map<ReportKind, Object?> data;
  final Map<String, int> trust;
  final calls = <(ReportKind, ReportFilters)>[];

  /// When set, every call fails with this (for testing error messages).
  AppFailure? failWith;

  static final Map<ReportKind, Object?> sampleRows = {
    ReportKind.storeDirectory: [
      {'store_name': 'Petal & Twine', 'seller_username': 'petal.twine', 'store_description': 'Hand-tied bouquets.', 'address': '88 Maginhawa Street, Quezon City 1101',
       'category_count': 1, 'active_listings': 2, 'avg_rating': 4.9, 'items_sold': 305, 'verified_status': 'verified', 'archived': false},
      {'store_name': 'LayerLab PH', 'seller_username': 'layerlab.ph', 'store_description': '3D-printed gifts.', 'address': '201 Jupiter Street, Makati City 1209',
       'category_count': 1, 'active_listings': 2, 'avg_rating': null, 'items_sold': 0, 'verified_status': 'pending', 'archived': false},
    ],
    ReportKind.productListing: [
      {'product_title': 'Crochet Tote Bag', 'category_name': 'Crochet', 'store_name': 'ana.makes', 'price': 680, 'stock_quantity': 8, 'has_custom_option': true,
       'created_at': '2026-10-02T03:00:00Z', 'images': 3, 'reviews': 12, 'avg_rating': 4.9, 'status': 'active'},
    ],
    ReportKind.customRequests: [
      {'request_number': 'CR-1063', 'buyer_username': 'bea.lim', 'seller_username': 'ana.makes', 'store_name': 'ana.makes', 'product_title': 'Crochet Tote Bag',
       'quantity': 2, 'budget': 1500, 'needed_by': '2026-12-10', 'reference_photos': 2, 'status': 'accepted', 'created_at': '2026-11-02T01:00:00Z',
       'quotes': [
         {'version': 1, 'price': 1600, 'completion': '2026-12-05', 'status': 'superseded', 'created_at': '2026-11-03T01:00:00Z'},
         {'version': 2, 'price': 1450, 'completion': '2026-12-06', 'status': 'accepted', 'created_at': '2026-11-04T01:00:00Z'},
       ]},
    ],
    ReportKind.orderPayment: [
      {'order_number': 'CH-2026-001047', 'customer_name': 'Bea Lim', 'customer_username': 'bea.lim', 'store_name': 'ana.makes', 'order_date': '2026-11-12T02:00:00Z',
       'total': 680, 'status': 'confirmed', 'total_paid': 680,
       'items': [{'title': 'Crochet Tote Bag', 'quantity': 1, 'unit_price': 680}],
       'payments': [{'reference': 'GC7781234', 'amount': 680, 'status': 'verified', 'verified_at': '2026-11-12T05:00:00Z'}]},
    ],
    ReportKind.sellerReliability: [
      {'store_name': 'ana.makes', 'seller_username': 'ana.makes', 'from': '2026-08-19', 'to': '2026-11-17', 'completed': 18, 'cancelled': 1, 'on_time_rate': 0.94,
       'requests': 9, 'quotes_accepted': 6, 'conversion_rate': 0.6667, 'avg_rating': 4.9, 'disputes': 0, 'trust_score': 86},
    ],
    ReportKind.marketplaceActivity: [
      {'category_name': 'Crochet', 'from': '2026-08-19', 'to': '2026-11-17', 'listings': 4, 'orders': 21, 'custom_requests': 9, 'total_order_value': 14280,
       'verified_sellers': 1, 'avg_trust_score': 86},
      {'category_name': 'Flowers', 'from': '2026-08-19', 'to': '2026-11-17', 'listings': 2, 'orders': 33, 'custom_requests': 4, 'total_order_value': 18150,
       'verified_sellers': 1, 'avg_trust_score': 91},
    ],
  };

  Future<void> _check() async {
    await Future<void>.delayed(const Duration(milliseconds: 10));
    final f = failWith;
    if (f != null) throw f;
  }

  @override
  Future<Object?> rows(ReportKind kind, ReportFilters f) async {
    await _check();
    calls.add((kind, f));
    return data[kind] ?? const [];
  }

  @override
  Future<Map<String, int>> trustScores() async {
    await _check();
    return trust;
  }
}

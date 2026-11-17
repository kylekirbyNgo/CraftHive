import 'package:cloud_firestore/cloud_firestore.dart' show FirebaseFirestore;
import 'package:firebase_auth/firebase_auth.dart' show FirebaseAuth;
import 'package:firebase_database/firebase_database.dart' show FirebaseDatabase;
import 'package:firebase_messaging/firebase_messaging.dart' show FirebaseMessaging;
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show Supabase;

import '../core/config/firebase_config.dart';
import '../core/theme/app_colors.dart';
import '../shared/widgets/craft_icon.dart';
import 'models.dart';
import 'repositories/admin_repository.dart';
import 'repositories/auth_repository.dart';
import 'repositories/catalog_repository.dart';
import 'repositories/chat_repository.dart';
import 'repositories/custom_order_repository.dart';
import 'repositories/dispute_repository.dart';
import 'repositories/fake_repositories.dart';
import 'repositories/firebase_session.dart';
import 'repositories/listing_repository.dart';
import 'repositories/notification_repository.dart';
import 'repositories/order_repository.dart';
import 'repositories/presence_repository.dart';
import 'repositories/receipt_scanner.dart';
import 'repositories/report_repository.dart';
import 'repositories/recent_search_repository.dart';
import 'repositories/saved_repository.dart';
import 'repositories/verification_repository.dart';
import 'reports.dart';
import 'search.dart';

export 'repositories/auth_repository.dart' show AppFailure, AuthField, ProfileUpdate, SignUpData, SignUpOutcome;
export 'repositories/catalog_repository.dart' show CatalogData;
export 'repositories/custom_order_repository.dart' show CustomRequestInput;
export 'repositories/listing_repository.dart' show ListingInput, ListingPhoto, StoreInput;
export 'repositories/order_repository.dart' show PickedImage;
export 'repositories/firebase_session.dart' show PushBanner;
export 'repositories/receipt_scanner.dart' show ReceiptScan, formatReference;
export 'repositories/verification_repository.dart' show idRetentionDays;
export 'reports.dart';
export 'search.dart';

// ---------------------------------------------------------------------------
// Session (Supabase Auth). The session is kept on the phone, so the user stays
// logged in after closing the app.
// ---------------------------------------------------------------------------
final authRepositoryProvider = Provider<AuthRepository>((ref) => SupabaseAuthRepository(Supabase.instance.client));

/// The signed-in user's ID, or null when signed out.
final sessionProvider = StreamProvider<String?>((ref) => ref.watch(authRepositoryProvider).userIdChanges);

/// The signed-in user's profile row from the users table.
final profileProvider = FutureProvider<AppUser?>((ref) async {
  final userId = await ref.watch(sessionProvider.future);
  if (userId == null) return null;
  return ref.watch(authRepositoryProvider).loadProfile(userId);
});

enum AuthStatus { checking, signedOut, signedIn, profileError }

final authStatusProvider = Provider<AuthStatus>((ref) {
  final session = ref.watch(sessionProvider);
  if (!session.hasValue && !session.hasError) return AuthStatus.checking;
  if (session.valueOrNull == null) return AuthStatus.signedOut;
  final profile = ref.watch(profileProvider);
  if (profile.valueOrNull != null) return AuthStatus.signedIn;
  if (profile.hasError && !profile.isLoading) return AuthStatus.profileError;
  return AuthStatus.checking;
});

/// True after the user opened the password-reset link from their email: the
/// router shows "Choose a new password" until it is saved or cancelled.
final passwordRecoveryProvider = StateProvider<bool>((ref) => false);

class AuthController extends Notifier<AppUser?> {
  @override
  AppUser? build() => ref.watch(profileProvider).valueOrNull;

  AuthRepository get _repo => ref.read(authRepositoryProvider);

  /// Username or email + password. Throws [AppFailure] with a message to show.
  Future<void> logIn(String usernameOrEmail, String password) => _repo.logIn(usernameOrEmail, password);

  Future<SignUpOutcome> signUp(SignUpData data) => _repo.signUp(data);

  Future<void> sendPasswordResetLink(String email) => _repo.sendPasswordResetLink(email);

  Future<void> updatePassword(String newPassword) => _repo.updatePassword(newPassword);

  /// Shows profile changes right away (Open your store).
  void updateProfile(AppUser user) => state = user;

  /// Edit profile, all in one step: saves to USERS (and STORE), uploads the new
  /// photo, starts an email change (a confirmation link is sent to [newEmail]),
  /// and only then reloads the profile.
  ///
  /// Reloading the profile rebuilds this provider, and Riverpod does not allow
  /// using its ref until that rebuild is done, so nothing may run after it.
  /// The screen reloads the store cards (catalogDataProvider): that provider
  /// depends on this one, so invalidating it from here is a CircularDependencyError.
  Future<void> saveProfile(ProfileUpdate update, {PickedImage? photo, String? newEmail}) async {
    final repo = _repo;
    try {
      await repo.updateProfile(update);
      if (photo != null) await repo.uploadAvatar(photo.bytes, photo.fileName);
      if (newEmail != null) await repo.changeEmail(newEmail);
    } finally {
      // Also after an error: whatever was saved shows on the screens.
      await _reloadProfile();
    }
  }

  Future<void> _reloadProfile() async {
    try {
      await ref.refresh(profileProvider.future);
    } catch (_) {
      // Saved already; the profile reloads again on the next screen.
    }
  }

  Future<void> signOut() async {
    // While still signed in to Firebase: stop pushes to this phone and show me offline.
    // This step may never hold up signing out, whatever Firebase does.
    try {
      // My Firebase uid is my Supabase user ID. It is not read from firebaseUidProvider,
      // which depends on this provider (Riverpod would stop with a CircularDependencyError).
      await disconnectFirebase(ref, _repo.currentUserId).timeout(const Duration(seconds: 6));
    } catch (e) {
      debugPrint('Sign out: skipped the Firebase step ($e)');
    }
    try {
      await _repo.signOut();
    } catch (e) {
      // Offline: Supabase still clears the session on the phone, so the user is signed out.
      debugPrint('Sign out: $e');
    }
  }
}

final authProvider = NotifierProvider<AuthController, AppUser?>(AuthController.new);

// ---------------------------------------------------------------------------
// Catalog (PostgreSQL: CATEGORY, STORE, PRODUCT, PRODUCT_IMAGE, REVIEW)
// ---------------------------------------------------------------------------
final catalogRepositoryProvider = Provider<CatalogRepository>((ref) => SupabaseCatalogRepository(Supabase.instance.client));

/// Categories, stores and listings for the signed-in user. Reloads when the
/// account changes; Home's pull-to-refresh calls ref.refresh on it.
final catalogDataProvider = FutureProvider<CatalogData>((ref) async {
  final userId = ref.watch(authProvider.select((u) => u?.id));
  if (userId == null) return CatalogData.empty;
  return ref.watch(catalogRepositoryProvider).load(myUserId: userId);
});

final categoriesProvider = Provider<List<Category>>((ref) => ref.watch(catalogDataProvider).valueOrNull?.categories ?? const []);

/// All stores. The signed-in user's own store always has the id "me"; if they
/// have not opened one yet, a placeholder built from their profile is used.
final sellersProvider = Provider<List<Seller>>((ref) {
  final sellers = [...?ref.watch(catalogDataProvider).valueOrNull?.sellers];
  final user = ref.watch(authProvider);
  if (user != null && !sellers.any((s) => s.id == 'me')) {
    sellers.insert(
      0,
      Seller(
        id: 'me',
        name: user.username,
        initials: user.initials,
        color: AppColors.clay,
        location: user.location,
        isVerified: false,
        rating: 0,
        sold: 0,
        replyTime: 'a few hours',
        bio: user.bio,
        avatarUrl: user.avatarUrl,
      ),
    );
  }
  return sellers;
});

class CatalogController extends Notifier<List<Product>> {
  @override
  List<Product> build() => [...?ref.watch(catalogDataProvider).valueOrNull?.products];

  void add(Product p) => state = [p, ...state];

  void replace(Product p) => state = [for (final x in state) x.id == p.id ? p : x];
}

final catalogProvider = NotifierProvider<CatalogController, List<Product>>(CatalogController.new);

final productProvider = Provider.family<Product?, String>((ref, id) {
  for (final p in ref.watch(catalogProvider)) {
    if (p.id == id) return p;
  }
  return null;
});

final sellerProvider = Provider.family<Seller?, String>((ref, id) {
  for (final s in ref.watch(sellersProvider)) {
    if (s.id == id) return s;
  }
  return null;
});

const _unknownCategory = Category(id: '', name: 'Other', icon: CraftIcons.tag, tint: AppColors.lightSand, ink: AppColors.grayBrown);

final categoryProvider = Provider.family<Category, String>(
    (ref, id) => ref.watch(categoriesProvider).where((c) => c.id == id).firstOrNull ?? _unknownCategory);

// ---------------------------------------------------------------------------
// Selling (PostgreSQL: SELLER, STORE, PRODUCT, PRODUCT_IMAGE, PRODUCT_CUSTOM_OPTION;
// photos in the product-images Storage bucket)
// ---------------------------------------------------------------------------
final listingRepositoryProvider = Provider<ListingRepository>((ref) => SupabaseListingRepository(Supabase.instance.client));

/// The signed-in user's store_id, or null until they open a store (or while the catalog loads).
final myStoreIdProvider = Provider<String?>((ref) => ref.watch(catalogDataProvider).valueOrNull?.myStoreId);

/// Listings in my own store (seller id "me").
final myListingsProvider = Provider<List<Product>>(
    (ref) => ref.watch(catalogProvider).where((p) => p.sellerId == 'me' && p.status != ListingStatus.archived).toList());

// ---------------------------------------------------------------------------
// Per-user lists in Firestore: saved items (users/{uid}/savedItems, with save
// counts in productStats) and recent searches (users/{uid}/recentSearches).
// ---------------------------------------------------------------------------
final savedRepositoryProvider = Provider<SavedRepository>(
    (ref) => FirebaseConfig.ready ? FirestoreSavedRepository(FirebaseFirestore.instance) : FakeSavedRepository());

final savedDataProvider = StreamProvider<Set<String>>((ref) async* {
  final me = await ref.watch(firebaseUidProvider.future);
  if (me == null) {
    yield const <String>{};
    return;
  }
  yield* ref.watch(savedRepositoryProvider).watchSaved(me);
});

/// Saved product IDs. A tap on the heart shows at once; it is saved in the background.
class SavedController extends Notifier<Set<String>> {
  /// Taps not yet confirmed by Firestore: product ID → saved.
  final _pending = <String, bool>{};

  @override
  Set<String> build() {
    final out = {...?ref.watch(savedDataProvider).valueOrNull};
    _pending.forEach((id, saved) => saved ? out.add(id) : out.remove(id));
    return out;
  }

  /// Returns true when the item is now saved.
  bool toggle(String id) {
    final saved = !state.contains(id);
    _pending[id] = saved;
    state = saved ? {...state, id} : ({...state}..remove(id));
    _write(id, saved);
    return saved;
  }

  Future<void> _write(String id, bool saved) async {
    try {
      final me = await ref.read(firebaseUidProvider.future);
      if (me == null) throw const AppFailure('Please log in again.');
      await ref.read(savedRepositoryProvider).setSaved(me, id, saved);
      _pending.remove(id);
    } catch (_) {
      // Not saved: put the heart back the way it was.
      _pending.remove(id);
      ref.invalidateSelf();
    }
  }
}

final savedProvider = NotifierProvider<SavedController, Set<String>>(SavedController.new);

/// How many people saved a product (Firestore productStats/{productId}.saveCount).
final saveCountProvider = StreamProvider.autoDispose.family<int, String>((ref, productId) => ref.watch(savedRepositoryProvider).watchSaveCount(productId));

final recentSearchRepositoryProvider = Provider<RecentSearchRepository>(
    (ref) => FirebaseConfig.ready ? FirestoreRecentSearchRepository(FirebaseFirestore.instance) : FakeRecentSearchRepository());

final recentSearchDataProvider = StreamProvider<List<String>>((ref) async* {
  final me = await ref.watch(firebaseUidProvider.future);
  if (me == null) {
    yield const <String>[];
    return;
  }
  yield* ref.watch(recentSearchRepositoryProvider).watch(me);
});

/// Recent searches (Firestore users/{uid}/recentSearches), newest first.
/// Changes show at once and are saved in the background.
class RecentSearchController extends Notifier<List<String>> {
  @override
  List<String> build() => ref.watch(recentSearchDataProvider).valueOrNull ?? const [];

  Future<void> _write(Future<void> Function(RecentSearchRepository repo, String me) change) async {
    try {
      final me = await ref.read(firebaseUidProvider.future);
      if (me != null) await change(ref.read(recentSearchRepositoryProvider), me);
    } catch (_) {
      // Recent searches are a convenience: a failed save is not worth an error message.
    }
  }

  void add(String q, {SearchFilters? filters}) {
    final t = q.trim();
    if (t.isEmpty) return;
    state = [t, ...state.where((x) => x.toLowerCase() != t.toLowerCase())].take(recentSearchLimit).toList();
    final f = filters;
    _write((repo, me) => repo.add(me, t,
        filters: f == null ? null : recentSearchFilters(f)));
  }

  void remove(String q) {
    state = [for (final x in state) if (x != q) x];
    _write((repo, me) => repo.remove(me, q));
  }

  void clear() {
    state = const [];
    _write((repo, me) => repo.clear(me));
  }
}

final recentSearchProvider = NotifierProvider<RecentSearchController, List<String>>(RecentSearchController.new);

// ---------------------------------------------------------------------------
// Firebase connection. Login stays with Supabase; the firebase-bridge Edge
// Function signs the same user in to Firebase. Until FirebaseConfig is filled
// in (and in the automated tests) the in-memory sample versions are used.
// ---------------------------------------------------------------------------
final firebaseSessionProvider = Provider<FirebaseSession>(
    (ref) => FirebaseConfig.ready ? FirebaseAuthSession(FirebaseAuth.instance, Supabase.instance.client) : FakeFirebaseSession());

final chatRepositoryProvider = Provider<ChatRepository>(
    (ref) => FirebaseConfig.ready ? FirestoreChatRepository(FirebaseFirestore.instance, Supabase.instance.client) : FakeChatRepository());

final presenceRepositoryProvider = Provider<PresenceRepository>(
    (ref) => FirebaseConfig.ready ? RealtimePresenceRepository(FirebaseDatabase.instance) : FakePresenceRepository());

final notificationRepositoryProvider = Provider<NotificationRepository>(
    (ref) => FirebaseConfig.ready ? FirestoreNotificationRepository(FirebaseFirestore.instance) : FakeNotificationRepository());

final pushServiceProvider = Provider<PushService>(
    (ref) => FirebaseConfig.ready ? FcmPushService(FirebaseMessaging.instance, FirebaseFirestore.instance) : FakePushService());

/// My Firebase uid (the same as my Supabase user ID) once connected; null when signed out.
/// Errors (for example the Edge Function is not deployed) are [AppFailure]s;
/// ref.invalidate(firebaseUidProvider) tries again.
final firebaseUidProvider = FutureProvider<String?>((ref) async {
  final userId = ref.watch(authProvider.select((u) => u?.id));
  final session = ref.watch(firebaseSessionProvider);
  if (userId == null) {
    try {
      await session.disconnect();
    } catch (_) {}
    return null;
  }
  return firebaseGuard(() => session.connect(userId));
});

/// Called before signing out of Supabase, with my user ID (= my Firebase uid).
Future<void> disconnectFirebase(Ref ref, String? me) async {
  if (me == null) return;
  try {
    await Future.wait([
      ref.read(pushServiceProvider).unregister(me),
      ref.read(presenceRepositoryProvider).goOffline(me),
    ]).timeout(const Duration(seconds: 5));
  } catch (_) {
    // Offline: the Realtime Database marks me offline when the connection drops.
  }
}

// ---------------------------------------------------------------------------
// Messages (Firestore chats/{chatId} and chats/{chatId}/messages)
// ---------------------------------------------------------------------------
final chatsDataProvider = StreamProvider<List<ChatThread>>((ref) async* {
  final me = await ref.watch(firebaseUidProvider.future);
  if (me == null) {
    yield const [];
    return;
  }
  yield* ref.watch(chatRepositoryProvider).watchThreads(me);
});

final chatsProvider = Provider<List<ChatThread>>((ref) => ref.watch(chatsDataProvider).valueOrNull ?? const []);

final chatProvider = Provider.family<ChatThread?, String>((ref, id) => ref.watch(chatsProvider).where((t) => t.id == id).firstOrNull);

final chatMessagesProvider = StreamProvider.autoDispose.family<List<ChatMessage>, String>((ref, chatId) async* {
  final me = await ref.watch(firebaseUidProvider.future);
  if (me == null) {
    yield const [];
    return;
  }
  yield* ref.watch(chatRepositoryProvider).watchMessages(chatId, me);
});

final unreadCountProvider = Provider<int>((ref) => ref.watch(chatsProvider).fold(0, (sum, t) => sum + t.unread));

/// Online status of a user (Realtime Database /status/{uid}).
final onlineProvider = StreamProvider.autoDispose.family<bool, String>((ref, uid) => ref.watch(presenceRepositoryProvider).watchOnline(uid));

/// Whether [uid] is typing in a chat: key is (chatId, uid).
final typingProvider = StreamProvider.autoDispose.family<bool, (String, String)>(
    (ref, key) => ref.watch(presenceRepositoryProvider).watchTyping(key.$1, key.$2));

class ChatActions {
  ChatActions(this._ref);
  final Ref _ref;

  ChatRepository get _repo => _ref.read(chatRepositoryProvider);

  Future<String> _me() async {
    final me = await _ref.read(firebaseUidProvider.future);
    if (me == null) throw const AppFailure('Please log in again.');
    return me;
  }

  /// Message a store as a buyer. Returns the chat ID.
  Future<String> openWithStore(String storeId, {String? productId}) async =>
      _repo.open(await _me(), storeId: storeId, productId: productId);

  Future<String> openForOrder(Order o) async =>
      _repo.open(await _me(), orderId: o.id, productId: o.productId.isEmpty ? null : o.productId);

  Future<String> openForRequest(CustomRequest r) async =>
      _repo.open(await _me(), requestId: r.id, productId: r.productId.isEmpty ? null : r.productId);

  Future<void> send(ChatThread t, String text) async => _repo.sendText(await _me(), t, text);

  Future<void> sendPhoto(ChatThread t, PickedImage photo) async => _repo.sendPhoto(await _me(), t, photo);

  /// Never fails: a missed read mark only leaves the badge until next time.
  Future<void> markRead(String chatId) async {
    try {
      await _repo.markRead(await _me(), chatId);
    } catch (_) {}
  }

  Future<void> setTyping(String chatId, bool typing) async {
    final me = _ref.read(firebaseUidProvider).valueOrNull;
    if (me != null) await _ref.read(presenceRepositoryProvider).setTyping(chatId, me, typing);
  }
}

final chatActionsProvider = Provider<ChatActions>((ref) => ChatActions(ref));

/// Link to view a chat photo (private chat-photos bucket), valid for an hour.
final chatPhotoUrlProvider = FutureProvider.family<String, String>((ref, path) => ref.watch(chatRepositoryProvider).photoUrl(path));

// ---------------------------------------------------------------------------
// Custom requests (PostgreSQL: CUSTOM_REQUEST, CUSTOM_REQUEST_OPTION,
// CUSTOM_REQUEST_IMAGE, QUOTE)
// ---------------------------------------------------------------------------
final customOrderRepositoryProvider = Provider<CustomOrderRepository>((ref) => SupabaseCustomOrderRepository(Supabase.instance.client));

/// Requests I sent (buying) and requests for my store (selling). Reloads when
/// the account changes; the screens call [CustomOrderActions] to change them.
final requestsDataProvider = FutureProvider<List<CustomRequest>>((ref) async {
  final userId = ref.watch(authProvider.select((u) => u?.id));
  if (userId == null) return const [];
  return ref.watch(customOrderRepositoryProvider).loadRequests();
});

final requestsProvider = Provider<List<CustomRequest>>((ref) => ref.watch(requestsDataProvider).valueOrNull ?? const []);

final requestProvider = Provider.family<CustomRequest?, String>((ref, code) => ref.watch(requestsProvider).where((r) => r.code == code).firstOrNull);

/// Requests waiting for me: new ones for my store, or quotes I have not answered.
final requestsNeedingActionProvider = Provider<int>((ref) => ref.watch(requestsProvider).where((r) => r.needsMyAction).length);

/// Every change is saved in PostgreSQL first, then the lists are reloaded so
/// all screens show the database's state. Errors are thrown as [AppFailure].
class CustomOrderActions {
  CustomOrderActions(this._ref);
  final Ref _ref;

  CustomOrderRepository get _repo => _ref.read(customOrderRepositoryProvider);

  Future<void> _reload({bool orders = false}) async {
    _ref.invalidate(requestsDataProvider);
    if (orders) _ref.invalidate(ordersDataProvider);
    await _ref.read(requestsDataProvider.future);
    if (orders) await _ref.read(ordersDataProvider.future);
  }

  /// Returns the request number (CR-…).
  Future<String> submit(CustomRequestInput input) async {
    final code = await _repo.submitRequest(input);
    await _reload();
    return code;
  }

  Future<void> cancel(CustomRequest r) async {
    await _repo.cancelRequest(r);
    await _reload();
  }

  Future<void> sendQuote(CustomRequest r, {required double price, required DateTime readyBy, String? message}) async {
    await _repo.sendQuote(request: r, price: price, readyBy: readyBy, message: message);
    await _reload();
  }

  Future<void> decline(CustomRequest r, String reason) async {
    await _repo.declineRequest(request: r, reason: reason);
    await _reload();
  }

  /// Returns the new order number.
  Future<String> accept(QuoteOffer q) async {
    final number = await _repo.acceptQuote(q);
    await _reload(orders: true);
    return number;
  }

  Future<void> askForChanges(QuoteOffer q, String note) async {
    await _repo.requestChanges(q, note);
    await _reload();
  }
}

final customOrderActionsProvider = Provider<CustomOrderActions>((ref) => CustomOrderActions(ref));

// ---------------------------------------------------------------------------
// Orders (PostgreSQL: ORDERS, ORDER_ITEM, PAYMENT, ORDER_STATUS_HISTORY, REVIEW)
// ---------------------------------------------------------------------------
final orderRepositoryProvider = Provider<OrderRepository>((ref) => SupabaseOrderRepository(Supabase.instance.client));

final ordersDataProvider = FutureProvider<List<Order>>((ref) async {
  final userId = ref.watch(authProvider.select((u) => u?.id));
  if (userId == null) return const [];
  return ref.watch(orderRepositoryProvider).loadOrders();
});

final ordersProvider = Provider<List<Order>>((ref) => ref.watch(ordersDataProvider).valueOrNull ?? const []);

final orderProvider = Provider.family<Order?, String>((ref, number) => ref.watch(ordersProvider).where((o) => o.number == number).firstOrNull);

/// Signed link for a private photo (payment proof or reference photo); valid for an hour.
final privateImageUrlProvider = FutureProvider.family<String, String>((ref, path) => ref.watch(orderRepositoryProvider).privateImageUrl(path));

class OrderActions {
  OrderActions(this._ref);
  final Ref _ref;

  OrderRepository get _repo => _ref.read(orderRepositoryProvider);

  Future<void> _reload({bool catalog = false}) async {
    _ref.invalidate(ordersDataProvider);
    // Stock changes when an order is placed or cancelled, so listings reload too.
    if (catalog) _ref.invalidate(catalogDataProvider);
    await _ref.read(ordersDataProvider.future);
  }

  /// Buy now. Returns the order number.
  Future<String> place(Product p, int quantity) async {
    final number = await _repo.placeOrder(productId: p.id, quantity: quantity);
    await _reload(catalog: true);
    return number;
  }

  Future<void> submitPayment(Order o, {required String reference, required PickedImage proof}) async {
    await _repo.submitPayment(order: o, reference: reference, proof: proof);
    await _reload();
  }

  Future<void> reviewPayment(Order o, {required bool accept, String? reason}) async {
    await _repo.reviewPayment(order: o, accept: accept, reason: reason);
    await _reload();
  }

  Future<void> advance(Order o, OrderStatus to, {String? note}) async {
    final status = switch (to) {
      OrderStatus.inProduction => 'in_production',
      OrderStatus.shipped => 'shipped',
      // The buyer confirming receipt completes the order.
      OrderStatus.delivered => o.side == ChatSide.buying ? 'completed' : 'delivered',
      OrderStatus.cancelled => 'cancelled',
      _ => throw ArgumentError('Use reviewPayment to confirm an order.'),
    };
    await _repo.setStatus(order: o, status: status, note: note);
    await _reload(catalog: to == OrderStatus.cancelled);
  }

  Future<void> postReview(Order o, {required int rating, String? comment}) async {
    await _repo.postReview(order: o, rating: rating, comment: comment);
    await _reload(catalog: true);
  }
}

final orderActionsProvider = Provider<OrderActions>((ref) => OrderActions(ref));

/// Reads the reference number and amount from a payment screenshot (scan-receipt Edge Function, OCR.space).
final receiptScannerProvider = Provider<ReceiptScanner>((ref) => EdgeReceiptScanner(Supabase.instance.client));

// ---------------------------------------------------------------------------
// Notifications (Firestore notifications/{uid}/items, added by the Edge Function)
// ---------------------------------------------------------------------------
final noticesDataProvider = StreamProvider<List<AppNotice>>((ref) async* {
  final me = await ref.watch(firebaseUidProvider.future);
  if (me == null) {
    yield const [];
    return;
  }
  yield* ref.watch(notificationRepositoryProvider).watch(me);
});

final noticesProvider = Provider<List<AppNotice>>((ref) => ref.watch(noticesDataProvider).valueOrNull ?? const []);
final unreadNoticesProvider = Provider<int>((ref) => ref.watch(noticesProvider).where((n) => !n.read).length);

class NoticeActions {
  NoticeActions(this._ref);
  final Ref _ref;

  String? get _me => _ref.read(firebaseUidProvider).valueOrNull;

  Future<void> markRead(AppNotice n) async {
    final me = _me;
    if (me == null || n.read) return;
    try {
      await _ref.read(notificationRepositoryProvider).markRead(me, n.id);
    } catch (_) {}
  }

  Future<void> markAllRead() async {
    final me = _me;
    if (me == null) return;
    final ids = [for (final n in _ref.read(noticesProvider)) if (!n.read) n.id];
    await _ref.read(notificationRepositoryProvider).markAllRead(me, ids);
  }
}

final noticeActionsProvider = Provider<NoticeActions>((ref) => NoticeActions(ref));

// ---------------------------------------------------------------------------
// Verified Maker (SELLER verification; database/06_verified_maker.sql)
// ---------------------------------------------------------------------------
final verificationRepositoryProvider = Provider<VerificationRepository>((ref) => SupabaseVerificationRepository(Supabase.instance.client));

/// The signed-in maker's verification (null for admins and signed-out users).
final myVerificationProvider = FutureProvider<MyVerification?>((ref) async {
  final user = ref.watch(authProvider);
  if (user == null || user.isAdmin) return null;
  return ref.watch(verificationRepositoryProvider).loadMine();
});

/// Admin: pending applications (true) or reviewed ones (false).
final verificationQueueProvider = FutureProvider.family<List<VerificationApplication>, bool>((ref, pending) async {
  final user = ref.watch(authProvider);
  if (user == null || !user.isAdmin) return const [];
  return ref.watch(verificationRepositoryProvider).loadQueue(pending: pending);
});

class VerificationActions {
  VerificationActions(this._ref);
  final Ref _ref;
  VerificationRepository get _repo => _ref.read(verificationRepositoryProvider);

  Future<void> submit({required String idType, required PickedImage id, required List<PickedImage> portfolio}) async {
    await _repo.submit(idType: idType, id: id, portfolio: portfolio);
    _ref.invalidate(myVerificationProvider);
  }

  Future<void> review({required String sellerId, required bool approve, String? note}) async {
    try {
      await _repo.review(sellerId: sellerId, approve: approve, note: note);
    } finally {
      _ref
        ..invalidate(verificationQueueProvider(true))
        ..invalidate(verificationQueueProvider(false))
        ..invalidate(adminDashboardProvider);
    }
  }
}

final verificationActionsProvider = Provider<VerificationActions>(VerificationActions.new);

// ---------------------------------------------------------------------------
// Disputes ("Report a problem"; database/12_disputes.sql)
// ---------------------------------------------------------------------------
final disputeRepositoryProvider = Provider<DisputeRepository>((ref) => SupabaseDisputeRepository(Supabase.instance.client));

/// The latest report on an order (by order_id), or null.
final orderDisputeProvider = FutureProvider.family<Dispute?, String>((ref, orderId) async {
  if (ref.watch(authProvider) == null || orderId.isEmpty) return null;
  return ref.watch(disputeRepositoryProvider).forOrder(orderId);
});

/// Admin: open and under-review reports (true) or decided ones (false).
final disputeQueueProvider = FutureProvider.family<List<Dispute>, bool>((ref, active) async {
  final user = ref.watch(authProvider);
  if (user == null || !user.isAdmin) return const [];
  return ref.watch(disputeRepositoryProvider).queue(active: active);
});

class DisputeActions {
  DisputeActions(this._ref);
  final Ref _ref;
  DisputeRepository get _repo => _ref.read(disputeRepositoryProvider);

  Future<Dispute> open({required String orderId, required String reason, List<PickedImage> photos = const [], String? note}) async {
    final d = await _repo.open(orderId: orderId, reason: reason, photos: photos, note: note);
    _ref.invalidate(orderDisputeProvider(orderId));
    return d;
  }

  Future<void> addEvidence(Dispute d, List<PickedImage> photos, {String? note}) async {
    await _repo.addEvidence(dispute: d, photos: photos, note: note);
    _ref
      ..invalidate(orderDisputeProvider(d.orderId))
      ..invalidate(disputeQueueProvider(true));
  }

  /// Admin: 'under_review', 'resolved' or 'closed'.
  Future<void> update(Dispute d, String status, {String? resolution}) async {
    try {
      await _repo.update(disputeId: d.id, status: status, resolution: resolution);
    } finally {
      _ref
        ..invalidate(disputeQueueProvider(true))
        ..invalidate(disputeQueueProvider(false))
        ..invalidate(orderDisputeProvider(d.orderId))
        ..invalidate(adminDashboardProvider);
    }
  }
}

final disputeActionsProvider = Provider<DisputeActions>(DisputeActions.new);

// ---------------------------------------------------------------------------
// Admin dashboard and staff accounts (database/13_admin_dashboard.sql)
// ---------------------------------------------------------------------------
final adminRepositoryProvider = Provider<AdminRepository>((ref) => SupabaseAdminRepository(Supabase.instance.client));

final adminDashboardProvider = FutureProvider<AdminDashboard?>((ref) async {
  final user = ref.watch(authProvider);
  if (user == null || !user.isAdmin) return null;
  return ref.watch(adminRepositoryProvider).loadDashboard();
});

final staffProvider = FutureProvider<List<StaffMember>>((ref) async {
  final user = ref.watch(authProvider);
  if (user == null || !user.isAdmin) return const [];
  return ref.watch(adminRepositoryProvider).loadStaff();
});

class AdminActions {
  AdminActions(this._ref);
  final Ref _ref;
  AdminRepository get _repo => _ref.read(adminRepositoryProvider);

  Future<void> invite({required String email, required String firstName, required String lastName, required String role}) async {
    await _repo.invite(email: email, firstName: firstName, lastName: lastName, role: role);
    _ref
      ..invalidate(staffProvider)
      ..invalidate(adminDashboardProvider);
  }

  Future<void> setRole(StaffMember s, String role) async {
    await _repo.setRole(s.adminId, role);
    _ref.invalidate(staffProvider);
  }

  Future<void> setActive(StaffMember s, bool active) async {
    await _repo.setActive(s.adminId, active);
    _ref
      ..invalidate(staffProvider)
      ..invalidate(adminDashboardProvider);
  }

  /// Pull-to-refresh on the dashboard: numbers and every queue.
  Future<void> refreshAll() async {
    _ref
      ..invalidate(verificationQueueProvider(true))
      ..invalidate(verificationQueueProvider(false))
      ..invalidate(disputeQueueProvider(true))
      ..invalidate(disputeQueueProvider(false))
      ..invalidate(adminDashboardProvider);
    await _ref.read(adminDashboardProvider.future);
  }
}

final adminActionsProvider = Provider<AdminActions>(AdminActions.new);

// ---------------------------------------------------------------------------
// Reports (database/14_reports.sql; Search and Browse is built here)
// ---------------------------------------------------------------------------
final reportRepositoryProvider = Provider<ReportRepository>((ref) => SupabaseReportRepository(Supabase.instance.client));

class ReportRunner {
  ReportRunner(this._ref);
  final Ref _ref;

  Future<ReportResult> run(ReportKind kind, ReportFilters f) async {
    final repo = _ref.read(reportRepositoryProvider);
    if (kind != ReportKind.searchBrowse) return reportFromRows(kind, await repo.rows(kind, f));
    final catalog = await _ref.read(catalogDataProvider.future);
    final myStore = catalog.myStoreId;
    return searchBrowseReport(
      products: _ref.read(catalogProvider),
      sellers: _ref.read(sellersProvider),
      categories: catalog.categories,
      filters: f,
      trust: await repo.trustScores(),
      storeIdOf: (id) => id == 'me' ? (myStore ?? id) : id,
    );
  }
}

final reportRunnerProvider = Provider<ReportRunner>(ReportRunner.new);

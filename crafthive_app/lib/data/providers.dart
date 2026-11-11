import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show Supabase;

import '../core/theme/app_colors.dart';
import '../core/utils/format.dart';
import '../shared/widgets/craft_icon.dart';
import 'mock_data.dart';
import 'models.dart';
import 'repositories/auth_repository.dart';
import 'repositories/catalog_repository.dart';
import 'repositories/custom_order_repository.dart';
import 'repositories/listing_repository.dart';
import 'repositories/order_repository.dart';
import 'sample_ids.dart';

export 'repositories/auth_repository.dart' show AppFailure, AuthField, SignUpData, SignUpOutcome;
export 'repositories/catalog_repository.dart' show CatalogData;
export 'repositories/custom_order_repository.dart' show CustomRequestInput;
export 'repositories/listing_repository.dart' show ListingInput, ListingPhoto, StoreInput;
export 'repositories/order_repository.dart' show PickedImage;

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

  /// Used by Edit profile (store module) to show changes right away.
  void updateProfile(AppUser user) => state = user;

  Future<void> signOut() async {
    try {
      await _repo.signOut();
    } on AppFailure {
      // Offline: Supabase still clears the session on the phone, so the user is signed out.
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

/// Search with the filters from the filter sheet (full-text search in PostgreSQL later).
class SearchFilters {
  const SearchFilters({this.query = '', this.categoryId, this.maxPrice = 2000, this.customOnly = false, this.inStockOnly = false, this.sort = SortBy.relevance});
  final String query;
  final String? categoryId;
  final double maxPrice;
  final bool customOnly;
  final bool inStockOnly;
  final SortBy sort;

  SearchFilters copyWith({String? query, String? categoryId, bool clearCategory = false, double? maxPrice, bool? customOnly, bool? inStockOnly, SortBy? sort}) =>
      SearchFilters(
        query: query ?? this.query,
        categoryId: clearCategory ? null : (categoryId ?? this.categoryId),
        maxPrice: maxPrice ?? this.maxPrice,
        customOnly: customOnly ?? this.customOnly,
        inStockOnly: inStockOnly ?? this.inStockOnly,
        sort: sort ?? this.sort,
      );

  int get activeCount => (maxPrice < 2000 ? 1 : 0) + (customOnly ? 1 : 0) + (inStockOnly ? 1 : 0);
}

enum SortBy { relevance, priceLow, priceHigh, rating }

List<Product> searchProducts(List<Product> all, List<Seller> sellers, SearchFilters f) {
  final q = f.query.trim().toLowerCase();
  var list = all.where((p) {
    // Published listings only; the user's own are included so they can find them too.
    if (p.status != ListingStatus.active) return false;
    if (f.categoryId != null && p.categoryId != f.categoryId) return false;
    if (p.price > f.maxPrice) return false;
    if (f.customOnly && !p.acceptsCustom) return false;
    if (f.inStockOnly && p.stock == 0) return false;
    if (q.isEmpty) return true;
    final seller = sellers.where((s) => s.id == p.sellerId).firstOrNull;
    return p.title.toLowerCase().contains(q) ||
        p.description.toLowerCase().contains(q) ||
        (seller?.name.toLowerCase().contains(q) ?? false) ||
        q.split(' ').every((w) => p.title.toLowerCase().contains(w) || p.description.toLowerCase().contains(w));
  }).toList();
  switch (f.sort) {
    case SortBy.priceLow:
      list.sort((a, b) => a.price.compareTo(b.price));
    case SortBy.priceHigh:
      list.sort((a, b) => b.price.compareTo(a.price));
    case SortBy.rating:
      list.sort((a, b) => b.rating.compareTo(a.rating));
    case SortBy.relevance:
      break;
  }
  return list;
}

// ---------------------------------------------------------------------------
// Per-user lists. Recent searches are kept on the phone per account
// (Firestore users/{uid}/recentSearches in the paper); saved items are still sample data.
// ---------------------------------------------------------------------------
class SavedController extends Notifier<Set<String>> {
  @override
  Set<String> build() => {SampleIds.p2, SampleIds.p5, SampleIds.p9};

  bool toggle(String id) {
    final saved = !state.contains(id);
    state = saved ? {...state, id} : ({...state}..remove(id));
    return saved;
  }
}

final savedProvider = NotifierProvider<SavedController, Set<String>>(SavedController.new);

class RecentSearchController extends Notifier<List<String>> {
  static const _max = 10;
  String _key = '';

  @override
  List<String> build() {
    final userId = ref.watch(authProvider.select((u) => u?.id));
    if (userId == null) return const [];
    _key = 'recent_searches_$userId';
    _load(_key);
    return const [];
  }

  Future<void> _load(String key) async {
    try {
      final saved = (await SharedPreferences.getInstance()).getStringList(key) ?? const [];
      if (key == _key && state.isEmpty) state = saved;
    } catch (_) {
      // Storage unavailable: keep the list for this session only.
    }
  }

  Future<void> _save() async {
    try {
      await (await SharedPreferences.getInstance()).setStringList(_key, state);
    } catch (_) {}
  }

  void add(String q) {
    final t = q.trim();
    if (t.isEmpty || _key.isEmpty) return;
    state = [t, ...state.where((x) => x.toLowerCase() != t.toLowerCase())].take(_max).toList();
    _save();
  }

  void remove(String q) {
    state = [for (final x in state) if (x != q) x];
    _save();
  }

  void clear() {
    state = const [];
    _save();
  }
}

final recentSearchProvider = NotifierProvider<RecentSearchController, List<String>>(RecentSearchController.new);

// ---------------------------------------------------------------------------
// Messages (Firestore chats/{chatId}/messages)
// ---------------------------------------------------------------------------
class ChatController extends Notifier<List<ChatThread>> {
  @override
  List<ChatThread> build() => [...MockData.threads];

  ChatThread? byId(String id) => state.where((t) => t.id == id).firstOrNull;

  void send(String threadId, String text) {
    state = [
      for (final t in state)
        if (t.id == threadId)
          t.copyWith(messages: [...t.messages, ChatMessage(fromMe: true, text: text, time: Fmt.timeNow())], lastTime: Fmt.timeNow())
        else
          t,
    ];
  }

  void markRead(String threadId) {
    state = [for (final t in state) t.id == threadId ? t.copyWith(unread: 0) : t];
  }

  void setQuoteStatus(String threadId, QuoteStatus status) {
    state = [
      for (final t in state)
        if (t.id == threadId)
          t.copyWith(
            tag: status == QuoteStatus.accepted ? const StatusTag('Custom · Confirmed', Tone.success) : const StatusTag('Custom · Changes asked', Tone.warning),
            messages: [
              for (final m in t.messages)
                if (m.kind == MessageKind.quote) ChatMessage(fromMe: m.fromMe, text: m.text, time: m.time, kind: m.kind, quote: m.quote!.copyWith(status: status)) else m,
              ChatMessage(
                fromMe: true,
                time: Fmt.timeNow(),
                text: status == QuoteStatus.accepted ? 'I confirmed the order. I\'ll send the payment proof shortly.' : 'Could we change a few details before I confirm?',
              ),
            ],
          )
        else
          t,
    ];
  }

  /// Seller replies to a custom request with a price quote.
  void sendQuote(String threadId, Quote quote, String note) {
    state = [
      for (final t in state)
        if (t.id == threadId)
          t.copyWith(
            tag: const StatusTag('Custom · Quoted', Tone.info),
            lastTime: Fmt.timeNow(),
            messages: [
              ...t.messages,
              if (note.trim().isNotEmpty) ChatMessage(fromMe: true, text: note.trim(), time: Fmt.timeNow()),
              ChatMessage(fromMe: true, text: '', time: Fmt.timeNow(), kind: MessageKind.quote, quote: quote),
            ],
          )
        else
          t,
    ];
  }

  /// "Buy now" opens (or creates) a chat with the seller about this product.
  String openForProduct(Product p, Seller s, {String? note}) {
    final existing = state.where((t) => t.side == ChatSide.buying && t.sellerId == s.id).firstOrNull;
    if (existing != null) {
      state = [for (final t in state) t.id == existing.id ? ChatThread(
        id: t.id, side: t.side, name: t.name, initials: t.initials, color: t.color, messages: t.messages, tag: t.tag,
        sellerId: t.sellerId, productId: p.id, productNote: note ?? 'you tapped Buy now', unread: t.unread, isOnline: t.isOnline, lastTime: t.lastTime) : t];
      return existing.id;
    }
    final id = 't-${s.id}-${p.id}';
    state = [
      ChatThread(
        id: id, side: ChatSide.buying, name: s.name, initials: s.initials, color: s.color, sellerId: s.id, productId: p.id,
        productNote: note ?? 'you tapped Buy now', isOnline: s.isOnline, lastTime: Fmt.timeNow(), tag: const StatusTag('Buying', Tone.neutral),
        messages: [ChatMessage(fromMe: false, text: 'You asked about ${p.title} · ${Fmt.peso(p.price)}', time: '', kind: MessageKind.system)],
      ),
      ...state,
    ];
    return id;
  }
}

final chatsProvider = NotifierProvider<ChatController, List<ChatThread>>(ChatController.new);

final unreadCountProvider = Provider<int>((ref) => ref.watch(chatsProvider).fold(0, (sum, t) => sum + t.unread));

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

// ---------------------------------------------------------------------------
// Notifications (Firestore users/{uid}/notifications)
// ---------------------------------------------------------------------------
class NoticeController extends Notifier<List<AppNotice>> {
  @override
  List<AppNotice> build() => [...MockData.notices];
  void markAllRead() => state = [for (final n in state) n.markRead()];
  void markRead(int i) => state = [for (var k = 0; k < state.length; k++) k == i ? state[k].markRead() : state[k]];
}

final noticesProvider = NotifierProvider<NoticeController, List<AppNotice>>(NoticeController.new);
final unreadNoticesProvider = Provider<int>((ref) => ref.watch(noticesProvider).where((n) => !n.read).length);

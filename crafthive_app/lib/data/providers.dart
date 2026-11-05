import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/utils/format.dart';
import 'mock_data.dart';
import 'models.dart';

// ---------------------------------------------------------------------------
// Session (Firebase Authentication in Milestone 3)
// ---------------------------------------------------------------------------
class AuthController extends Notifier<AppUser?> {
  @override
  AppUser? build() => null;

  /// Mock login: any username/email with a password of 8+ characters works.
  Future<void> logIn(String id, String password) async {
    await Future<void>.delayed(const Duration(milliseconds: 600));
    if (password.length < 8) throw Exception('Wrong username or password.');
    state = MockData.demoUser;
  }

  Future<void> signUp({
    required String email,
    required String phone,
    required String country,
    required String sex,
    required String username,
  }) async {
    await Future<void>.delayed(const Duration(milliseconds: 700));
    state = AppUser(username: username, email: email, phone: phone, country: country, sex: sex, displayName: username, location: country);
  }

  void updateProfile(AppUser user) => state = user;

  void signOut() => state = null;
}

final authProvider = NotifierProvider<AuthController, AppUser?>(AuthController.new);

// ---------------------------------------------------------------------------
// Catalog (PostgreSQL: PRODUCT, CATEGORY, SELLER)
// ---------------------------------------------------------------------------
final categoriesProvider = Provider<List<Category>>((ref) => MockData.categories);
final sellersProvider = Provider<List<Seller>>((ref) => MockData.sellers);

class CatalogController extends Notifier<List<Product>> {
  @override
  List<Product> build() => [...MockData.products];

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

final categoryProvider = Provider.family<Category, String>((ref, id) =>
    ref.watch(categoriesProvider).firstWhere((c) => c.id == id, orElse: () => ref.watch(categoriesProvider).first));

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
    if (p.status != ListingStatus.active || p.sellerId == 'me') return false;
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
// Per-user lists (Firestore users/{uid}/savedItems and recentSearches)
// ---------------------------------------------------------------------------
class SavedController extends Notifier<Set<String>> {
  @override
  Set<String> build() => {'p2', 'p5', 'p9'};

  bool toggle(String id) {
    final saved = !state.contains(id);
    state = saved ? {...state, id} : ({...state}..remove(id));
    return saved;
  }
}

final savedProvider = NotifierProvider<SavedController, Set<String>>(SavedController.new);

class RecentSearchController extends Notifier<List<String>> {
  @override
  List<String> build() => [...MockData.recentSearches];

  void add(String q) {
    final t = q.trim();
    if (t.isEmpty) return;
    state = [t, ...state.where((x) => x.toLowerCase() != t.toLowerCase())].take(10).toList();
  }

  void clear() => state = [];
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
// Custom requests (PostgreSQL: CUSTOM_REQUEST, QUOTE)
// ---------------------------------------------------------------------------
class RequestController extends Notifier<List<CustomRequest>> {
  @override
  List<CustomRequest> build() => [
        CustomRequest(code: 'CR-1042', productId: 'p1', description: 'Engrave "Lola Nena" on the handle in cursive. Make a set of 3 in small, medium and large.',
            options: const ['Engraving', 'Size'], quantity: 3, budget: 1200, neededBy: DateTime(2026, 12, 18), sentAt: DateTime(2026, 10, 31, 14, 5), status: RequestStatus.accepted),
      ];

  CustomRequest submit({required String productId, required String description, required List<String> options, required int quantity, required DateTime neededBy, double? budget}) {
    final r = CustomRequest(
      code: 'CR-${1052 + state.length}',
      productId: productId,
      description: description,
      options: options,
      quantity: quantity,
      budget: budget,
      neededBy: neededBy,
      sentAt: DateTime.now(),
    );
    state = [r, ...state];
    return r;
  }
}

final requestsProvider = NotifierProvider<RequestController, List<CustomRequest>>(RequestController.new);

final requestProvider = Provider.family<CustomRequest?, String>((ref, code) => ref.watch(requestsProvider).where((r) => r.code == code).firstOrNull);

// ---------------------------------------------------------------------------
// Orders (PostgreSQL: ORDERS, STATUS_HISTORY, PAYMENT)
// ---------------------------------------------------------------------------
class OrderController extends Notifier<List<Order>> {
  @override
  List<Order> build() => [...MockData.orders];

  void advance(String number, OrderStatus to, {String? note}) {
    state = [
      for (final o in state)
        if (o.number == number) o.copyWith(status: to, history: [...o.history, OrderEvent(to, Fmt.stamp(DateTime.now()), note)]) else o,
    ];
  }

  void uploadProof(String number, String ref) {
    state = [
      for (final o in state)
        if (o.number == number)
          o.copyWith(paymentRef: ref, history: [...o.history, OrderEvent(o.status, Fmt.stamp(DateTime.now()), 'Payment proof uploaded (GCash ref $ref).')])
        else
          o,
    ];
  }
}

final ordersProvider = NotifierProvider<OrderController, List<Order>>(OrderController.new);

final orderProvider = Provider.family<Order?, String>((ref, number) => ref.watch(ordersProvider).where((o) => o.number == number).firstOrNull);

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

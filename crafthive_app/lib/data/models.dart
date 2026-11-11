import 'package:flutter/material.dart';

/// Plain data classes used by the UI. Catalog and account data are filled from
/// PostgreSQL (Supabase), including orders and custom requests; chats and
/// notifications still use sample data.

class AppUser {
  const AppUser({
    this.id = '',
    required this.username,
    required this.email,
    required this.phone,
    required this.country,
    required this.sex,
    required this.displayName,
    this.bio = '',
    this.location = '',
    this.isVerified = false,
  });

  /// Supabase Auth user ID (users.user_id). Empty for the offline sample user.
  final String id;
  final String username;
  final String email;
  final String phone;
  final String country;
  final String sex;
  final String displayName;
  final String bio;
  final String location;
  final bool isVerified;

  String get initials {
    final parts = displayName.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return username.isEmpty ? '?' : username.substring(0, username.length >= 2 ? 2 : 1).toUpperCase();
    if (parts.length == 1) return parts.first.substring(0, parts.first.length >= 2 ? 2 : 1).toUpperCase();
    return (parts.first[0] + parts.last[0]).toUpperCase();
  }

  String get firstName => displayName.split(' ').first;

  AppUser copyWith({String? displayName, String? bio, String? location, String? phone, String? email, bool? isVerified}) => AppUser(
        id: id,
        username: username,
        email: email ?? this.email,
        phone: phone ?? this.phone,
        country: country,
        sex: sex,
        displayName: displayName ?? this.displayName,
        bio: bio ?? this.bio,
        location: location ?? this.location,
        isVerified: isVerified ?? this.isVerified,
      );
}

class Category {
  const Category({required this.id, required this.name, required this.icon, required this.tint, required this.ink});
  final String id;
  final String name;
  final String icon; // CraftIcons path data
  final Color tint; // tile background
  final Color ink; // icon colour
}

class Seller {
  const Seller({
    required this.id,
    required this.name,
    required this.initials,
    required this.color,
    required this.location,
    required this.isVerified,
    required this.rating,
    required this.sold,
    required this.replyTime,
    required this.bio,
    this.isOnline = false,
  });

  final String id;
  final String name;
  final String initials;
  final Color color;
  final String location;
  final bool isVerified;
  final double rating;
  final int sold;
  final String replyTime;
  final String bio;
  final bool isOnline;
}

enum ListingStatus { active, hidden, archived }

class Product {
  const Product({
    required this.id,
    required this.title,
    required this.sellerId,
    required this.categoryId,
    required this.price,
    required this.description,
    this.rating = 0,
    this.sold = 0,
    this.stock = 0,
    this.leadDays = 0,
    this.acceptsCustom = false,
    this.customOptions = const [],
    this.customNote,
    this.photoCount = 3,
    this.isFeatured = false,
    this.status = ListingStatus.active,
    this.imageUrls = const [],
    this.imagePaths = const [],
    this.reviewCount = 0,
  });

  final String id;
  final String title;
  final String sellerId;
  final String categoryId;
  final double price;
  final String description;
  final double rating;
  final int sold;
  final int stock;
  final int leadDays;
  final bool acceptsCustom;
  final List<String> customOptions;
  final String? customNote;
  final int photoCount;
  final bool isFeatured;
  final ListingStatus status;

  /// Public photo links from Supabase Storage, cover first. Empty means the
  /// category placeholder is shown.
  final List<String> imageUrls;

  /// The same photos as Storage paths (product_image.image_path), in the same
  /// order as [imageUrls]. Edit listing needs them to keep or remove photos.
  final List<String> imagePaths;
  final int reviewCount;

  bool get isSoldOut => stock == 0 && leadDays == 0;
  bool get isLowStock => stock > 0 && stock <= 3;
  bool get isMadeToOrder => stock == 0 && leadDays > 0;

  Product copyWith({ListingStatus? status, int? stock, double? price, bool? isFeatured}) => Product(
        id: id,
        title: title,
        sellerId: sellerId,
        categoryId: categoryId,
        price: price ?? this.price,
        description: description,
        rating: rating,
        sold: sold,
        stock: stock ?? this.stock,
        leadDays: leadDays,
        acceptsCustom: acceptsCustom,
        customOptions: customOptions,
        customNote: customNote,
        photoCount: photoCount,
        isFeatured: isFeatured ?? this.isFeatured,
        status: status ?? this.status,
        imageUrls: imageUrls,
        imagePaths: imagePaths,
        reviewCount: reviewCount,
      );
}

enum ChatSide { buying, selling }

enum MessageKind { text, quote, system, photo }

class Quote {
  const Quote({required this.item, required this.price, required this.readyBy, this.status = QuoteStatus.sent});
  final String item;
  final double price;
  final DateTime readyBy;
  final QuoteStatus status;
  Quote copyWith({QuoteStatus? status}) => Quote(item: item, price: price, readyBy: readyBy, status: status ?? this.status);
}

enum QuoteStatus { sent, accepted, changesRequested }

class ChatMessage {
  const ChatMessage({required this.fromMe, required this.text, required this.time, this.kind = MessageKind.text, this.quote, this.seen = false});
  final bool fromMe;
  final String text;
  final String time;
  final MessageKind kind;
  final Quote? quote;
  final bool seen;
}

/// Short tag shown under a conversation, e.g. "Custom · Accepted".
class StatusTag {
  const StatusTag(this.label, this.tone);
  final String label;
  final Tone tone;
}

enum Tone { success, warning, error, info, neutral, seller }

class ChatThread {
  const ChatThread({
    required this.id,
    required this.side,
    required this.name,
    required this.initials,
    required this.color,
    required this.messages,
    required this.tag,
    this.sellerId,
    this.productId,
    this.productNote,
    this.unread = 0,
    this.isOnline = false,
    this.lastTime = '',
  });

  final String id;
  final ChatSide side;
  final String name;
  final String initials;
  final Color color;
  final List<ChatMessage> messages;
  final StatusTag tag;
  final String? sellerId;
  final String? productId;
  final String? productNote;
  final int unread;
  final bool isOnline;
  final String lastTime;

  String get lastMessage {
    if (messages.isEmpty) return 'Say hello';
    final m = messages.last;
    final text = m.kind == MessageKind.quote ? 'Quote: ${m.quote!.item}' : m.text;
    return m.fromMe ? 'You: $text' : text;
  }

  ChatThread copyWith({List<ChatMessage>? messages, int? unread, StatusTag? tag, String? lastTime}) => ChatThread(
        id: id,
        side: side,
        name: name,
        initials: initials,
        color: color,
        messages: messages ?? this.messages,
        tag: tag ?? this.tag,
        sellerId: sellerId,
        productId: productId,
        productNote: productNote,
        unread: unread ?? this.unread,
        isOnline: isOnline,
        lastTime: lastTime ?? this.lastTime,
      );
}

enum RequestStatus { pending, quoted, accepted, declined, cancelled }

extension RequestStatusX on RequestStatus {
  String get label => switch (this) {
        RequestStatus.pending => 'Pending',
        RequestStatus.quoted => 'Quoted',
        RequestStatus.accepted => 'Accepted',
        RequestStatus.declined => 'Declined',
        RequestStatus.cancelled => 'Cancelled',
      };
  Tone get tone => switch (this) {
        RequestStatus.pending => Tone.warning,
        RequestStatus.quoted => Tone.info,
        RequestStatus.accepted => Tone.success,
        RequestStatus.declined => Tone.error,
        RequestStatus.cancelled => Tone.neutral,
      };
  bool get isOpen => this == RequestStatus.pending || this == RequestStatus.quoted;
}

/// One version of the seller's price offer for a custom request (QUOTE).
enum OfferStatus { sent, accepted, changesRequested, declined, superseded }

extension OfferStatusX on OfferStatus {
  String get label => switch (this) {
        OfferStatus.sent => 'Waiting for buyer',
        OfferStatus.accepted => 'Accepted',
        OfferStatus.changesRequested => 'Changes asked',
        OfferStatus.declined => 'Declined',
        OfferStatus.superseded => 'Replaced',
      };
  Tone get tone => switch (this) {
        OfferStatus.sent => Tone.info,
        OfferStatus.accepted => Tone.success,
        OfferStatus.changesRequested => Tone.warning,
        OfferStatus.declined => Tone.error,
        OfferStatus.superseded => Tone.neutral,
      };
}

class QuoteOffer {
  const QuoteOffer({
    required this.id,
    required this.version,
    required this.price,
    required this.readyBy,
    required this.status,
    required this.createdAt,
    this.message,
    this.declineReason,
  });
  final String id;
  final int version;
  final double price;
  final DateTime readyBy;
  final OfferStatus status;
  final DateTime createdAt;

  /// Seller's note with the price.
  final String? message;

  /// Why the seller declined, or what the buyer asked to change.
  final String? declineReason;
}

class CustomRequest {
  const CustomRequest({
    required this.code,
    required this.productId,
    required this.description,
    required this.options,
    required this.quantity,
    required this.neededBy,
    required this.sentAt,
    this.budget,
    this.status = RequestStatus.pending,
    this.id = '',
    this.side = ChatSide.buying,
    this.counterpart = '',
    this.productTitle = '',
    this.quotes = const [],
    this.orderNumber,
    this.imagePaths = const [],
  });

  /// Readable request number (custom_request.request_number), e.g. CR-1063.
  final String code;
  final String productId;
  final String description;
  final List<String> options;
  final int quantity;
  final double? budget;
  final DateTime neededBy;
  final DateTime sentAt;
  final RequestStatus status;

  /// custom_request.request_id
  final String id;

  /// Buying = I asked for it; selling = a buyer asked my store.
  final ChatSide side;

  /// The store name (buying) or the buyer's name (selling).
  final String counterpart;
  final String productTitle;

  /// Every quote version, oldest first.
  final List<QuoteOffer> quotes;

  /// The order made when a quote was accepted.
  final String? orderNumber;

  /// Reference photos in the private-files bucket.
  final List<String> imagePaths;

  QuoteOffer? get latestQuote => quotes.isEmpty ? null : quotes.last;

  /// The quote the buyer can still accept or answer.
  QuoteOffer? get openQuote => status == RequestStatus.quoted && latestQuote?.status == OfferStatus.sent ? latestQuote : null;

  /// True when the signed-in user is the one who has to act next.
  bool get needsMyAction => side == ChatSide.selling ? status == RequestStatus.pending : openQuote != null;
}

enum OrderStatus { pending, confirmed, inProduction, shipped, delivered, cancelled }

extension OrderStatusX on OrderStatus {
  String get label => switch (this) {
        OrderStatus.pending => 'Awaiting payment',
        OrderStatus.confirmed => 'Confirmed',
        OrderStatus.inProduction => 'In production',
        OrderStatus.shipped => 'Shipped',
        OrderStatus.delivered => 'Completed',
        OrderStatus.cancelled => 'Cancelled',
      };
  Tone get tone => switch (this) {
        OrderStatus.pending => Tone.warning,
        OrderStatus.confirmed => Tone.info,
        OrderStatus.inProduction => Tone.seller,
        OrderStatus.shipped => Tone.info,
        OrderStatus.delivered => Tone.success,
        OrderStatus.cancelled => Tone.error,
      };
}

enum PaymentStatus { submitted, verified, rejected }

class OrderEvent {
  const OrderEvent(this.status, this.when, [this.note]);
  final OrderStatus status;
  final String when;
  final String? note;
}

class Order {
  const Order({
    required this.number,
    required this.side,
    required this.productId,
    required this.itemLabel,
    required this.quantity,
    required this.total,
    required this.status,
    required this.counterpart,
    required this.placedOn,
    required this.isCustom,
    required this.history,
    this.fulfillment = 'Delivery · J&T Express',
    this.paymentMethod = 'GCash',
    this.paymentRef,
    this.chatId,
    this.id = '',
    this.paymentStatus,
    this.proofPath,
    this.dueDate,
    this.reservedUntil,
    this.reviewed = false,
    this.requestCode,
  });

  final String number;
  final ChatSide side;
  final String productId;
  final String itemLabel;
  final int quantity;
  final double total;
  final OrderStatus status;
  final String counterpart;
  final String placedOn;
  final bool isCustom;
  final List<OrderEvent> history;
  final String fulfillment;
  final String paymentMethod;
  final String? paymentRef;
  final String? chatId;

  /// orders.order_id
  final String id;

  /// State of the latest payment proof (null when none was sent).
  final PaymentStatus? paymentStatus;

  /// Storage path of the latest payment screenshot (private-files bucket).
  final String? proofPath;
  final DateTime? dueDate;

  /// Reserved stock is released after this time if the order is still unpaid.
  final DateTime? reservedUntil;
  final bool reviewed;

  /// The custom request (CR-…) this order came from.
  final String? requestCode;

  /// The buyer still has to send (or re-send) a payment proof.
  bool get needsProof => status == OrderStatus.pending && (paymentRef == null || paymentStatus == PaymentStatus.rejected);

  /// A proof was sent and the seller has not checked it yet.
  bool get proofWaiting => status == OrderStatus.pending && paymentRef != null && paymentStatus != PaymentStatus.rejected;

  Order copyWith({OrderStatus? status, List<OrderEvent>? history, String? paymentRef, PaymentStatus? paymentStatus, bool? reviewed}) => Order(
        number: number,
        side: side,
        productId: productId,
        itemLabel: itemLabel,
        quantity: quantity,
        total: total,
        status: status ?? this.status,
        counterpart: counterpart,
        placedOn: placedOn,
        isCustom: isCustom,
        history: history ?? this.history,
        fulfillment: fulfillment,
        paymentMethod: paymentMethod,
        paymentRef: paymentRef ?? this.paymentRef,
        chatId: chatId,
        id: id,
        paymentStatus: paymentStatus ?? this.paymentStatus,
        proofPath: proofPath,
        dueDate: dueDate,
        reservedUntil: reservedUntil,
        reviewed: reviewed ?? this.reviewed,
        requestCode: requestCode,
      );
}

enum NoticeKind { quote, payment, request, shipping, review }

class AppNotice {
  const AppNotice({required this.kind, required this.title, required this.body, required this.time, required this.route, this.read = false});
  final NoticeKind kind;
  final String title;
  final String body;
  final String time;
  final String route;
  final bool read;
  AppNotice markRead() => AppNotice(kind: kind, title: title, body: body, time: time, route: route, read: true);
}

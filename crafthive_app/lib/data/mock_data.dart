import 'package:flutter/material.dart';

import '../core/theme/app_colors.dart';
import '../shared/widgets/craft_icon.dart';
import 'models.dart';
import 'sample_ids.dart';

/// Sample content so every screen can be navigated before the backend is connected.
/// Replaced by Supabase (PostgreSQL) and Firebase repositories in Milestone 3.
abstract final class MockData {
  static const demoUser = AppUser(
    username: 'ana.makes',
    email: 'ana.reyes@email.com',
    phone: '917 123 4567',
    country: 'Philippines',
    sex: 'Female',
    displayName: 'Ana Reyes',
    bio: 'Crochet bags, keychains and small gifts, made by hand. Custom colors and names welcome; most orders ready in 3 to 5 days.',
    location: 'Cebu City',
    isVerified: true,
  );

  static const categories = <Category>[
    Category(id: SampleIds.catFlowers, name: 'Flowers', icon: CraftIcons.flower, tint: Color(0xFFF6E7C4), ink: Color(0xFFB07A16)),
    Category(id: SampleIds.catPrints3d, name: '3D Prints', icon: CraftIcons.cube, tint: Color(0xFFDCE8E8), ink: AppColors.slateTeal),
    Category(id: SampleIds.catWood, name: 'Woodcrafts', icon: CraftIcons.tree, tint: AppColors.paleSage, ink: AppColors.moss),
    Category(id: SampleIds.catShirts, name: 'Custom Shirts', icon: CraftIcons.shirt, tint: Color(0xFFF0DED6), ink: AppColors.clayText),
    Category(id: SampleIds.catCrochet, name: 'Crochet', icon: CraftIcons.yarn, tint: Color(0xFFEFE3F0), ink: Color(0xFF7B5A80)),
    Category(id: SampleIds.catCandles, name: 'Candles', icon: CraftIcons.candle, tint: Color(0xFFF7EBD3), ink: Color(0xFF9A6B12)),
    Category(id: SampleIds.catPottery, name: 'Pottery', icon: CraftIcons.vase, tint: Color(0xFFF0DED6), ink: AppColors.clay),
    Category(id: SampleIds.catAccessories, name: 'Accessories', icon: CraftIcons.gem, tint: Color(0xFFDCE8E8), ink: AppColors.slateTeal),
  ];

  static const sellers = <Seller>[
    Seller(id: 'me', name: 'ana.makes', initials: 'AR', color: AppColors.clay, location: 'Cebu City', isVerified: true, rating: 4.9, sold: 312, replyTime: 'about 1 hr', bio: 'Crochet bags, keychains and small gifts, made by hand.'),
    Seller(id: SampleIds.storeNarra, name: 'Narra Craft Co.', initials: 'NC', color: AppColors.moss, location: 'Baguio City', isVerified: true, rating: 4.8, sold: 540, replyTime: 'about 4 hrs', bio: 'Kitchen tools and home pieces carved from reclaimed narra and acacia. Engraving available on most items.', isOnline: true),
    Seller(id: SampleIds.storePetal, name: 'Petal & Twine', initials: 'PT', color: Color(0xFFB07A16), location: 'Quezon City', isVerified: true, rating: 4.9, sold: 1210, replyTime: 'about 1 hr', bio: 'Hand-tied bouquets for graduations, birthdays and just because. Same-day pickup in QC.', isOnline: true),
    Seller(id: SampleIds.storeLayer, name: 'LayerLab PH', initials: 'LL', color: AppColors.slateTeal, location: 'Makati City', isVerified: false, rating: 4.7, sold: 860, replyTime: 'about 2 hrs', bio: 'Small 3D-printed gifts, planters and keychains. Send us your idea and we will print it.'),
    Seller(id: SampleIds.storeThread, name: 'Thread & Ink Tees', initials: 'TI', color: Color(0xFF7B5A80), location: 'Pasig City', isVerified: true, rating: 4.6, sold: 2030, replyTime: 'about 3 hrs', bio: 'Custom printed shirts for barkadas, events and small businesses. No minimum order.'),
    Seller(id: SampleIds.storeWick, name: 'Wick & Wax MNL', initials: 'WW', color: Color(0xFF9A6B12), location: 'Manila', isVerified: true, rating: 4.8, sold: 1480, replyTime: 'about 5 hrs', bio: 'Soy candles in Filipino scents: calamansi, sampaguita and kapeng barako.'),
    Seller(id: SampleIds.storeClay, name: 'Clayfolk Studio', initials: 'CS', color: AppColors.clay, location: 'Davao City', isVerified: false, rating: 4.7, sold: 210, replyTime: 'about 6 hrs', bio: 'Hand-thrown mugs and bowls fired in small batches.'),
  ];

  static const products = <Product>[
    Product(id: SampleIds.p1, title: 'Hand-carved Wooden Spoon', sellerId: SampleIds.storeNarra, categoryId: SampleIds.catWood, price: 350, rating: 4.8, sold: 126, stock: 12, leadDays: 6, acceptsCustom: true, isFeatured: true, photoCount: 4,
        customOptions: ['Engraving', 'Size', 'Wood type', 'Finish'], customNote: 'You can ask for engraving, size or wood type. Custom orders take 5 to 7 days.',
        description: 'Carved from one piece of reclaimed narra wood and finished with food-safe coconut oil. Every spoon has its own grain, so yours will look slightly different. 25 cm long.'),
    Product(id: SampleIds.p2, title: 'Hand-tied Sunflower Bouquet', sellerId: SampleIds.storePetal, categoryId: SampleIds.catFlowers, price: 450, rating: 4.9, sold: 210, stock: 6, leadDays: 1, acceptsCustom: true, isFeatured: true,
        customOptions: ['Flower color', 'Wrapper', 'Message card'], customNote: 'Pick the wrapper and add a message card. Custom bouquets are ready the next day.',
        description: 'Three fresh sunflowers with baby\'s breath and eucalyptus, wrapped in kraft paper and twine. Lasts about a week in water.'),
    Product(id: SampleIds.p3, title: '3D-Printed Mini Planter', sellerId: SampleIds.storeLayer, categoryId: SampleIds.catPrints3d, price: 280, rating: 4.7, sold: 88, stock: 15, leadDays: 2, acceptsCustom: true, isFeatured: true,
        customOptions: ['Color', 'Size', 'Name engraving'], customNote: 'Choose any of our 12 filament colors or add a name. Ready in 2 days.',
        description: 'Geometric planter printed in plant-based PLA, with a drainage hole and a small tray. Fits succulents up to 7 cm wide.'),
    Product(id: SampleIds.p4, title: 'Crochet Tote Bag', sellerId: 'me', categoryId: SampleIds.catCrochet, price: 680, rating: 4.9, sold: 64, stock: 8, leadDays: 4, acceptsCustom: true,
        customOptions: ['Color', 'Size', 'Name tag'], customNote: 'Pick your yarn color and add a name tag. Custom bags take 3 to 5 days.',
        description: 'Roomy tote in sage cotton yarn, lined inside. Fits a laptop up to 13 inches.'),
    Product(id: SampleIds.p5, title: 'Soy Candle, Calamansi', sellerId: SampleIds.storeWick, categoryId: SampleIds.catCandles, price: 220, rating: 4.8, sold: 340, stock: 20, acceptsCustom: true, isFeatured: true,
        customOptions: ['Scent', 'Label text'], customNote: 'Choose a scent and print your own label. Ready in 3 days.',
        description: '180 g soy wax candle with a cotton wick and a bright calamansi scent. Burns for about 35 hours.'),
    Product(id: SampleIds.p6, title: 'Custom Name Shirt', sellerId: SampleIds.storeThread, categoryId: SampleIds.catShirts, price: 390, rating: 4.6, sold: 152, leadDays: 3, acceptsCustom: true,
        customOptions: ['Text', 'Shirt color', 'Size', 'Print side'], customNote: 'Send your text or logo. Orders of any size are printed in 3 days.',
        description: 'Soft cotton shirt printed with your name or design. Sizes XS to 3XL.'),
    Product(id: SampleIds.p7, title: 'Graduation Bouquet', sellerId: SampleIds.storePetal, categoryId: SampleIds.catFlowers, price: 650, rating: 4.9, sold: 95, stock: 4, leadDays: 1, acceptsCustom: true,
        customOptions: ['Flower color', 'Ribbon text', 'Add a bear'],
        description: 'Roses, chrysanthemums and a satin ribbon in your school colors. Order 2 days before the ceremony.'),
    Product(id: SampleIds.p8, title: 'Narra Serving Board', sellerId: SampleIds.storeNarra, categoryId: SampleIds.catWood, price: 890, rating: 4.7, sold: 41, stock: 5,
        description: 'Long serving board with a juice groove, finished with food-safe oil. 45 × 20 cm.'),
    Product(id: SampleIds.p9, title: 'Articulated Dragon Keychain', sellerId: SampleIds.storeLayer, categoryId: SampleIds.catPrints3d, price: 180, rating: 4.8, sold: 230, stock: 25,
        description: 'Flexible printed dragon that wiggles and bends. 12 cm long with a metal key ring.'),
    Product(id: SampleIds.p10, title: 'Sunflower Keychain', sellerId: 'me', categoryId: SampleIds.catCrochet, price: 120, rating: 4.9, sold: 140, stock: 2,
        description: 'Small crochet sunflower on a gold-tone key ring. A cheerful little gift.'),
    Product(id: SampleIds.p11, title: 'Name Bracelet, Beaded', sellerId: 'me', categoryId: SampleIds.catAccessories, price: 150, rating: 4.8, sold: 75, leadDays: 3, acceptsCustom: true,
        customOptions: ['Name', 'Bead color'], description: 'Glass-bead bracelet with letter beads spelling any name up to 10 letters.'),
    Product(id: SampleIds.p12, title: 'Mini Crochet Bouquet', sellerId: 'me', categoryId: SampleIds.catCrochet, price: 390, rating: 5.0, sold: 33,
        description: 'Three crochet tulips that never wilt, wrapped like a real bouquet.'),
    Product(id: SampleIds.p13, title: 'Lavender Candle Set', sellerId: SampleIds.storeWick, categoryId: SampleIds.catCandles, price: 480, rating: 4.7, sold: 120, stock: 9,
        description: 'Set of three 80 g lavender soy candles in amber jars. A calming gift.'),
    Product(id: SampleIds.p14, title: 'Barkada Tees, Set of 5', sellerId: SampleIds.storeThread, categoryId: SampleIds.catShirts, price: 1750, rating: 4.7, sold: 60, leadDays: 4, acceptsCustom: true,
        customOptions: ['Text', 'Shirt color', 'Sizes'], description: 'Five matching printed shirts for your group trip or event.'),
    Product(id: SampleIds.p15, title: 'Hand-thrown Mug', sellerId: SampleIds.storeClay, categoryId: SampleIds.catPottery, price: 520, rating: 4.7, sold: 48, stock: 7,
        description: 'Stoneware mug with a speckled glaze. Holds about 350 ml. Microwave safe.'),
  ];

  static const recentSearches = ['graduation bouquet', 'crochet keychain', 'custom tote bag'];

  static final threads = <ChatThread>[
    ChatThread(
      id: 't-narra', side: ChatSide.buying, name: 'Narra Craft Co.', initials: 'NC', color: AppColors.moss, sellerId: SampleIds.storeNarra, productId: SampleIds.p1,
      productNote: 'from your custom request', unread: 2, isOnline: true, lastTime: '2:47 PM', tag: const StatusTag('Custom · Accepted', Tone.success),
      messages: [
        const ChatMessage(fromMe: false, text: 'Custom request CR-1042 sent · Oct 31', time: '', kind: MessageKind.system),
        const ChatMessage(fromMe: false, text: 'Hi Ana! I can make a set of 3 with the engraving. Small, medium and large.', time: '2:41 PM'),
        ChatMessage(fromMe: false, text: '', time: '2:42 PM', kind: MessageKind.quote, quote: Quote(item: 'Engraved spoon set × 3', price: 1050, readyBy: DateTime(2026, 12, 10))),
        const ChatMessage(fromMe: true, text: 'Perfect, thank you! I\'ll pay through GCash.', time: '2:46 PM', seen: true),
        const ChatMessage(fromMe: false, text: 'Great. I\'ll start carving once the payment comes in.', time: '2:47 PM'),
      ],
    ),
    const ChatThread(
      id: 't-petal', side: ChatSide.buying, name: 'Petal & Twine', initials: 'PT', color: Color(0xFFB07A16), sellerId: SampleIds.storePetal, productId: SampleIds.p2, unread: 1, isOnline: true,
      lastTime: '11:20 AM', tag: StatusTag('Ready for pickup', Tone.info),
      messages: [
        ChatMessage(fromMe: true, text: 'Hi! Can I pick up the sunflower bouquet tomorrow morning?', time: '10:58 AM', seen: true),
        ChatMessage(fromMe: false, text: 'Your bouquet is ready for pickup tomorrow.', time: '11:20 AM'),
      ],
    ),
    const ChatThread(
      id: 't-layer', side: ChatSide.buying, name: 'LayerLab PH', initials: 'LL', color: AppColors.slateTeal, sellerId: SampleIds.storeLayer, productId: SampleIds.p3, lastTime: 'Yesterday',
      tag: StatusTag('Asking', Tone.neutral),
      messages: [
        ChatMessage(fromMe: false, text: 'Hello! Thanks for checking our planter.', time: '4:10 PM'),
        ChatMessage(fromMe: true, text: 'Can you print it in sage green?', time: '4:12 PM'),
      ],
    ),
    const ChatThread(
      id: 't-thread', side: ChatSide.buying, name: 'Thread & Ink Tees', initials: 'TI', color: Color(0xFF7B5A80), sellerId: SampleIds.storeThread, productId: SampleIds.p6, lastTime: 'Oct 28',
      tag: StatusTag('Shipped', Tone.info),
      messages: [ChatMessage(fromMe: false, text: 'Shipped through J&T, tracking 7701 2345 8890', time: 'Oct 28')],
    ),
    const ChatThread(
      id: 't-wick', side: ChatSide.buying, name: 'Wick & Wax MNL', initials: 'WW', color: Color(0xFF9A6B12), sellerId: SampleIds.storeWick, productId: SampleIds.p5, lastTime: 'Oct 22',
      tag: StatusTag('Completed', Tone.success),
      messages: [ChatMessage(fromMe: false, text: 'Thank you for your order!', time: 'Oct 22')],
    ),
    // Selling side: customers of my store
    const ChatThread(
      id: 't-miguel', side: ChatSide.selling, name: 'Miguel Santos', initials: 'MS', color: AppColors.slateTeal, productId: SampleIds.p10, unread: 1, lastTime: '3:02 PM',
      tag: StatusTag('Custom · Needs reply', Tone.warning),
      messages: [
        ChatMessage(fromMe: false, text: 'Custom request CR-1051 received · Nov 3', time: '', kind: MessageKind.system),
        ChatMessage(fromMe: false, text: 'Custom request: 10 name keychains for a party', time: '3:02 PM'),
      ],
    ),
    const ChatThread(
      id: 't-bea', side: ChatSide.selling, name: 'Bea Lim', initials: 'BL', color: Color(0xFF7B5A80), productId: SampleIds.p4, unread: 1, lastTime: '1:15 PM',
      tag: StatusTag('Payment sent', Tone.info),
      messages: [
        ChatMessage(fromMe: true, text: 'Your tote is ready to ship once payment comes in.', time: '12:40 PM', seen: true),
        ChatMessage(fromMe: false, text: 'Paid through GCash, ref 5012 345 678901', time: '1:15 PM'),
      ],
    ),
    const ChatThread(
      id: 't-jessa', side: ChatSide.selling, name: 'Jessa Cruz', initials: 'JC', color: AppColors.moss, productId: SampleIds.p4, lastTime: 'Yesterday',
      tag: StatusTag('Inquiry', Tone.neutral),
      messages: [ChatMessage(fromMe: false, text: 'Is the crochet tote still available?', time: '6:30 PM')],
    ),
    const ChatThread(
      id: 't-carlo', side: ChatSide.selling, name: 'Carlo Dizon', initials: 'CD', color: Color(0xFFB07A16), productId: SampleIds.p10, lastTime: 'Oct 27',
      tag: StatusTag('Completed', Tone.success),
      messages: [ChatMessage(fromMe: false, text: 'Received it, thank you so much!', time: 'Oct 27')],
    ),
    const ChatThread(
      id: 't-rina', side: ChatSide.selling, name: 'Rina Pascual', initials: 'RP', color: AppColors.clay, productId: SampleIds.p4, lastTime: 'Oct 25',
      tag: StatusTag('Inquiry', Tone.neutral),
      messages: [ChatMessage(fromMe: false, text: 'Can you do it in navy blue?', time: 'Oct 25')],
    ),
  ];

  static const orders = <Order>[
    Order(number: 'CH-2026-001042', side: ChatSide.buying, productId: SampleIds.p1, itemLabel: 'Engraved spoon set', quantity: 3, total: 1050, status: OrderStatus.pending,
        counterpart: 'Narra Craft Co.', placedOn: 'Oct 31, 2026', isCustom: true, chatId: 't-narra',
        history: [OrderEvent(OrderStatus.pending, 'Oct 31, 2:48 PM', 'Quote accepted. Waiting for your payment.')]),
    Order(number: 'CH-2026-001031', side: ChatSide.buying, productId: SampleIds.p2, itemLabel: 'Hand-tied Sunflower Bouquet', quantity: 1, total: 450, status: OrderStatus.inProduction,
        counterpart: 'Petal & Twine', placedOn: 'Oct 30, 2026', isCustom: false, chatId: 't-petal', fulfillment: 'Pickup · Quezon City', paymentRef: '5012 778 120044',
        history: [
          OrderEvent(OrderStatus.pending, 'Oct 30, 9:12 AM'),
          OrderEvent(OrderStatus.confirmed, 'Oct 30, 9:40 AM', 'Payment confirmed by the seller.'),
          OrderEvent(OrderStatus.inProduction, 'Nov 2, 4:15 PM', 'Bouquet is being arranged.'),
        ]),
    Order(number: 'CH-2026-001018', side: ChatSide.buying, productId: SampleIds.p6, itemLabel: 'Custom Name Shirt', quantity: 2, total: 780, status: OrderStatus.shipped,
        counterpart: 'Thread & Ink Tees', placedOn: 'Oct 24, 2026', isCustom: false, chatId: 't-thread', paymentRef: '5012 664 900812',
        history: [
          OrderEvent(OrderStatus.pending, 'Oct 24, 1:05 PM'),
          OrderEvent(OrderStatus.confirmed, 'Oct 24, 3:30 PM', 'Payment confirmed by the seller.'),
          OrderEvent(OrderStatus.inProduction, 'Oct 25, 10:00 AM', 'Printing your shirts.'),
          OrderEvent(OrderStatus.shipped, 'Oct 28, 5:20 PM', 'J&T tracking 7701 2345 8890'),
        ]),
    Order(number: 'CH-2026-000977', side: ChatSide.buying, productId: SampleIds.p5, itemLabel: 'Soy Candle, Calamansi', quantity: 2, total: 440, status: OrderStatus.delivered,
        counterpart: 'Wick & Wax MNL', placedOn: 'Oct 18, 2026', isCustom: false, chatId: 't-wick', paymentRef: '5012 551 330217',
        history: [
          OrderEvent(OrderStatus.pending, 'Oct 18, 8:00 PM'),
          OrderEvent(OrderStatus.confirmed, 'Oct 19, 9:10 AM'),
          OrderEvent(OrderStatus.shipped, 'Oct 20, 2:00 PM'),
          OrderEvent(OrderStatus.delivered, 'Oct 22, 11:45 AM', 'You confirmed receipt and left a 5-star review.'),
        ]),
    Order(number: 'CH-2026-001047', side: ChatSide.selling, productId: SampleIds.p4, itemLabel: 'Crochet Tote Bag', quantity: 1, total: 680, status: OrderStatus.pending,
        counterpart: 'Bea Lim', placedOn: 'Nov 3, 2026', isCustom: false, chatId: 't-bea', paymentRef: '5012 345 678901',
        history: [OrderEvent(OrderStatus.pending, 'Nov 3, 12:30 PM', 'Buyer uploaded a GCash payment proof. Please check and confirm.')]),
    Order(number: 'CH-2026-001003', side: ChatSide.selling, productId: SampleIds.p10, itemLabel: 'Sunflower Keychain', quantity: 4, total: 480, status: OrderStatus.delivered,
        counterpart: 'Carlo Dizon', placedOn: 'Oct 21, 2026', isCustom: false, chatId: 't-carlo', paymentRef: '5012 402 118930',
        history: [
          OrderEvent(OrderStatus.pending, 'Oct 21, 6:10 PM'),
          OrderEvent(OrderStatus.confirmed, 'Oct 21, 7:00 PM'),
          OrderEvent(OrderStatus.shipped, 'Oct 23, 1:00 PM'),
          OrderEvent(OrderStatus.delivered, 'Oct 27, 9:30 AM', 'Buyer confirmed receipt.'),
        ]),
  ];

  static const notices = <AppNotice>[
    AppNotice(kind: NoticeKind.quote, title: 'Your custom request was accepted', body: 'Narra Craft Co. quoted ₱1,050 for the engraved spoon set, ready Dec 10.', time: '2:42 PM', route: '/chat/t-narra'),
    AppNotice(kind: NoticeKind.request, title: 'New custom request', body: 'Miguel Santos wants 10 name keychains for a party.', time: '3:02 PM', route: '/chat/t-miguel'),
    AppNotice(kind: NoticeKind.payment, title: 'Payment proof received', body: 'Bea Lim uploaded a GCash proof for order CH-2026-001047.', time: '1:15 PM', route: '/order/CH-2026-001047'),
    AppNotice(kind: NoticeKind.shipping, title: 'Your order is on the way', body: 'Thread & Ink Tees shipped CH-2026-001018 through J&T.', time: 'Oct 28', route: '/order/CH-2026-001018', read: true),
    AppNotice(kind: NoticeKind.review, title: 'New 5-star review', body: '"So cute and well made!" — Carlo on Sunflower Keychain.', time: 'Oct 27', route: '/store', read: true),
  ];
}

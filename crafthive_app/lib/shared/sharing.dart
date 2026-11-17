import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import '../core/router/app_router.dart';
import '../core/utils/share_links.dart';
import '../data/models.dart';
import '../data/providers.dart';
import 'widgets/common.dart';

/// Opens the phone's share sheet. Swapped for a fake in tests.
abstract class Sharer {
  Future<void> share(String text, {String? subject});

  /// Links opened from outside the app (another chat, a browser). Empty when not supported.
  Stream<Uri> get incomingLinks;
  Future<Uri?> initialLink();
}

class SystemSharer implements Sharer {
  final _links = AppLinks();

  @override
  Future<void> share(String text, {String? subject}) => SharePlus.instance.share(ShareParams(text: text, subject: subject));

  @override
  Stream<Uri> get incomingLinks => _links.uriLinkStream;

  @override
  Future<Uri?> initialLink() => _links.getInitialLink();
}

final sharerProvider = Provider<Sharer>((ref) => SystemSharer());

/// Shares an item: name, price, store and a link that opens it in the app.
Future<void> shareProduct(BuildContext context, WidgetRef ref, Product p) async {
  final s = ref.read(sellerProvider(p.sellerId));
  await _share(context, ref, ShareLinks.productText(p, s), subject: p.title);
}

/// Shares a store. [sellerId] is the catalog id ("me" for your own store).
Future<void> shareStore(BuildContext context, WidgetRef ref, Seller s) async {
  final storeId = s.id == 'me' ? ref.read(myStoreIdProvider) : s.id;
  if (storeId == null) {
    showMessage(context, 'Open your store first, then you can share it.');
    return;
  }
  final listings = ref.read(catalogProvider).where((p) => p.sellerId == s.id && p.status == ListingStatus.active).length;
  await _share(context, ref, ShareLinks.storeText(s, storeId, listings: listings), subject: s.name);
}

Future<void> _share(BuildContext context, WidgetRef ref, String text, {String? subject}) async {
  try {
    await ref.read(sharerProvider).share(text, subject: subject);
  } catch (e) {
    debugPrint('CraftHive: share failed: $e');
    if (context.mounted) showMessage(context, "Couldn't open sharing on this phone. Try again.");
  }
}

/// Opens shared CraftHive links (ph.crafthive.app://open/...) on the right
/// screen. A link that arrives before sign-in opens right after it.
class ShareLinkListener extends ConsumerStatefulWidget {
  const ShareLinkListener({super.key, required this.child});
  final Widget child;
  @override
  ConsumerState<ShareLinkListener> createState() => _ShareLinkListenerState();
}

class _ShareLinkListenerState extends ConsumerState<ShareLinkListener> {
  StreamSubscription<Uri>? _sub;
  Uri? _pending;

  @override
  void initState() {
    super.initState();
    final sharer = ref.read(sharerProvider);
    try {
      _sub = sharer.incomingLinks.listen(_handle, onError: (Object e) => debugPrint('CraftHive: link error: $e'));
      sharer.initialLink().then((u) {
        if (u != null) _handle(u);
      }).catchError((Object e) => debugPrint('CraftHive: initial link error: $e'));
    } catch (e) {
      debugPrint('CraftHive: links unavailable: $e');
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  void _handle(Uri uri) {
    if (ShareLinks.routeFor(uri) == null) return; // password-reset links are Supabase's
    _pending = uri;
    _openPending();
  }

  void _openPending() {
    final uri = _pending;
    if (uri == null || !mounted) return;
    final user = ref.read(authProvider);
    if (ref.read(authStatusProvider) != AuthStatus.signedIn || user == null || user.isAdmin) return;
    final route = ShareLinks.routeFor(uri, myStoreId: ref.read(myStoreIdProvider));
    _pending = null;
    if (route != null) ref.read(routerProvider).push(route);
  }

  @override
  Widget build(BuildContext context) {
    // When the user finishes signing in, open a link that came in before.
    ref.listen(authStatusProvider, (_, next) {
      if (next == AuthStatus.signedIn) WidgetsBinding.instance.addPostFrameCallback((_) => _openPending());
    });
    return widget.child;
  }
}

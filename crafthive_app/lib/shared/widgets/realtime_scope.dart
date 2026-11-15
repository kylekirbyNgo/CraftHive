import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/router/app_router.dart';
import '../../core/theme/app_colors.dart';
import '../../data/providers.dart';

/// Shows snack bars from outside a screen (push notifications in the foreground).
final appMessengerKey = GlobalKey<ScaffoldMessengerState>();

/// Runs the Firebase parts that live as long as the app:
/// • online status (Realtime Database) while the app is open,
/// • this phone's push token, saved when a user signs in,
/// • opening the right screen when a push notification is tapped,
/// • a banner for notifications that arrive while the app is open.
class RealtimeScope extends ConsumerStatefulWidget {
  const RealtimeScope({super.key, required this.child});
  final Widget child;

  @override
  ConsumerState<RealtimeScope> createState() => _RealtimeScopeState();
}

class _RealtimeScopeState extends ConsumerState<RealtimeScope> {
  late final AppLifecycleListener _lifecycle;
  final _subs = <StreamSubscription<Object>>[];
  String? _me;
  bool _checkedInitial = false;

  @override
  void initState() {
    super.initState();
    final push = ref.read(pushServiceProvider);
    _subs
      ..add(push.openedRoutes.listen(_open))
      ..add(push.foreground.listen(_banner));
    _lifecycle = AppLifecycleListener(
      onResume: () {
        final me = _me;
        if (me != null) ref.read(presenceRepositoryProvider).goOnline(me);
      },
      onHide: () {
        final me = _me;
        if (me != null) ref.read(presenceRepositoryProvider).goOffline(me);
      },
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final me = ref.read(firebaseUidProvider).valueOrNull;
      if (me != null) _signedIn(me);
    });
  }

  @override
  void dispose() {
    for (final s in _subs) {
      s.cancel();
    }
    _lifecycle.dispose();
    super.dispose();
  }

  Future<void> _signedIn(String me) async {
    if (_me == me) return;
    _me = me;
    await ref.read(presenceRepositoryProvider).goOnline(me);
    await ref.read(pushServiceProvider).register(me);
    if (!_checkedInitial) {
      // The app was started by tapping a notification.
      _checkedInitial = true;
      final route = await ref.read(pushServiceProvider).initialRoute();
      if (route != null) _open(route);
    }
  }

  String get _location {
    try {
      return ref.read(routerProvider).routerDelegate.currentConfiguration.uri.path;
    } catch (_) {
      return '';
    }
  }

  void _open(String route) {
    if (_me == null || !mounted) return;
    if (_location == route) return;
    ref.read(routerProvider).push(route);
  }

  void _banner(PushBanner b) {
    // Already looking at this chat: the new message is on screen.
    if (b.type == 'message' && _location == b.route) return;
    appMessengerKey.currentState
      ?..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        duration: const Duration(seconds: 5),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(b.title, style: const TextStyle(fontWeight: FontWeight.w800)),
          if (b.body.isNotEmpty) Text(b.body, maxLines: 2, overflow: TextOverflow.ellipsis),
        ]),
        action: SnackBarAction(label: 'Open', textColor: AppColors.softHoney, onPressed: () => _open(b.route)),
      ));
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<AsyncValue<String?>>(firebaseUidProvider, (prev, next) {
      final me = next.valueOrNull;
      if (me != null) {
        _signedIn(me);
      } else if (!next.isLoading) {
        _me = null;
      }
    });
    return widget.child;
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/providers.dart';
import '../../features/auth/forgot_password_screen.dart';
import '../../features/auth/login_screen.dart';
import '../../features/auth/reset_password_screen.dart';
import '../../features/auth/signup_screen.dart';
import '../../features/auth/splash_screen.dart';
import '../../features/custom_order/custom_order_screen.dart';
import '../../features/custom_order/request_sent_screen.dart';
import '../../features/home/home_screen.dart';
import '../../features/home/search_screen.dart';
import '../../features/messages/chat_screen.dart';
import '../../features/messages/messages_screen.dart';
import '../../features/notifications/notifications_screen.dart';
import '../../features/orders/order_details_screen.dart';
import '../../features/orders/orders_screen.dart';
import '../../features/product/product_details_screen.dart';
import '../../features/saved/saved_screen.dart';
import '../../features/selling/new_listing_screen.dart';
import '../../features/store/edit_profile_screen.dart';
import '../../features/store/my_store_screen.dart';
import '../../features/store/seller_store_screen.dart';
import '../../shared/widgets/main_shell.dart';

final _rootKey = GlobalKey<NavigatorState>(debugLabel: 'root');

/// Re-runs the router's redirect whenever the sign-in state changes.
class _AuthListenable extends ChangeNotifier {
  _AuthListenable(Ref ref) {
    ref.listen(authStatusProvider, (_, __) => notifyListeners());
    ref.listen(passwordRecoveryProvider, (_, __) => notifyListeners());
    // Opening the reset link from the email starts a password recovery.
    final sub = ref.read(authRepositoryProvider).passwordRecoveryEvents.listen((_) {
      ref.read(passwordRecoveryProvider.notifier).state = true;
    });
    ref.onDispose(sub.cancel);
  }
}

/// Navigation map from the Milestone 1 blueprint (section 5).
/// Signed out: Log in and Sign up only. Signed in: bottom bar with Home,
/// Messages, Sell (+), Orders and Saved; every other screen opens on top with a back button.
final routerProvider = Provider<GoRouter>((ref) {
  final refresh = _AuthListenable(ref);
  ref.onDispose(refresh.dispose);
  const publicPaths = {'/login', '/signup', '/forgot-password'};

  return GoRouter(
    navigatorKey: _rootKey,
    initialLocation: '/splash',
    refreshListenable: refresh,
    redirect: (context, state) {
      final loc = state.matchedLocation;
      final status = ref.read(authStatusProvider);
      // Opened the reset link: choose a new password before anything else.
      if (ref.read(passwordRecoveryProvider) && status == AuthStatus.signedIn) {
        return loc == '/reset-password' ? null : '/reset-password';
      }
      switch (status) {
        case AuthStatus.checking:
        case AuthStatus.profileError:
          return loc == '/splash' ? null : '/splash';
        case AuthStatus.signedOut:
          return publicPaths.contains(loc) ? null : '/login';
        case AuthStatus.signedIn:
          return publicPaths.contains(loc) || loc == '/splash' || loc == '/reset-password' ? '/home' : null;
      }
    },
    routes: [
      GoRoute(path: '/splash', builder: (_, __) => const SplashScreen()),
      GoRoute(path: '/reset-password', builder: (_, __) => const ResetPasswordScreen()),
      GoRoute(path: '/', redirect: (_, __) => '/home'),
      GoRoute(path: '/login', builder: (_, __) => const LoginScreen()),
      GoRoute(path: '/signup', builder: (_, __) => const SignupScreen()),
      GoRoute(path: '/forgot-password', builder: (_, __) => const ForgotPasswordScreen()),

      // Main app with the bottom navigation bar.
      StatefulShellRoute.indexedStack(
        builder: (context, state, shell) => MainShell(shell: shell),
        branches: [
          StatefulShellBranch(routes: [GoRoute(path: '/home', builder: (_, __) => const HomeScreen())]),
          StatefulShellBranch(routes: [GoRoute(path: '/messages', builder: (_, __) => const MessagesScreen())]),
          StatefulShellBranch(routes: [GoRoute(path: '/orders', builder: (_, __) => const OrdersScreen())]),
          StatefulShellBranch(routes: [GoRoute(path: '/saved', builder: (_, __) => const SavedScreen())]),
        ],
      ),

      // Screens that open above the bottom bar.
      GoRoute(
        parentNavigatorKey: _rootKey,
        path: '/search',
        builder: (_, s) => SearchScreen(initialQuery: s.uri.queryParameters['q'] ?? '', categoryId: s.uri.queryParameters['category']),
      ),
      GoRoute(parentNavigatorKey: _rootKey, path: '/notifications', builder: (_, __) => const NotificationsScreen()),
      GoRoute(
        parentNavigatorKey: _rootKey,
        path: '/product/:id',
        builder: (_, s) => ProductDetailsScreen(productId: s.pathParameters['id']!),
        routes: [
          GoRoute(parentNavigatorKey: _rootKey, path: 'custom', builder: (_, s) => CustomOrderScreen(productId: s.pathParameters['id']!)),
        ],
      ),
      GoRoute(parentNavigatorKey: _rootKey, path: '/request-sent/:code', builder: (_, s) => RequestSentScreen(code: s.pathParameters['code']!)),
      GoRoute(parentNavigatorKey: _rootKey, path: '/chat/:id', builder: (_, s) => ChatScreen(threadId: s.pathParameters['id']!)),
      GoRoute(parentNavigatorKey: _rootKey, path: '/sell', builder: (_, __) => const NewListingScreen()),
      GoRoute(parentNavigatorKey: _rootKey, path: '/listing/:id/edit', builder: (_, s) => NewListingScreen(editId: s.pathParameters['id'])),
      GoRoute(
        parentNavigatorKey: _rootKey,
        path: '/store',
        builder: (_, __) => const MyStoreScreen(),
        routes: [GoRoute(parentNavigatorKey: _rootKey, path: 'edit', builder: (_, __) => const EditProfileScreen())],
      ),
      GoRoute(parentNavigatorKey: _rootKey, path: '/seller/:id', builder: (_, s) => SellerStoreScreen(sellerId: s.pathParameters['id']!)),
      GoRoute(parentNavigatorKey: _rootKey, path: '/order/:number', builder: (_, s) => OrderDetailsScreen(number: s.pathParameters['number']!)),
    ],
  );
});

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'core/config/firebase_config.dart';
import 'core/config/supabase_config.dart';
import 'core/router/app_router.dart';
import 'core/theme/app_colors.dart';
import 'core/theme/app_theme.dart';
import 'shared/sharing.dart';
import 'shared/widgets/realtime_scope.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (!SupabaseConfig.isSet) {
    runApp(const _SetupMessage('The Supabase URL and key are missing in lib/core/config/supabase_config.dart.'));
    return;
  }
  try {
    // Restores the saved login session, if any, before the first screen.
    await Supabase.initialize(url: SupabaseConfig.url, anonKey: SupabaseConfig.anonKey);
  } catch (e) {
    runApp(_SetupMessage('Could not start the connection to Supabase: $e'));
    return;
  }
  // Firebase: chat, online status, notifications and push. Without it the app
  // still runs, with sample chats (see lib/core/config/firebase_config.dart).
  if (FirebaseConfig.isSet) {
    try {
      await Firebase.initializeApp(options: FirebaseConfig.options);
      FirebaseConfig.ready = true;
    } catch (e) {
      debugPrint('Firebase did not start: $e');
    }
  }
  // Plus Jakarta Sans is downloaded once by google_fonts and cached on the phone.
  GoogleFonts.config.allowRuntimeFetching = true;
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.dark,
    systemNavigationBarColor: AppColors.white,
    systemNavigationBarIconBrightness: Brightness.dark,
  ));
  runApp(const ProviderScope(child: CraftHiveApp()));
}

class CraftHiveApp extends ConsumerWidget {
  const CraftHiveApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(routerProvider);
    return MaterialApp.router(
      title: 'CraftHive',
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(),
      routerConfig: router,
      scaffoldMessengerKey: appMessengerKey,
      builder: (context, child) {
        // Respect the user's text size, but cap it so layouts stay intact.
        final mq = MediaQuery.of(context);
        return MediaQuery(
          data: mq.copyWith(textScaler: mq.textScaler.clamp(minScaleFactor: 0.9, maxScaleFactor: 1.3)),
          child: RealtimeScope(child: ShareLinkListener(child: child!)),
        );
      },
    );
  }
}

/// Shown only when the app is built without valid Supabase settings.
class _SetupMessage extends StatelessWidget {
  const _SetupMessage(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => MaterialApp(
        debugShowCheckedModeBanner: false,
        home: Scaffold(body: SafeArea(child: Padding(padding: const EdgeInsets.all(24), child: Center(child: Text(text, textAlign: TextAlign.center))))),
      );
}

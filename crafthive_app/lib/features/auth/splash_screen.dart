import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../data/providers.dart';
import '../../shared/widgets/common.dart';

/// Shown while the app checks for a saved session and loads the profile.
/// If the profile cannot be loaded, it explains why and offers Try again / Log out.
class SplashScreen extends ConsumerWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(authStatusProvider);
    final error = ref.watch(profileProvider).error;
    final failed = status == AuthStatus.profileError;

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: ResponsiveCenter(
              maxWidth: 420,
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                ClipOval(child: Image.asset('assets/images/logo.png', width: 96, height: 96, fit: BoxFit.cover, semanticLabel: 'CraftHive logo')),
                const SizedBox(height: 14),
                Text('CraftHive', style: AppText.display),
                const SizedBox(height: 24),
                if (!failed) ...[
                  const SizedBox(width: 28, height: 28, child: CircularProgressIndicator(strokeWidth: 3, color: AppColors.moss)),
                  const SizedBox(height: 14),
                  Text('Getting things ready…', style: AppText.caption),
                ] else ...[
                  Text("We couldn't open your account", style: AppText.screenTitle, textAlign: TextAlign.center),
                  const SizedBox(height: 8),
                  Text(
                    error is AppFailure ? error.message : 'Please check your connection and try again.',
                    style: AppText.body.copyWith(color: AppColors.grayBrown),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 20),
                  AppButton(label: 'Try again', onPressed: () => ref.invalidate(profileProvider)),
                  const SizedBox(height: 10),
                  AppButton(label: 'Log out', kind: ButtonKind.outline, onPressed: () => ref.read(authProvider.notifier).signOut()),
                ],
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

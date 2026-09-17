import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/branding/app_brand.dart';
import 'core/router/app_router.dart';
import 'core/theme/app_theme.dart';
import 'features/auth/providers/auth_controller.dart';

void main() {
  runApp(const ProviderScope(child: LuminaApp()));
}

/// Point d’entrée UI. La restore de session est déclenchée par [authControllerProvider] ;
/// [appRouterProvider] redirige Welcome/Login ↔ Home selon l’état.
class LuminaApp extends ConsumerWidget {
  const LuminaApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(authControllerProvider);
    final router = ref.watch(appRouterProvider);
    return MaterialApp.router(
      debugShowCheckedModeBanner: false,
      title: AppBrand.appName,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: AppTheme.themeMode,
      routerConfig: router,
    );
  }
}

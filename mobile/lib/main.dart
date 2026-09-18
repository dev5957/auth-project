import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/branding/app_brand.dart';
import 'core/router/app_router.dart';
import 'core/theme/app_theme.dart';

void main() {
  debugPrint('[auth-restore-diag] main() entered at ${DateTime.now().toIso8601String()}');
  WidgetsFlutterBinding.ensureInitialized();
  debugPrint('[auth-restore-diag] WidgetsFlutterBinding.ensureInitialized() done');
  runApp(const ProviderScope(child: LuminaApp()));
  debugPrint('[auth-restore-diag] runApp(ProviderScope) called');
}

/// Point d’entrée UI. La restore est déclenchée par le router ; le splash
/// reste affiché tant qu’elle n’est pas finie.
class LuminaApp extends ConsumerWidget {
  const LuminaApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    debugPrint('[auth-restore-diag] LuminaApp.build() → watch appRouterProvider');
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

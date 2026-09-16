import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'features/auth/providers/auth_controller.dart';

void main() {
  runApp(const ProviderScope(child: AuthSkeletonApp()));
}

/// Point d'entrée uniquement. Les écrans Auth seront ajoutés plus tard.
/// [authControllerProvider] est observé pour lancer la restauration de session.
class AuthSkeletonApp extends ConsumerWidget {
  const AuthSkeletonApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(authControllerProvider);
    return const MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'auth-project',
      home: Scaffold(
        body: Center(
          child: Text('Auth skeleton'),
        ),
      ),
    );
  }
}

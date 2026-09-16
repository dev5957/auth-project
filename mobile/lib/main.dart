import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'features/auth/providers/auth_controller.dart';
import 'features/auth/state/auth_state.dart';

void main() {
  runApp(const ProviderScope(child: AuthSkeletonApp()));
}

/// Affichage temporaire pour vérifier le cycle de restauration. Pas un écran Auth.
class AuthSkeletonApp extends ConsumerWidget {
  const AuthSkeletonApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authControllerProvider);
    final label = switch (authState) {
      AuthLoading() => 'Restoring session...',
      AuthAuthenticated() => 'Authenticated',
      AuthUnauthenticated() => 'Not authenticated',
    };
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'auth-project',
      home: Scaffold(
        body: Center(
          child: Text(label),
        ),
      ),
    );
  }
}

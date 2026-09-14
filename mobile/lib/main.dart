import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

void main() {
  runApp(const ProviderScope(child: AuthSkeletonApp()));
}

/// Point d'entrée uniquement. Les écrans Auth seront ajoutés plus tard.
class AuthSkeletonApp extends StatelessWidget {
  const AuthSkeletonApp({super.key});

  @override
  Widget build(BuildContext context) {
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

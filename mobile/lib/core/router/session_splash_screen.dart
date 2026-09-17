import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../widgets/app_loading.dart';

/// Attente de [AuthController.restore]. Pas d’onboarding.
class SessionSplashScreen extends StatelessWidget {
  const SessionSplashScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = context.luminaColors;
    return Scaffold(
      backgroundColor: colors.bgBase,
      body: const SafeArea(
        child: AppLoading(),
      ),
    );
  }
}

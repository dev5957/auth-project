import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/router/app_routes.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_text_theme.dart';
import '../../../../core/widgets/app_button.dart';
import '../../../../core/widgets/app_card.dart';
import '../../../../core/widgets/app_logo.dart';
import 'onboarding_slides.dart';

/// Onboarding d’entrée Auth. Pas de logique métier ni de persistance.
class AuthEntryScreen extends StatefulWidget {
  const AuthEntryScreen({super.key});

  @override
  State<AuthEntryScreen> createState() => _AuthEntryScreenState();
}

class _AuthEntryScreenState extends State<AuthEntryScreen> {
  late final PageController _pageController;
  int _index = 0;

  @override
  void initState() {
    super.initState();
    _pageController = PageController(viewportFraction: 0.86);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  bool get _isLast => _index >= onboardingSlides.length - 1;

  void _goToRegister() {
    context.push(AppRoutes.register);
  }

  void _goNext() {
    if (_isLast) {
      _goToRegister();
      return;
    }
    _pageController.nextPage(
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.luminaColors;
    final compact = MediaQuery.sizeOf(context).height < 700;

    return Scaffold(
      backgroundColor: colors.bgBase,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.md,
                  AppSpacing.sm,
                  AppSpacing.xs,
                  0,
                ),
                child: Row(
                  children: [
                    AppLogo(size: compact ? 40 : 48),
                    const Spacer(),
                    if (!_isLast)
                      TextButton(
                        onPressed: _goToRegister,
                        child: Text(
                          'Skip',
                          style: AppTextTheme.labelLarge.copyWith(
                            color: colors.textSecondary,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              Expanded(
                child: PageView.builder(
                  controller: _pageController,
                  itemCount: onboardingSlides.length,
                  onPageChanged: (index) => setState(() => _index = index),
                  itemBuilder: (context, index) {
                    return _OnboardingCard(
                      slide: onboardingSlides[index],
                      pageController: _pageController,
                      index: index,
                      compact: compact,
                    );
                  },
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              _OnboardingDots(
                count: onboardingSlides.length,
                index: _index,
              ),
              const SizedBox(height: AppSpacing.lg),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
                child: AppButton(
                  label: _isLast ? 'Get Started' : 'Next',
                  onPressed: _goNext,
                ),
              ),
              const SizedBox(height: AppSpacing.xxl),
            ],
          ),
        ),
      ),
    );
  }
}

class _OnboardingCard extends StatelessWidget {
  const _OnboardingCard({
    required this.slide,
    required this.pageController,
    required this.index,
    required this.compact,
  });

  final OnboardingSlide slide;
  final PageController pageController;
  final int index;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final colors = context.luminaColors;
    return AnimatedBuilder(
      animation: pageController,
      builder: (context, child) {
        var scale = 1.0;
        if (pageController.hasClients && pageController.position.haveDimensions) {
          final page = pageController.page ?? pageController.initialPage.toDouble();
          final delta = (page - index).abs();
          scale = (1.0 - delta * 0.08).clamp(0.9, 1.0);
        }
        return Transform.scale(scale: scale, child: child);
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(
          vertical: AppSpacing.sm,
          horizontal: AppSpacing.xs,
        ),
        child: AppCard(
          padding: EdgeInsets.zero,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: ClipRRect(
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(AppSpacing.xxxl),
                  ),
                  child: Image.asset(
                    slide.imageAsset,
                    fit: BoxFit.cover,
                    width: double.infinity,
                    filterQuality: FilterQuality.medium,
                    gaplessPlayback: true,
                  ),
                ),
              ),
              Padding(
                padding: EdgeInsets.fromLTRB(
                  AppSpacing.lg,
                  compact ? AppSpacing.md : AppSpacing.lg,
                  AppSpacing.lg,
                  compact ? AppSpacing.md : AppSpacing.lg,
                ),
                child: Column(
                  children: [
                    Text(
                      slide.title,
                      textAlign: TextAlign.center,
                      style: (compact ? AppTextTheme.titleMedium : AppTextTheme.titleLarge)
                          .copyWith(color: colors.textPrimary),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    Text(
                      slide.subtitle,
                      textAlign: TextAlign.center,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextTheme.bodyMedium.copyWith(color: colors.textSecondary),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _OnboardingDots extends StatelessWidget {
  const _OnboardingDots({
    required this.count,
    required this.index,
  });

  final int count;
  final int index;

  @override
  Widget build(BuildContext context) {
    final colors = context.luminaColors;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List<Widget>.generate(count, (i) {
        final selected = i == index;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
          margin: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
          height: AppSpacing.sm,
          width: selected ? AppSpacing.xl : AppSpacing.sm,
          decoration: BoxDecoration(
            color: selected ? colors.primary : colors.border,
            borderRadius: BorderRadius.circular(AppSpacing.xs),
          ),
        );
      }),
    );
  }
}

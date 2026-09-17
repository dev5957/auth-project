/// Slides d’onboarding provisoires (textes et images remplaçables).
class OnboardingSlide {
  const OnboardingSlide({
    required this.title,
    required this.subtitle,
    required this.imageAsset,
  });

  final String title;
  final String subtitle;
  final String imageAsset;
}

const List<OnboardingSlide> onboardingSlides = [
  OnboardingSlide(
    title: 'Discover',
    subtitle: 'Discover what is around you.',
    imageAsset: 'assets/onboarding/dmytro-koplyk-kdN49Gc01_0-unsplash.jpg',
  ),
  OnboardingSlide(
    title: 'Connect',
    subtitle: 'Create connections around the things you discover.',
    imageAsset: 'assets/onboarding/elodie-debard-3suUDohyMZ0-unsplash.jpg',
  ),
  OnboardingSlide(
    title: 'Explore',
    subtitle: 'Explore new places and experiences.',
    imageAsset: 'assets/onboarding/hanna-lazar-dLLvu1ipYF0-unsplash.jpg',
  ),
  OnboardingSlide(
    title: 'Share',
    subtitle: 'Share your experiences with the community.',
    imageAsset: 'assets/onboarding/vadim-sadovski-OxHm0L9_6ng-unsplash.jpg',
  ),
  OnboardingSlide(
    title: 'Welcome to Lumina',
    subtitle: 'Your journey starts here.',
    imageAsset: 'assets/onboarding/william-veitch-zVkeONx-3So-unsplash.jpg',
  ),
];

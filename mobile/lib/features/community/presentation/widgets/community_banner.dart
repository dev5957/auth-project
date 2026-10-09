import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_text_theme.dart';

class CommunityBanner extends StatelessWidget {
  const CommunityBanner({
    super.key,
    this.readUrl,
    this.height = 140,
    this.onEdit,
  });

  final String? readUrl;
  final double height;
  final VoidCallback? onEdit;

  @override
  Widget build(BuildContext context) {
    final colors = context.luminaColors;
    final image = readUrl;
    final banner = Container(
      key: const ValueKey('community-identity-banner'),
      height: height,
      width: double.infinity,
      color: colors.bgSurface,
      alignment: Alignment.center,
      child: image == null
          ? Text(
              'Bannière',
              key: const ValueKey('community-placeholder-Bannière'),
              style: AppTextTheme.bodyMedium.copyWith(color: colors.textSecondary),
            )
          : Image.network(
              image,
              key: const ValueKey('community-identity-banner-image'),
              fit: BoxFit.cover,
              width: double.infinity,
              height: height,
              errorBuilder: (_, __, ___) => Icon(
                Icons.image_outlined,
                color: colors.textSecondary,
              ),
            ),
    );

    if (onEdit == null) {
      return banner;
    }
    return GestureDetector(
      key: const ValueKey('community-identity-banner-edit'),
      behavior: HitTestBehavior.opaque,
      onTap: onEdit,
      child: banner,
    );
  }
}

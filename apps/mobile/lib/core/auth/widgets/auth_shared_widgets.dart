import 'package:flutter/material.dart';

import 'package:mobile/services/app_strings.dart';
import 'package:mobile/theme/app_colors.dart';
import 'package:mobile/theme/app_theme.dart';
import 'package:mobile/theme/app_typography.dart';

class AuthBackgroundDecorations extends StatelessWidget {
  const AuthBackgroundDecorations({super.key});

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: IgnorePointer(
        child: Stack(
          children: [
            Positioned(
              top: -100,
              right: -100,
              child: Container(
                width: 500,
                height: 500,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.secondaryContainer.withValues(alpha: 0.2),
                ),
              ),
            ),
            Positioned(
              bottom: -150,
              left: -150,
              child: Container(
                width: 600,
                height: 600,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.tertiaryFixed.withValues(alpha: 0.1),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class AuthFooterLinks extends StatelessWidget {
  const AuthFooterLinks({super.key});

  @override
  Widget build(BuildContext context) {
    return Wrap(
      alignment: WrapAlignment.center,
      spacing: AppSpacing.md,
      runSpacing: AppSpacing.xs,
      children: [
        Text(
          AppStrings.privacyPolicy,
          style: AppTypography.labelMd.copyWith(
            color: AppColors.inversePrimary,
          ),
        ),
        Text(
          AppStrings.termsConditions,
          style: AppTypography.labelMd.copyWith(
            color: AppColors.inversePrimary,
          ),
        ),
        Text(
          AppStrings.support,
          style: AppTypography.labelMd.copyWith(
            color: AppColors.inversePrimary,
          ),
        ),
      ],
    );
  }
}

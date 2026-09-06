import 'dart:ui';
import 'package:flutter/material.dart';
import '../services/app_strings.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../theme/app_typography.dart';

class TopBar extends StatelessWidget implements PreferredSizeWidget {
  const TopBar({super.key});

  @override
  Size get preferredSize => const Size.fromHeight(64.0);

  @override
  Widget build(BuildContext context) {
    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 12.0, sigmaY: 12.0),
        child: Container(
          height: 64.0,
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.marginMobile,
          ),
          decoration: BoxDecoration(
            color: AppColors.surface.withValues(alpha: 0.8),
            border: Border(
              bottom: BorderSide(
                color: AppColors.outlineVariant.withValues(alpha: 0.1),
                width: 1.0,
              ),
            ),
          ),
          child: Row(
            children: [
              const Icon(
                Icons.notifications_outlined,
                color: AppColors.onSurfaceVariant,
              ),
              Expanded(
                child: Text(
                  AppStrings.appTitle,
                  style: AppTypography.headlineLgMobile.copyWith(
                    color: AppColors.primary,
                  ),
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const Icon(Icons.menu, color: AppColors.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }
}

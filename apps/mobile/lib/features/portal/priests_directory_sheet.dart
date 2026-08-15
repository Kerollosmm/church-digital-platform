import 'package:flutter/material.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_theme.dart';
import '../../theme/app_typography.dart';
import 'portal_models.dart';
import 'portal_repository.dart';

class PriestsDirectorySheet extends StatelessWidget {
  const PriestsDirectorySheet({super.key, required this.repository});

  final PortalRepository repository;

  static Future<void> show(BuildContext context, PortalRepository repository) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => PriestsDirectorySheet(repository: repository),
    );
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.7,
      minChildSize: 0.4,
      maxChildSize: 0.9,
      builder: (context, scrollController) {
        return Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(
              top: Radius.circular(AppRadius.xl),
            ),
          ),
          child: Column(
            children: [
              Container(
                margin: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.outlineVariant,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.md,
                  vertical: AppSpacing.xs,
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.church,
                      color: AppColors.primary,
                      size: 28,
                    ),
                    const SizedBox(width: AppSpacing.xs),
                    Expanded(
                      child: Text(
                        'الآباء الكهنة ومواعيد الاعترافات',
                        style: AppTypography.headlineMd.copyWith(
                          color: AppColors.primary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const Divider(),
              Expanded(
                child: FutureBuilder<List<PriestItem>>(
                  future: repository.priests(),
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    final priests = snapshot.data ?? [];
                    if (priests.isEmpty) {
                      return Center(
                        child: Text(
                          'لا يوجد بيانات للآباء حالياً',
                          style: AppTypography.bodyMd.copyWith(
                            color: AppColors.onSurfaceVariant,
                          ),
                        ),
                      );
                    }

                    return ListView.separated(
                      controller: scrollController,
                      padding: const EdgeInsets.all(AppSpacing.md),
                      itemCount: priests.length,
                      separatorBuilder: (_, _) =>
                          const SizedBox(height: AppSpacing.sm),
                      itemBuilder: (context, index) {
                        final priest = priests[index];
                        return Container(
                          padding: const EdgeInsets.all(AppSpacing.md),
                          decoration: BoxDecoration(
                            color: AppColors.surfaceContainerLowest,
                            borderRadius: BorderRadius.circular(AppRadius.lg),
                            border: Border.all(color: AppColors.glassBorder),
                            boxShadow: const [
                              BoxShadow(
                                color: AppColors.cardShadow,
                                blurRadius: 10,
                                offset: Offset(0, 2),
                              ),
                            ],
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              CircleAvatar(
                                radius: 30,
                                backgroundColor: AppColors.primaryContainer,
                                backgroundImage:
                                    priest.photoUrl != null &&
                                        priest.photoUrl!.isNotEmpty
                                    ? NetworkImage(priest.photoUrl!)
                                    : null,
                                child:
                                    (priest.photoUrl == null ||
                                        priest.photoUrl!.isEmpty)
                                    ? const Icon(
                                        Icons.person,
                                        size: 36,
                                        color: AppColors.primary,
                                      )
                                    : null,
                              ),
                              const SizedBox(width: AppSpacing.md),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      priest.name,
                                      style: AppTypography.headlineMd.copyWith(
                                        color: AppColors.primary,
                                        fontSize: 16,
                                      ),
                                    ),
                                    if (priest.bio != null &&
                                        priest.bio!.isNotEmpty) ...[
                                      const SizedBox(height: 4),
                                      Text(
                                        priest.bio!,
                                        style: AppTypography.bodyMd.copyWith(
                                          color: AppColors.onSurfaceVariant,
                                        ),
                                      ),
                                    ],
                                    if (priest.visitationHours != null &&
                                        priest.visitationHours!.isNotEmpty) ...[
                                      const SizedBox(height: AppSpacing.xs),
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 8,
                                          vertical: 4,
                                        ),
                                        decoration: BoxDecoration(
                                          color: AppColors.secondaryContainer
                                              .withValues(alpha: 0.4),
                                          borderRadius: BorderRadius.circular(
                                            AppRadius.sm,
                                          ),
                                        ),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            const Icon(
                                              Icons.access_time,
                                              size: 16,
                                              color: AppColors.secondary,
                                            ),
                                            const SizedBox(width: 4),
                                            Flexible(
                                              child: Text(
                                                'مواعيد المقابلات: ${priest.visitationHours}',
                                                style: AppTypography.labelMd
                                                    .copyWith(
                                                      color: AppColors
                                                          .onSecondaryContainer,
                                                    ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

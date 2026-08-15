import 'package:flutter/material.dart';
import 'package:mobile/features/booking/slot_grid_screen.dart';
import 'package:mobile/repositories/booking_repository.dart';
import 'package:mobile/services/app_strings.dart';
import 'package:mobile/theme/app_colors.dart';
import 'package:mobile/theme/app_theme.dart';
import 'package:mobile/theme/app_typography.dart';

class ServicesListScreen extends StatelessWidget {
  const ServicesListScreen({super.key, required this.repository});
  final BookingRepository repository;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(
        title: Text(
          AppStrings.selectSlot,
          style: AppTypography.headlineMd.copyWith(color: AppColors.primary),
        ),
        backgroundColor: AppColors.surface,
        elevation: 0,
        centerTitle: true,
      ),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: repository.fetchServices(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final rows = snapshot.data!;
          if (rows.isEmpty) {
            return Center(
              child: Text(
                AppStrings.notFoundError,
                style: AppTypography.bodyLg.copyWith(
                  color: AppColors.onSurfaceVariant,
                ),
              ),
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.all(AppSpacing.marginMobile),
            itemCount: rows.length,
            separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.sm),
            itemBuilder: (_, i) {
              final service = rows[i];
              final title = service['title_ar'] as String? ?? '';
              final location = service['location'] as String?;
              final priceFrom = service['price_from'];

              return Material(
                color: AppColors.surfaceContainerLowest,
                borderRadius: BorderRadius.circular(AppRadius.lg),
                child: InkWell(
                  borderRadius: BorderRadius.circular(AppRadius.lg),
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => SlotGridScreen(
                        serviceId: service['id'] as int,
                        repository: repository,
                      ),
                    ),
                  ),
                  child: Container(
                    padding: const EdgeInsets.all(AppSpacing.sm),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(AppRadius.lg),
                      border: Border.all(
                        color: AppColors.outlineVariant.withValues(alpha: 0.5),
                      ),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 44,
                          height: 44,
                          decoration: const BoxDecoration(
                            color: AppColors.surfaceContainerHigh,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.event_outlined,
                            color: AppColors.primary,
                          ),
                        ),
                        const SizedBox(width: AppSpacing.sm),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                title,
                                style: AppTypography.headlineMd.copyWith(
                                  color: AppColors.primary,
                                  fontSize: 20,
                                ),
                              ),
                              if (location != null && location.isNotEmpty) ...[
                                const SizedBox(height: AppSpacing.xs / 2),
                                Row(
                                  children: [
                                    const Icon(
                                      Icons.location_on_outlined,
                                      size: 16,
                                      color: AppColors.onSurfaceVariant,
                                    ),
                                    const SizedBox(width: 4),
                                    Expanded(
                                      child: Text(
                                        location,
                                        style: AppTypography.bodyMd.copyWith(
                                          color: AppColors.onSurfaceVariant,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                              if (priceFrom != null) ...[
                                const SizedBox(height: AppSpacing.xs / 2),
                                Text(
                                  '${AppStrings.priceFrom} $priceFrom ${AppStrings.egp}',
                                  style: AppTypography.labelMd.copyWith(
                                    color: AppColors.secondary,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                        const Icon(
                          Icons.chevron_left,
                          color: AppColors.onSurfaceVariant,
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

import 'package:flutter/material.dart';
import '../features/portal/portal_models.dart';
import '../features/portal/portal_repository.dart';
import '../services/app_strings.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../theme/app_typography.dart';

class HomeHubScreen extends StatefulWidget {
  const HomeHubScreen({
    super.key,
    required this.repository,
    this.onTapMass,
    this.onTapConfession,
    this.onTapBooking,
    this.onTapVideos,
    this.onTapComplaints,
  });

  final PortalRepository repository;
  final VoidCallback? onTapMass;
  final VoidCallback? onTapConfession;
  final VoidCallback? onTapBooking;
  final VoidCallback? onTapVideos;
  final VoidCallback? onTapComplaints;

  @override
  State<HomeHubScreen> createState() => _HomeHubScreenState();
}

class _HomeHubScreenState extends State<HomeHubScreen> {
  late Future<List<AnnouncementItem>> _announcementsFuture;

  @override
  void initState() {
    super.initState();
    _announcementsFuture = widget.repository.announcements();
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.marginMobile),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Section: Announcements
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                AppStrings.announcementsTitle,
                style: AppTypography.headlineMd.copyWith(
                  color: AppColors.primary,
                ),
              ),
              Text(
                AppStrings.viewAll,
                style: AppTypography.labelMd.copyWith(
                  color: AppColors.secondary,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          FutureBuilder<List<AnnouncementItem>>(
            future: _announcementsFuture,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const SizedBox(
                  height: 150,
                  child: Center(child: CircularProgressIndicator()),
                );
              }
              final announcements = snapshot.data ?? [];
              if (announcements.isEmpty) {
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
                  child: Text(
                    AppStrings.noAnnouncements,
                    style: AppTypography.bodyMd.copyWith(
                      color: AppColors.onSurfaceVariant,
                    ),
                  ),
                );
              }

              return SizedBox(
                height: 150.0,
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  itemCount: announcements.length,
                  itemBuilder: (context, index) {
                    final item = announcements[index];
                    final accentColor = index == 0
                        ? AppColors.secondary
                        : (index == 1 ? AppColors.primary : AppColors.outline);
                    final icon = index == 0
                        ? Icons.event
                        : (index == 1 ? Icons.group : Icons.volunteer_activism);

                    return Container(
                      width: 300.0,
                      margin: const EdgeInsets.only(left: AppSpacing.sm),
                      decoration: BoxDecoration(
                        color: AppColors.surfaceContainerLowest,
                        borderRadius: BorderRadius.circular(AppRadius.lg),
                        border: Border.all(color: AppColors.glassBorder),
                        boxShadow: const [
                          BoxShadow(
                            color: AppColors.cardShadow,
                            blurRadius: 20,
                            offset: Offset(0, 4),
                          ),
                        ],
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(AppRadius.lg),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(height: 4.0, color: accentColor),
                            Padding(
                              padding: const EdgeInsets.all(AppSpacing.sm),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Icon(
                                        icon,
                                        color: accentColor,
                                        size: 20.0,
                                      ),
                                      if (item.categoryAr != null) ...[
                                        const SizedBox(width: AppSpacing.xs),
                                        Text(
                                          item.categoryAr!,
                                          style: AppTypography.labelMd.copyWith(
                                            color: AppColors.onSurfaceVariant,
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                  const SizedBox(height: AppSpacing.xs),
                                  Text(
                                    item.titleAr,
                                    style: AppTypography.bodyLg.copyWith(
                                      fontWeight: FontWeight.bold,
                                      color: AppColors.primary,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  const SizedBox(height: 4.0),
                                  Text(
                                    item.bodyAr,
                                    style: AppTypography.bodyMd.copyWith(
                                      color: AppColors.onSurfaceVariant,
                                    ),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              );
            },
          ),

          const SizedBox(height: AppSpacing.lg),

          // Section: Quick Services
          Text(
            AppStrings.quickServicesTitle,
            style: AppTypography.headlineMd.copyWith(color: AppColors.primary),
          ),
          const SizedBox(height: AppSpacing.xs),
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: AppSpacing.sm,
            crossAxisSpacing: AppSpacing.sm,
            childAspectRatio: 1.3,
            children: [
              _buildQuickCard(
                label: AppStrings.quickMass,
                icon: Icons.calendar_month,
                onTap: widget.onTapMass,
              ),
              _buildQuickCard(
                label: AppStrings.quickConfession,
                icon: Icons.church,
                onTap: widget.onTapConfession,
              ),
              _buildQuickCard(
                label: AppStrings.quickBooking,
                icon: Icons.event_available,
                onTap: widget.onTapBooking,
              ),
              _buildQuickCard(
                label: AppStrings.quickVideos,
                icon: Icons.movie,
                onTap: widget.onTapVideos,
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          _buildQuickCard(
            label: AppStrings.quickComplaints,
            icon: Icons.edit_note,
            onTap: widget.onTapComplaints,
          ),

          const SizedBox(height: AppSpacing.lg),

          // Section: Featured Verse Hero
          Container(
            height: 256.0,
            width: double.infinity,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AppRadius.lg),
              color: AppColors.primaryContainer,
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.transparent,
                  AppColors.primaryContainer.withValues(alpha: 0.9),
                ],
              ),
            ),
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Column(
              mainAxisAlignment: dynamicPaddingAlignment(context),
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.xs,
                    vertical: 4.0,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.secondary.withValues(alpha: 0.8),
                    borderRadius: BorderRadius.circular(8.0),
                  ),
                  child: Text(
                    AppStrings.meditationToday,
                    style: AppTypography.labelMd.copyWith(color: Colors.white),
                  ),
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  AppStrings.verseText,
                  style: AppTypography.headlineLg.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4.0),
                Text(
                  AppStrings.verseRef,
                  style: AppTypography.bodyMd.copyWith(
                    color: Colors.white.withValues(alpha: 0.9),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static MainAxisAlignment dynamicPaddingAlignment(BuildContext context) =>
      MainAxisAlignment.end;

  Widget _buildQuickCard({
    required String label,
    required IconData icon,
    VoidCallback? onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        child: Container(
          padding: const EdgeInsets.all(AppSpacing.sm),
          decoration: BoxDecoration(
            color: AppColors.surfaceContainerLowest,
            borderRadius: BorderRadius.circular(AppRadius.lg),
            border: Border.all(color: AppColors.glassBorder),
            boxShadow: const [
              BoxShadow(
                color: AppColors.cardShadow,
                blurRadius: 20,
                offset: Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 48.0,
                height: 48.0,
                decoration: const BoxDecoration(
                  color: AppColors.surfaceContainerLow,
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: AppColors.primary, size: 28.0),
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                label,
                style: AppTypography.bodyMd.copyWith(
                  fontWeight: FontWeight.bold,
                  color: AppColors.primary,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:mobile/features/booking/booking_detail_screen.dart';
import 'package:mobile/repositories/booking_repository.dart';
import 'package:mobile/services/app_strings.dart';
import 'package:mobile/theme/app_colors.dart';
import 'package:mobile/theme/app_theme.dart';
import 'package:mobile/theme/app_typography.dart';

import 'package:mobile/core/auth/auth_gateway.dart';

class SlotGridScreen extends StatefulWidget {
  const SlotGridScreen({
    super.key,
    required this.serviceId,
    required this.repository,
    this.gateway,
    this.isLoggedIn,
  });

  final int serviceId;
  final BookingRepository repository;
  final AuthGateway? gateway;
  final bool Function()? isLoggedIn;

  @override
  State<SlotGridScreen> createState() => _SlotGridScreenState();
}

class _SlotGridScreenState extends State<SlotGridScreen> {
  late Future<List<Map<String, dynamic>>> _slots;

  @override
  void initState() {
    super.initState();
    _slots = widget.repository.slotsForService(widget.serviceId);
  }

  String _formatTime(dynamic rawTime) {
    if (rawTime == null) return '';
    final str = rawTime.toString();
    if (str.length >= 16 && str.contains('T')) {
      return str.substring(11, 16);
    }
    return str;
  }

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
        future: _slots,
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final slots = snapshot.data!;
          if (slots.isEmpty) {
            return Center(
              child: Text(
                AppStrings.notFoundError,
                style: AppTypography.bodyLg.copyWith(
                  color: AppColors.onSurfaceVariant,
                ),
              ),
            );
          }

          final firstSlot = slots.first;
          final serviceLocation = firstSlot['location'] as String?;

          return ListView(
            padding: const EdgeInsets.all(AppSpacing.marginMobile),
            children: [
              // Legend row
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  _buildLegendItem(
                    AppColors.slotAvailable,
                    AppStrings.statusAvailable,
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  _buildLegendItem(
                    AppColors.slotBooked,
                    AppStrings.statusBooked,
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  _buildLegendItem(
                    AppColors.slotClosed,
                    AppStrings.statusClosed,
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),

              // Event details card (if location exists or arrive early notice)
              Container(
                padding: const EdgeInsets.all(AppSpacing.sm),
                decoration: BoxDecoration(
                  color: AppColors.surfaceContainerLowest,
                  borderRadius: BorderRadius.circular(AppRadius.lg),
                  border: Border.all(
                    color: AppColors.outlineVariant.withValues(alpha: 0.5),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (serviceLocation != null &&
                        serviceLocation.isNotEmpty) ...[
                      Row(
                        children: [
                          const Icon(
                            Icons.location_on_outlined,
                            size: 18,
                            color: AppColors.onSurfaceVariant,
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              serviceLocation,
                              style: AppTypography.bodyMd.copyWith(
                                color: AppColors.onSurfaceVariant,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.xs),
                    ],
                    Row(
                      children: [
                        const Icon(
                          Icons.info_outline,
                          size: 18,
                          color: AppColors.onSurfaceVariant,
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            AppStrings.arriveEarlyNotice,
                            style: AppTypography.bodyMd.copyWith(
                              color: AppColors.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.md),

              // Slots list
              ...slots.map((s) {
                final status = s['slot_status'] as String? ?? 'AVAILABLE';
                final isAvailable = status == 'AVAILABLE';
                final isBooked = status == 'BOOKED';
                final isClosed = status == 'CLOSED';

                final title = s['title_ar'] as String? ?? '';
                final startsAt = _formatTime(s['starts_at']);
                final endsAt = _formatTime(s['ends_at']);
                final timeDisplay = endsAt.isNotEmpty
                    ? '$startsAt - $endsAt'
                    : startsAt;
                final availableSeats = s['available_seats'];

                Color chipText;
                Color chipBg;
                IconData chipIcon;
                String statusLabel;

                if (isAvailable) {
                  chipText = AppColors.slotAvailable;
                  chipBg = AppColors.slotAvailableBg;
                  chipIcon = Icons.check_circle_outline;
                  statusLabel = AppStrings.statusAvailable;
                } else if (isBooked) {
                  chipText = AppColors.slotBooked;
                  chipBg = AppColors.slotBookedBg;
                  chipIcon = Icons.group_off_outlined;
                  statusLabel = AppStrings.statusBooked;
                } else {
                  chipText = AppColors.slotClosed;
                  chipBg = AppColors.slotClosedBg;
                  chipIcon = Icons.block_outlined;
                  statusLabel = AppStrings.statusClosed;
                }

                return Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                  child: Material(
                    color: isAvailable
                        ? AppColors.surfaceContainerLowest
                        : AppColors.surfaceContainer.withValues(
                            alpha: isClosed ? 0.4 : 0.6,
                          ),
                    borderRadius: BorderRadius.circular(AppRadius.lg),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(AppRadius.lg),
                      onTap: isAvailable
                          ? () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => BookingDetailScreen(
                                  slot: s,
                                  repository: widget.repository,
                                  gateway: widget.gateway,
                                  isLoggedIn: widget.isLoggedIn,
                                ),
                              ),
                            )
                          : null,
                      child: Container(
                        padding: const EdgeInsets.all(AppSpacing.sm),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(AppRadius.lg),
                          border: Border.all(
                            color: isClosed
                                ? AppColors.errorContainer
                                : AppColors.outlineVariant.withValues(
                                    alpha: 0.5,
                                  ),
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      if (title.isNotEmpty)
                                        Text(
                                          title,
                                          style: AppTypography.headlineMd
                                              .copyWith(
                                                color: isAvailable
                                                    ? AppColors.primary
                                                    : AppColors
                                                          .onSurfaceVariant,
                                                fontSize: 18,
                                              ),
                                        ),
                                      if (timeDisplay.isNotEmpty) ...[
                                        const SizedBox(height: 2),
                                        Text(
                                          timeDisplay,
                                          style: AppTypography.bodyMd.copyWith(
                                            color: AppColors.onSurfaceVariant,
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 4,
                                  ),
                                  decoration: BoxDecoration(
                                    color: chipBg,
                                    borderRadius: BorderRadius.circular(
                                      AppRadius.full,
                                    ),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(chipIcon, size: 14, color: chipText),
                                      const SizedBox(width: 4),
                                      Text(
                                        statusLabel,
                                        style: AppTypography.labelMd.copyWith(
                                          color: chipText,
                                          fontSize: 12,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: AppSpacing.xs),
                            if (isAvailable && availableSeats != null)
                              Text(
                                '$availableSeats ${AppStrings.availableSeatsLabel}',
                                style: AppTypography.labelMd.copyWith(
                                  color: AppColors.secondary,
                                  fontSize: 12,
                                ),
                              )
                            else if (isBooked)
                              Text(
                                AppStrings.noAvailableSeats,
                                style: AppTypography.labelMd.copyWith(
                                  color: AppColors.outline,
                                  fontSize: 12,
                                ),
                              )
                            else if (isClosed)
                              Text(
                                AppStrings.notAvailablePublic,
                                style: AppTypography.labelMd.copyWith(
                                  color: AppColors.outline,
                                  fontSize: 12,
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              }),
            ],
          );
        },
      ),
    );
  }

  Widget _buildLegendItem(Color color, String text) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 4),
        Text(
          text,
          style: AppTypography.labelMd.copyWith(
            color: AppColors.onSurfaceVariant,
            fontSize: 12,
          ),
        ),
      ],
    );
  }
}

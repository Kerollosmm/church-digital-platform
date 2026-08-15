import 'package:flutter/material.dart';
import 'package:mobile/controllers/run_guarded.dart';
import 'package:mobile/features/booking/services_list_screen.dart';
import 'package:mobile/models/booking_status.dart';
import 'package:mobile/models/resolved_booking_status.dart';
import 'package:mobile/repositories/booking_repository.dart';
import 'package:mobile/services/app_strings.dart';
import 'package:mobile/theme/app_colors.dart';
import 'package:mobile/theme/app_theme.dart';
import 'package:mobile/theme/app_typography.dart';
import 'package:qr_flutter/qr_flutter.dart';

class BookingTicketScreen extends StatefulWidget {
  const BookingTicketScreen({
    super.key,
    required this.booking,
    required this.repository,
  });

  final Map<String, dynamic> booking;
  final BookingRepository repository;

  @override
  State<BookingTicketScreen> createState() => _BookingTicketScreenState();
}

class _BookingTicketScreenState extends State<BookingTicketScreen> {
  bool _isCancelling = false;

  Future<void> _cancelBooking() async {
    setState(() => _isCancelling = true);
    await runGuarded(
      () async {
        final id = widget.booking['id'];
        if (id is int) {
          await widget.repository.cancelBooking(id);
        } else if (id is num) {
          await widget.repository.cancelBooking(id.toInt());
        }
        if (!mounted) return;
        Navigator.pop(context);
      },
      onError: (message) {
        if (!mounted) return;
        setState(() => _isCancelling = false);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(message)));
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final bookingId = widget.booking['id'];
    final rawStatus = widget.booking['status'] as String? ?? 'CONFIRMED';
    final statusObj = BookingStatus.fromDb(rawStatus);
    final resolvedStatus = resolveBookingStatus(statusObj);

    final rawServiceName = widget.booking['service_name'];
    final serviceName = rawServiceName != null
        ? rawServiceName.toString().trim()
        : '';

    final paidAmount = widget.booking['paid_amount'];
    final rawCreatedAt = widget.booking['created_at'];
    final createdAt = rawCreatedAt != null
        ? rawCreatedAt.toString().trim()
        : '';

    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(
        title: const Text(AppStrings.bookingConfirmedSuccess),
        backgroundColor: AppColors.surface,
        foregroundColor: AppColors.onSurface,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.marginMobile),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // Success Header
                Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    color: AppColors.surfaceContainerHighest,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: AppColors.outlineVariant.withValues(alpha: 0.4),
                    ),
                  ),
                  child: const Icon(
                    Icons.check_circle_outline,
                    color: AppColors.secondary,
                    size: 32,
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  AppStrings.bookingConfirmedSuccess,
                  style: AppTypography.headlineLgMobile.copyWith(
                    color: AppColors.primary,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  '${AppStrings.bookingNumberLabel} #$bookingId',
                  style: AppTypography.bodyMd.copyWith(
                    color: AppColors.onSurfaceVariant,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: AppSpacing.lg),

                // Ticket Card
                Container(
                  decoration: BoxDecoration(
                    color: AppColors.surfaceContainerLowest,
                    borderRadius: BorderRadius.circular(AppRadius.lg),
                    border: Border.all(
                      color: AppColors.outlineVariant.withValues(alpha: 0.3),
                    ),
                    boxShadow: const [
                      BoxShadow(
                        color: AppColors.cardShadow,
                        blurRadius: 20,
                        offset: Offset(0, 4),
                      ),
                    ],
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: Column(
                    children: [
                      // Header
                      Container(
                        padding: const EdgeInsets.all(AppSpacing.md),
                        color: AppColors.primaryContainer,
                        child: Row(
                          children: [
                            Expanded(
                              child: serviceName.isNotEmpty
                                  ? Text(
                                      serviceName,
                                      style: AppTypography.headlineMd.copyWith(
                                        color: AppColors.onPrimary,
                                      ),
                                    )
                                  : Text(
                                      '${AppStrings.bookingNumberPrefix}$bookingId',
                                      style: AppTypography.headlineMd.copyWith(
                                        color: AppColors.onPrimary,
                                      ),
                                    ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: resolvedStatus.color.withValues(
                                  alpha: 0.2,
                                ),
                                borderRadius: BorderRadius.circular(
                                  AppRadius.full,
                                ),
                                border: Border.all(
                                  color: resolvedStatus.color.withValues(
                                    alpha: 0.4,
                                  ),
                                ),
                              ),
                              child: Text(
                                resolvedStatus.label,
                                style: AppTypography.labelMd.copyWith(
                                  color: resolvedStatus.color,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),

                      // Ticket Body (Details)
                      Padding(
                        padding: const EdgeInsets.all(AppSpacing.md),
                        child: Column(
                          children: [
                            _buildDataRow(
                              AppStrings.bookingNumberLabel,
                              '#$bookingId',
                            ),
                            if (serviceName.isNotEmpty) ...[
                              const Divider(height: AppSpacing.md),
                              _buildDataRow(
                                AppStrings.serviceDetails,
                                serviceName,
                              ),
                            ],
                            if (paidAmount != null) ...[
                              const Divider(height: AppSpacing.md),
                              _buildDataRow(
                                AppStrings.paidAmountLabel,
                                '$paidAmount ${AppStrings.egp}',
                              ),
                            ],
                            if (createdAt.isNotEmpty) ...[
                              const Divider(height: AppSpacing.md),
                              _buildDataRow(
                                AppStrings.createdAtLabel,
                                createdAt,
                              ),
                            ],
                          ],
                        ),
                      ),

                      // QR Code Section
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(AppSpacing.md),
                        color: AppColors.surfaceContainerLow,
                        child: Column(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(AppSpacing.xs),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(
                                  AppRadius.sm,
                                ),
                                border: Border.all(
                                  color: AppColors.outlineVariant.withValues(
                                    alpha: 0.4,
                                  ),
                                ),
                              ),
                              child: BookingQrView(
                                payload:
                                    'CHURCH-TICKET-V1:$bookingId:${widget.booking['service_name'] ?? ''}',
                              ),
                            ),
                            const SizedBox(height: AppSpacing.sm),
                            Text(
                              AppStrings.showQrNotice,
                              style: AppTypography.labelMd.copyWith(
                                color: AppColors.onSurfaceVariant,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.lg),

                // Actions Section
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        style: AppTheme.ghostButton(),
                        onPressed: _isCancelling
                            ? null
                            : () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => ServicesListScreen(
                                      repository: widget.repository,
                                    ),
                                  ),
                                );
                              },
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: const [
                            Icon(Icons.edit_calendar, size: 18),
                            SizedBox(width: AppSpacing.xs),
                            Text(AppStrings.editBooking),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: OutlinedButton(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.error,
                          side: const BorderSide(color: AppColors.error),
                          minimumSize: const Size(64, 48),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(AppRadius.sm),
                          ),
                        ),
                        onPressed: _isCancelling ? null : _cancelBooking,
                        child: _isCancelling
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: AppColors.error,
                                ),
                              )
                            : Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: const [
                                  Icon(Icons.cancel, size: 18),
                                  SizedBox(width: AppSpacing.xs),
                                  Text(AppStrings.cancelBooking),
                                ],
                              ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.md),
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text(
                    AppStrings.backToHome,
                    style: AppTypography.labelMd.copyWith(
                      color: AppColors.primary,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDataRow(String label, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: AppTypography.labelMd.copyWith(
            color: AppColors.onSurfaceVariant,
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        Flexible(
          child: Text(
            value,
            style: AppTypography.bodyMd.copyWith(
              color: AppColors.primary,
              fontWeight: FontWeight.w600,
            ),
            textAlign: TextAlign.end,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}

class BookingQrView extends StatelessWidget {
  const BookingQrView({super.key, required this.payload});
  final String payload;

  @override
  Widget build(BuildContext context) {
    return QrImageView(
      data: payload,
      version: QrVersions.auto,
      size: 128.0,
      backgroundColor: Colors.transparent,
      eyeStyle: const QrEyeStyle(
        eyeShape: QrEyeShape.square,
        color: Color(0xFF1E293B),
      ),
      dataModuleStyle: const QrDataModuleStyle(
        dataModuleShape: QrDataModuleShape.square,
        color: Color(0xFF1E293B),
      ),
      errorCorrectionLevel: QrErrorCorrectLevel.M,
    );
  }
}

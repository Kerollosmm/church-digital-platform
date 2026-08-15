import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:mobile/controllers/booking_flow_controller.dart';
import 'package:mobile/controllers/run_guarded.dart';
import 'package:mobile/core/auth/auth_gateway.dart';
import 'package:mobile/core/auth/phone_verify_gate.dart';
import 'package:mobile/models/book_slot_result.dart';
import 'package:mobile/repositories/booking_repository.dart';
import 'package:mobile/services/app_routes.dart';
import 'package:mobile/services/app_strings.dart';
import 'package:mobile/theme/app_colors.dart';
import 'package:mobile/theme/app_theme.dart';
import 'package:mobile/theme/app_typography.dart';

class BookingDetailScreen extends StatefulWidget {
  const BookingDetailScreen({
    super.key,
    required this.slot,
    required this.repository,
    this.gateway,
    this.isLoggedIn,
  });

  final Map<String, dynamic> slot;
  final BookingRepository repository;
  final AuthGateway? gateway;
  final bool Function()? isLoggedIn;

  @override
  State<BookingDetailScreen> createState() => _BookingDetailScreenState();
}

class _BookingDetailScreenState extends State<BookingDetailScreen> {
  bool _optIn = false;
  bool _busy = false;
  late final BookingFlowController _controller;

  @override
  void initState() {
    super.initState();
    _controller = BookingFlowController(widget.repository);
  }

  Future<void> _confirm() async {
    await PhoneVerifyGate.ensureAuth(
      context,
      gateway: resolveAuthGateway(widget.gateway),
      isLoggedIn: widget.isLoggedIn,
      onVerified: () async {
        setState(() => _busy = true);
        await runGuarded(
          () async {
            final slotId = widget.slot['slot_id'] as int;
            final result = await _controller.reserveAndPay(
              slotId: slotId,
              whatsappOptIn: _optIn,
            );
            if (!mounted) return;
            result.fold(
              (failure) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(_controller.localizedMessage(failure))),
                );
              },
              (session) {
                context.pushNamed(
                  AppRoutes.paymentRedirect,
                  extra: session.booking.id,
                );
              },
            );
          },
          onError: (message) {
            if (!mounted) return;
            ScaffoldMessenger.of(
              context,
            ).showSnackBar(SnackBar(content: Text(message)));
          },
        );
        if (mounted) setState(() => _busy = false);
      },
    );
  }

  String _formatDateTime(dynamic raw) {
    if (raw == null) return '';
    final str = raw.toString();
    if (str.length >= 16 && str.contains('T')) {
      final parts = str.split('T');
      final date = parts[0];
      final time = parts[1].substring(0, 5);
      return '$date • $time';
    }
    return str;
  }

  @override
  Widget build(BuildContext context) {
    final title = widget.slot['title_ar'] as String? ?? '';
    final startsAt = _formatDateTime(widget.slot['starts_at']);
    final price = widget.slot['price'];
    final location = widget.slot['location'] as String?;

    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(
        title: Text(
          AppStrings.bookingSummary,
          style: AppTypography.headlineMd.copyWith(color: AppColors.primary),
        ),
        backgroundColor: AppColors.surface,
        elevation: 0,
        centerTitle: true,
      ),
      body: Column(
        children: [
          // Gold Countdown Banner (Static text per architecture spec)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.marginMobile,
              vertical: AppSpacing.xs,
            ),
            color: AppColors.secondaryContainer,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(
                  Icons.timer_outlined,
                  size: 18,
                  color: AppColors.onSecondaryContainer,
                ),
                const SizedBox(width: 8),
                Text(
                  AppStrings.completeBookingPrompt,
                  style: AppTypography.labelMd.copyWith(
                    color: AppColors.onSecondaryContainer,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(AppSpacing.marginMobile),
              children: [
                // Summary Card
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
                      Text(
                        title,
                        style: AppTypography.headlineMd.copyWith(
                          color: AppColors.primary,
                          fontSize: 20,
                        ),
                      ),
                      if (startsAt.isNotEmpty) ...[
                        const SizedBox(height: AppSpacing.xs),
                        Row(
                          children: [
                            const Icon(
                              Icons.access_time,
                              size: 18,
                              color: AppColors.onSurfaceVariant,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              startsAt,
                              style: AppTypography.bodyMd.copyWith(
                                color: AppColors.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ],
                      if (location != null && location.isNotEmpty) ...[
                        const SizedBox(height: AppSpacing.xs),
                        Row(
                          children: [
                            const Icon(
                              Icons.location_on_outlined,
                              size: 18,
                              color: AppColors.onSurfaceVariant,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              location,
                              style: AppTypography.bodyMd.copyWith(
                                color: AppColors.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ],
                      if (price != null) ...[
                        const SizedBox(height: AppSpacing.xs),
                        Row(
                          children: [
                            const Icon(
                              Icons.payments_outlined,
                              size: 18,
                              color: AppColors.secondary,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              '$price ${AppStrings.egp}',
                              style: AppTypography.headlineMd.copyWith(
                                color: AppColors.secondary,
                                fontSize: 18,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.md),

                // Opt-in Checkbox Card
                CheckboxListTile(
                  tileColor: AppColors.surfaceContainerLowest,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppRadius.lg),
                    side: BorderSide(
                      color: AppColors.outlineVariant.withValues(alpha: 0.5),
                    ),
                  ),
                  value: _optIn,
                  onChanged: _busy
                      ? null
                      : (v) => setState(() => _optIn = v ?? false),
                  activeColor: AppColors.primary,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.xs,
                    vertical: AppSpacing.xs / 2,
                  ),
                  title: Text(
                    AppStrings.whatsappOptIn,
                    style: AppTypography.bodyMd.copyWith(
                      color: AppColors.onSurface,
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Bottom Action Sheet Area
          Container(
            padding: const EdgeInsets.all(AppSpacing.marginMobile),
            decoration: BoxDecoration(
              color: AppColors.surfaceContainerLowest,
              boxShadow: const [
                BoxShadow(
                  color: AppColors.cardShadow,
                  blurRadius: 20,
                  offset: Offset(0, -4),
                ),
              ],
            ),
            child: SafeArea(
              top: false,
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      style: AppTheme.ghostButton(),
                      onPressed: _busy ? null : () => Navigator.pop(context),
                      child: Text(
                        AppStrings.cancel,
                        style: AppTypography.labelMd.copyWith(
                          color: AppColors.primary,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: FilledButton(
                      style: AppTheme.navyButton(),
                      onPressed: _busy ? null : _confirm,
                      child: _busy
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: AppColors.onPrimary,
                              ),
                            )
                          : Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(
                                  AppStrings.confirmBooking,
                                  style: AppTypography.labelMd.copyWith(
                                    color: AppColors.onPrimary,
                                  ),
                                ),
                                const SizedBox(width: 6),
                                const Icon(Icons.check, size: 18),
                              ],
                            ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

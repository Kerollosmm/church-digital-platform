import 'package:flutter/material.dart';
import 'package:mobile/controllers/run_guarded.dart';
import 'package:mobile/core/either.dart';
import 'package:mobile/core/failure.dart';
import 'package:mobile/models/booking_checkout_session.dart';
import 'package:mobile/services/app_strings.dart';
import 'package:mobile/theme/app_colors.dart';
import 'package:mobile/theme/app_theme.dart';
import 'package:mobile/theme/app_typography.dart';
import 'package:url_launcher/url_launcher.dart';

class PaymentRedirectScreen extends StatefulWidget {
  const PaymentRedirectScreen({
    super.key,
    required this.bookingId,
    this.checkoutUrl,
    this.onRetryCheckout,
    this.fetchCheckoutUrl,
  });

  final int bookingId;
  final String? checkoutUrl;
  final Future<Either<Failure, BookingCheckoutSession>> Function(int bookingId)?
  onRetryCheckout;
  final Future<String> Function(int bookingId)? fetchCheckoutUrl;

  @override
  State<PaymentRedirectScreen> createState() => _PaymentRedirectScreenState();
}

class _PaymentRedirectScreenState extends State<PaymentRedirectScreen> {
  bool _busy = false;
  int _selectedMethod = 0;
  String? _currentCheckoutUrl;
  String? _errorMessage;

  bool get _hasCheckoutUrl =>
      _currentCheckoutUrl != null && _currentCheckoutUrl!.isNotEmpty;

  @override
  void initState() {
    super.initState();
    _currentCheckoutUrl = widget.checkoutUrl;
    if (!_hasCheckoutUrl && widget.fetchCheckoutUrl == null) {
      _errorMessage = AppStrings.paymentOpenFailed;
    }
  }

  Future<void> _pay() async {
    if (_busy) return;
    setState(() => _busy = true);
    await runGuarded(
      () async {
        String? targetUrl = _currentCheckoutUrl;

        // If no checkoutUrl, user-triggered retry
        if (targetUrl == null || targetUrl.isEmpty) {
          if (widget.onRetryCheckout != null) {
            final res = await widget.onRetryCheckout!(widget.bookingId);
            res.fold(
              (failure) {
                if (mounted) {
                  setState(() => _errorMessage = AppStrings.paymentOpenFailed);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text(AppStrings.paymentOpenFailed)),
                  );
                }
              },
              (session) {
                targetUrl = session.checkoutUrl;
                if (mounted) {
                  setState(() {
                    _currentCheckoutUrl = targetUrl;
                    _errorMessage = null;
                  });
                }
              },
            );
          } else if (widget.fetchCheckoutUrl != null) {
            targetUrl = await widget.fetchCheckoutUrl!(widget.bookingId);
            if (mounted) {
              setState(() {
                _currentCheckoutUrl = targetUrl;
                _errorMessage = null;
              });
            }
          }
        }

        if (targetUrl == null || targetUrl!.isEmpty) {
          if (mounted && _errorMessage == null) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text(AppStrings.paymentOpenFailed)),
            );
          }
          return;
        }

        final opened = await launchUrl(
          Uri.parse(targetUrl!),
          mode: LaunchMode.externalApplication,
        );
        if (!opened && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text(AppStrings.paymentOpenFailed)),
          );
        }
      },
      onError: (message) {
        if (!mounted) return;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(message)));
      },
    );
    if (mounted) setState(() => _busy = false);
  }

  Widget _buildMethodCard({
    required int index,
    required String title,
    required String subtitle,
    required IconData icon,
  }) {
    final isSelected = _selectedMethod == index;
    return InkWell(
      onTap: () => setState(() => _selectedMethod = index),
      borderRadius: BorderRadius.circular(AppRadius.sm),
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.sm),
        decoration: BoxDecoration(
          color: isSelected
              ? AppColors.secondary.withValues(alpha: 0.05)
              : AppColors.surfaceContainerLowest,
          borderRadius: BorderRadius.circular(AppRadius.sm),
          border: Border.all(
            color: isSelected ? AppColors.secondary : AppColors.outlineVariant,
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 24,
              height: 24,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: isSelected
                      ? AppColors.secondary
                      : AppColors.outlineVariant,
                  width: 2,
                ),
                color: isSelected ? AppColors.secondary : Colors.transparent,
              ),
              child: isSelected
                  ? Center(
                      child: Container(
                        width: 8,
                        height: 8,
                        decoration: const BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.white,
                        ),
                      ),
                    )
                  : null,
            ),
            const SizedBox(width: AppSpacing.xs),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: AppTypography.labelMd),
                  Text(
                    subtitle,
                    style: AppTypography.bodyMd.copyWith(
                      color: AppColors.onSurfaceVariant,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
            Icon(icon, color: AppColors.onSurfaceVariant),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text(AppStrings.checkoutTitle)),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.marginMobile),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              AppStrings.checkoutTitle,
              style: AppTypography.headlineLgMobile,
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              AppStrings.checkoutSubtitle,
              style: AppTypography.bodyMd.copyWith(
                color: AppColors.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            Container(
              decoration: AppGlass.panel(),
              padding: const EdgeInsets.all(AppSpacing.sm),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(
                        Icons.account_balance_wallet,
                        color: AppColors.primary,
                      ),
                      const SizedBox(width: AppSpacing.xs),
                      Text(
                        AppStrings.paymentMethodsTitle,
                        style: AppTypography.headlineMd,
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  _buildMethodCard(
                    index: 0,
                    title: AppStrings.cardMethod,
                    subtitle: AppStrings.cardMethodDesc,
                    icon: Icons.credit_card,
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  _buildMethodCard(
                    index: 1,
                    title: AppStrings.fawryMethod,
                    subtitle: AppStrings.fawryMethodDesc,
                    icon: Icons.storefront,
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  _buildMethodCard(
                    index: 2,
                    title: AppStrings.walletMethod,
                    subtitle: AppStrings.walletMethodDesc,
                    icon: Icons.phone_iphone,
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Container(
                    padding: const EdgeInsets.all(AppSpacing.sm),
                    decoration: BoxDecoration(
                      color: AppColors.surfaceContainerLow,
                      borderRadius: BorderRadius.circular(AppRadius.sm),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(
                          Icons.shield,
                          color: AppColors.primary,
                          size: 20,
                        ),
                        const SizedBox(width: AppSpacing.xs),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                AppStrings.securePaymentTitle,
                                style: AppTypography.labelMd,
                              ),
                              const SizedBox(height: 2),
                              Text(
                                AppStrings.securePaymentDesc,
                                style: AppTypography.bodyMd.copyWith(
                                  color: AppColors.onSurfaceVariant,
                                  fontSize: 13,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            Container(
              decoration: AppGlass.panel(),
              padding: const EdgeInsets.all(AppSpacing.sm),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    AppStrings.orderSummaryTitle,
                    style: AppTypography.headlineMd,
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  const Divider(color: AppColors.outlineVariant, height: 1),
                  const SizedBox(height: AppSpacing.xs),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        AppStrings.bookingNumberLabel,
                        style: AppTypography.bodyMd.copyWith(
                          color: AppColors.onSurfaceVariant,
                        ),
                      ),
                      Text(
                        '#${widget.bookingId}',
                        style: AppTypography.labelMd,
                      ),
                    ],
                  ),
                  if (_errorMessage != null) ...[
                    const SizedBox(height: AppSpacing.sm),
                    Container(
                      padding: const EdgeInsets.all(AppSpacing.sm),
                      decoration: BoxDecoration(
                        color: AppColors.error.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(AppRadius.sm),
                        border: Border.all(color: AppColors.error),
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.error_outline,
                            color: AppColors.error,
                          ),
                          const SizedBox(width: AppSpacing.xs),
                          Expanded(
                            child: Text(
                              _errorMessage!,
                              style: AppTypography.bodyMd.copyWith(
                                color: AppColors.error,
                              ),
                            ),
                          ),
                          TextButton(
                            onPressed: _busy ? null : _pay,
                            child: const Text(AppStrings.retryPayment),
                          ),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: AppSpacing.md),
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: FilledButton.icon(
                      style: AppTheme.goldButton(),
                      onPressed: _busy ? null : _pay,
                      icon: _busy
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: AppColors.onSecondaryContainer,
                              ),
                            )
                          : const Icon(Icons.lock, size: 20),
                      label: const Text(AppStrings.payNow),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Center(
                    child: Text(
                      AppStrings.termsNote,
                      textAlign: TextAlign.center,
                      style: AppTypography.bodyMd.copyWith(
                        color: AppColors.onSurfaceVariant,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

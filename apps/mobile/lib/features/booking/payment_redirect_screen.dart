import 'package:flutter/material.dart';
import 'package:mobile/controllers/run_guarded.dart';
import 'package:mobile/services/app_strings.dart';
import 'package:mobile/theme/app_colors.dart';
import 'package:mobile/theme/app_theme.dart';
import 'package:mobile/theme/app_typography.dart';
import 'package:url_launcher/url_launcher.dart';

class PaymentRedirectScreen extends StatefulWidget {
  const PaymentRedirectScreen({
    super.key,
    required this.bookingId,
    required this.fetchCheckoutUrl,
  });

  final int bookingId;
  final Future<String> Function(int bookingId) fetchCheckoutUrl;

  @override
  State<PaymentRedirectScreen> createState() => _PaymentRedirectScreenState();
}

class _PaymentRedirectScreenState extends State<PaymentRedirectScreen> {
  bool _busy = false;
  int _selectedMethod = 0;

  Future<void> _start() async {
    if (_busy) return;
    setState(() => _busy = true);
    await runGuarded(
      () async {
        final url = await widget.fetchCheckoutUrl(widget.bookingId);
        final opened = await launchUrl(
          Uri.parse(url),
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
                  const SizedBox(height: AppSpacing.md),
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: FilledButton.icon(
                      style: AppTheme.goldButton(),
                      onPressed: _busy ? null : _start,
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

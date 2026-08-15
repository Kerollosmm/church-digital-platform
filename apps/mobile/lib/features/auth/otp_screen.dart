import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile/core/auth/auth_gateway.dart';
import 'package:mobile/services/app_strings.dart';
import 'package:mobile/theme/app_colors.dart';
import 'package:mobile/theme/app_theme.dart';
import 'package:mobile/theme/app_typography.dart';

class OtpScreen extends StatefulWidget {
  const OtpScreen({
    super.key,
    required this.phone,
    required this.gateway,
    required this.onVerified,
  });

  final String phone;
  final AuthGateway gateway;
  final VoidCallback onVerified;

  @override
  State<OtpScreen> createState() => _OtpScreenState();
}

class _OtpScreenState extends State<OtpScreen> {
  late final List<TextEditingController> _controllers;
  late final List<FocusNode> _focusNodes;
  bool _verifying = false;

  @override
  void initState() {
    super.initState();
    _controllers = List.generate(6, (_) => TextEditingController());
    _focusNodes = List.generate(6, (_) => FocusNode());
  }

  @override
  void dispose() {
    for (final c in _controllers) {
      c.dispose();
    }
    for (final f in _focusNodes) {
      f.dispose();
    }
    super.dispose();
  }

  Future<void> _verify() async {
    if (_verifying) return;
    final code = _controllers.map((c) => c.text).join();
    if (code.length < 6) return;

    setState(() => _verifying = true);
    try {
      final ok = await widget.gateway.verifyOtp(widget.phone, code);
      if (!mounted) return;
      setState(() => _verifying = false);
      if (ok) {
        widget.onVerified();
      } else {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text(AppStrings.otpInvalid)));
      }
    } catch (_) {
      if (mounted) {
        setState(() => _verifying = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text(AppStrings.otpVerifyFailed)),
        );
      }
    }
  }

  Future<void> _resendOtp() async {
    try {
      await widget.gateway.sendOtp(widget.phone);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text(AppStrings.otpSendFailed)));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: AppColors.primaryContainer,
        body: Stack(
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
            Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(AppSpacing.marginMobile),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 400),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(AppSpacing.lg),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.85),
                          borderRadius: BorderRadius.circular(AppRadius.xl),
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
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Container(
                              width: 64,
                              height: 64,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: AppColors.surfaceContainerHigh,
                                border: Border.all(
                                  color: AppColors.outlineVariant.withValues(
                                    alpha: 0.2,
                                  ),
                                ),
                              ),
                              child: const Icon(
                                Icons.church,
                                size: 40,
                                color: AppColors.primary,
                              ),
                            ),
                            const SizedBox(height: AppSpacing.sm),
                            Text(
                              AppStrings.authTitle,
                              style: AppTypography.headlineLgMobile.copyWith(
                                color: AppColors.primary,
                              ),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 4),
                            Text(
                              AppStrings.authSubtitle,
                              style: AppTypography.bodyMd.copyWith(
                                color: AppColors.onSurfaceVariant,
                              ),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: AppSpacing.md),
                            Text(
                              AppStrings.otpIntro,
                              style: AppTypography.labelMd.copyWith(
                                color: AppColors.onSurfaceVariant,
                              ),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '+20 ${widget.phone}',
                              style: AppTypography.bodyMd.copyWith(
                                color: AppColors.primary,
                                fontWeight: FontWeight.bold,
                              ),
                              textDirection: TextDirection.ltr,
                            ),
                            const SizedBox(height: AppSpacing.xs),
                            GestureDetector(
                              onTap: () => Navigator.maybePop(context),
                              child: Text(
                                AppStrings.changeNumber,
                                style: AppTypography.labelMd.copyWith(
                                  color: AppColors.secondary,
                                ),
                              ),
                            ),
                            const SizedBox(height: AppSpacing.sm),
                            Directionality(
                              textDirection: TextDirection.ltr,
                              child: Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: List.generate(
                                  6,
                                  (i) => Flexible(
                                    child: Container(
                                      constraints: const BoxConstraints(
                                        maxWidth: 48,
                                      ),
                                      height: 56,
                                      child: TextField(
                                        controller: _controllers[i],
                                        focusNode: _focusNodes[i],
                                        maxLength: 1,
                                        textAlign: TextAlign.center,
                                        style: AppTypography.headlineMd
                                            .copyWith(color: AppColors.primary),
                                        keyboardType: TextInputType.number,
                                        inputFormatters: [
                                          FilteringTextInputFormatter
                                              .digitsOnly,
                                        ],
                                        decoration: InputDecoration(
                                          counterText: '',
                                          filled: true,
                                          fillColor:
                                              AppColors.surfaceContainerLow,
                                          contentPadding: EdgeInsets.zero,
                                          border: OutlineInputBorder(
                                            borderRadius: BorderRadius.circular(
                                              AppRadius.sm,
                                            ),
                                            borderSide: const BorderSide(
                                              color: AppColors.outlineVariant,
                                            ),
                                          ),
                                          enabledBorder: OutlineInputBorder(
                                            borderRadius: BorderRadius.circular(
                                              AppRadius.sm,
                                            ),
                                            borderSide: const BorderSide(
                                              color: AppColors.outlineVariant,
                                            ),
                                          ),
                                          focusedBorder: OutlineInputBorder(
                                            borderRadius: BorderRadius.circular(
                                              AppRadius.sm,
                                            ),
                                            borderSide: const BorderSide(
                                              color: AppColors.secondary,
                                              width: 2.0,
                                            ),
                                          ),
                                        ),
                                        onChanged: (val) {
                                          if (val.length == 1) {
                                            if (i < 5) {
                                              FocusScope.of(
                                                context,
                                              ).requestFocus(
                                                _focusNodes[i + 1],
                                              );
                                            } else {
                                              _verify();
                                            }
                                          } else if (val.isEmpty && i > 0) {
                                            FocusScope.of(
                                              context,
                                            ).requestFocus(_focusNodes[i - 1]);
                                          }
                                        },
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: AppSpacing.sm),
                            SizedBox(
                              width: double.infinity,
                              child: FilledButton(
                                style: AppTheme.goldButton(),
                                onPressed: _verifying ? null : _verify,
                                child: const Text(AppStrings.confirmOtp),
                              ),
                            ),
                            const SizedBox(height: AppSpacing.sm),
                            Wrap(
                              alignment: WrapAlignment.center,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              spacing: 4,
                              children: [
                                Text(
                                  AppStrings.resendPrompt,
                                  style: AppTypography.bodyMd.copyWith(
                                    color: AppColors.onSurfaceVariant,
                                  ),
                                ),
                                GestureDetector(
                                  onTap: _resendOtp,
                                  child: Text(
                                    AppStrings.resendOtp,
                                    style: AppTypography.labelMd.copyWith(
                                      color: AppColors.secondary,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: AppSpacing.md),
                      Wrap(
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
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

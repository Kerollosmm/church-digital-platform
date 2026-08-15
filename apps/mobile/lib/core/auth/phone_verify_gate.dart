import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../services/app_strings.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_theme.dart';
import '../../theme/app_typography.dart';
import 'auth_gateway.dart';

enum PhoneVerifyStep { phone, otp }

AuthGateway resolveAuthGateway([AuthGateway? provided]) {
  if (provided != null) return provided;
  try {
    return SupabaseAuthGateway(Supabase.instance.client);
  } catch (_) {
    return UnimplementedAuthGateway();
  }
}

class PhoneVerifyGate extends StatefulWidget {
  const PhoneVerifyGate({
    super.key,
    required this.gateway,
    required this.child,
    this.isLoggedIn,
    this.onVerified,
  });

  final AuthGateway gateway;
  final Widget child;
  final bool Function()? isLoggedIn;
  final VoidCallback? onVerified;

  @override
  State<PhoneVerifyGate> createState() => _PhoneVerifyGateState();

  static bool checkSession([bool Function()? isLoggedIn]) {
    if (isLoggedIn != null) return isLoggedIn();
    try {
      return Supabase.instance.client.auth.currentSession != null;
    } catch (_) {
      return true; // Safe fallback when Supabase isn't initialized in unit tests
    }
  }

  static Future<void> ensureAuth(
    BuildContext context, {
    required AuthGateway gateway,
    required VoidCallback onVerified,
    bool Function()? isLoggedIn,
  }) async {
    if (checkSession(isLoggedIn)) {
      onVerified();
      return;
    }

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
        child: SingleChildScrollView(
          child: Container(
            margin: const EdgeInsets.all(AppSpacing.marginMobile),
            decoration: BoxDecoration(
              color: AppColors.primaryContainer,
              borderRadius: BorderRadius.circular(AppRadius.xl),
            ),
            child: PhoneVerifyForm(
              gateway: gateway,
              onVerified: () {
                Navigator.of(ctx).pop();
                onVerified();
              },
            ),
          ),
        ),
      ),
    );
  }
}

class _PhoneVerifyGateState extends State<PhoneVerifyGate> {
  @override
  Widget build(BuildContext context) {
    if (PhoneVerifyGate.checkSession(widget.isLoggedIn)) {
      return widget.child;
    }

    return Scaffold(
      backgroundColor: AppColors.primaryContainer,
      body: PhoneVerifyForm(
        gateway: widget.gateway,
        onVerified: () {
          setState(() {});
          widget.onVerified?.call();
        },
      ),
    );
  }
}

class PhoneVerifyForm extends StatefulWidget {
  const PhoneVerifyForm({
    super.key,
    required this.gateway,
    required this.onVerified,
  });

  final AuthGateway gateway;
  final VoidCallback onVerified;

  @override
  State<PhoneVerifyForm> createState() => _PhoneVerifyFormState();
}

class _PhoneVerifyFormState extends State<PhoneVerifyForm> {
  PhoneVerifyStep _step = PhoneVerifyStep.phone;
  final _phoneFormKey = GlobalKey<FormState>();
  final _phoneController = TextEditingController();
  late final List<TextEditingController> _otpControllers;
  late final List<FocusNode> _otpFocusNodes;

  bool _sending = false;
  bool _verifying = false;
  String _phone = '';

  @override
  void initState() {
    super.initState();
    _otpControllers = List.generate(6, (_) => TextEditingController());
    _otpFocusNodes = List.generate(6, (_) => FocusNode());
  }

  @override
  void dispose() {
    _phoneController.dispose();
    for (final c in _otpControllers) {
      c.dispose();
    }
    for (final f in _otpFocusNodes) {
      f.dispose();
    }
    super.dispose();
  }

  Future<void> _submitPhone() async {
    if (!(_phoneFormKey.currentState?.validate() ?? false)) return;
    final phone = _phoneController.text.trim();
    setState(() => _sending = true);
    try {
      await widget.gateway.sendOtp(phone);
      if (!mounted) return;
      setState(() {
        _sending = false;
        _phone = phone;
        _step = PhoneVerifyStep.otp;
      });
    } catch (_) {
      if (mounted) {
        setState(() => _sending = false);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text(AppStrings.otpSendFailed)));
      }
    }
  }

  Future<void> _submitOtp() async {
    if (_verifying) return;
    final code = _otpControllers.map((c) => c.text).join();
    if (code.length < 6) return;

    _verifying = true;
    if (mounted) setState(() {});
    try {
      final ok = await widget.gateway.verifyOtp(_phone, code);
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
      await widget.gateway.sendOtp(_phone);
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
      child: Stack(
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
                      child: _step == PhoneVerifyStep.phone
                          ? _buildPhoneStep()
                          : _buildOtpStep(),
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
    );
  }

  Widget _buildHeader() {
    return Column(
      children: [
        Container(
          width: 64,
          height: 64,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: AppColors.surfaceContainerHigh,
            border: Border.all(
              color: AppColors.outlineVariant.withValues(alpha: 0.2),
            ),
          ),
          child: const Icon(Icons.church, size: 40, color: AppColors.primary),
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
      ],
    );
  }

  Widget _buildPhoneStep() {
    return Form(
      key: _phoneFormKey,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          _buildHeader(),
          Align(
            alignment: Alignment.centerRight,
            child: Text(
              AppStrings.phoneLabel,
              style: AppTypography.labelMd.copyWith(color: AppColors.onSurface),
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                height: 48,
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
                decoration: const BoxDecoration(
                  color: AppColors.surfaceContainerLow,
                  borderRadius: BorderRadius.only(
                    topRight: Radius.circular(AppRadius.sm),
                    bottomRight: Radius.circular(AppRadius.sm),
                  ),
                  border: Border(
                    top: BorderSide(color: AppColors.outlineVariant),
                    right: BorderSide(color: AppColors.outlineVariant),
                    bottom: BorderSide(color: AppColors.outlineVariant),
                    left: BorderSide(color: AppColors.outlineVariant),
                  ),
                ),
                alignment: Alignment.center,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  textDirection: TextDirection.ltr,
                  children: [
                    Text(
                      'EG',
                      style: AppTypography.labelMd.copyWith(
                        color: AppColors.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      '+20',
                      style: AppTypography.labelMd.copyWith(
                        color: AppColors.onSurface,
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: TextFormField(
                  controller: _phoneController,
                  keyboardType: TextInputType.phone,
                  textDirection: TextDirection.ltr,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: InputDecoration(
                    hintText: AppStrings.phoneHint,
                    hintStyle: AppTypography.bodyMd.copyWith(
                      color: AppColors.outline,
                    ),
                    filled: true,
                    fillColor: AppColors.surfaceContainerLow,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.sm,
                      vertical: 12,
                    ),
                    border: const OutlineInputBorder(
                      borderRadius: BorderRadius.only(
                        topLeft: Radius.circular(AppRadius.sm),
                        bottomLeft: Radius.circular(AppRadius.sm),
                      ),
                      borderSide: BorderSide(color: AppColors.outlineVariant),
                    ),
                    enabledBorder: const OutlineInputBorder(
                      borderRadius: BorderRadius.only(
                        topLeft: Radius.circular(AppRadius.sm),
                        bottomLeft: Radius.circular(AppRadius.sm),
                      ),
                      borderSide: BorderSide(color: AppColors.outlineVariant),
                    ),
                    focusedBorder: const OutlineInputBorder(
                      borderRadius: BorderRadius.only(
                        topLeft: Radius.circular(AppRadius.sm),
                        bottomLeft: Radius.circular(AppRadius.sm),
                      ),
                      borderSide: BorderSide(
                        color: AppColors.secondary,
                        width: 2.0,
                      ),
                    ),
                  ),
                  validator: (v) {
                    final cleaned = (v ?? '').trim();
                    return cleaned.length < 10 ? AppStrings.invalidPhone : null;
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              style: AppTheme.navyButton(),
              onPressed: _sending ? null : _submitPhone,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text(AppStrings.sendOtpCta),
                  const SizedBox(width: AppSpacing.xs),
                  const Icon(Icons.send, size: 18),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOtpStep() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        _buildHeader(),
        Text(
          AppStrings.otpIntro,
          style: AppTypography.labelMd.copyWith(
            color: AppColors.onSurfaceVariant,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 4),
        Text(
          '+20 $_phone',
          style: AppTypography.bodyMd.copyWith(
            color: AppColors.primary,
            fontWeight: FontWeight.bold,
          ),
          textDirection: TextDirection.ltr,
        ),
        const SizedBox(height: AppSpacing.xs),
        GestureDetector(
          onTap: () => setState(() => _step = PhoneVerifyStep.phone),
          child: Text(
            AppStrings.changeNumber,
            style: AppTypography.labelMd.copyWith(color: AppColors.secondary),
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        Directionality(
          textDirection: TextDirection.ltr,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: List.generate(
              6,
              (i) => Flexible(
                child: Container(
                  constraints: const BoxConstraints(maxWidth: 48),
                  height: 56,
                  child: TextField(
                    controller: _otpControllers[i],
                    focusNode: _otpFocusNodes[i],
                    maxLength: 1,
                    textAlign: TextAlign.center,
                    style: AppTypography.headlineMd.copyWith(
                      color: AppColors.primary,
                    ),
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    decoration: InputDecoration(
                      counterText: '',
                      filled: true,
                      fillColor: AppColors.surfaceContainerLow,
                      contentPadding: EdgeInsets.zero,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(AppRadius.sm),
                        borderSide: const BorderSide(
                          color: AppColors.outlineVariant,
                        ),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(AppRadius.sm),
                        borderSide: const BorderSide(
                          color: AppColors.outlineVariant,
                        ),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(AppRadius.sm),
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
                          ).requestFocus(_otpFocusNodes[i + 1]);
                        } else {
                          _submitOtp();
                        }
                      } else if (val.isEmpty && i > 0) {
                        FocusScope.of(
                          context,
                        ).requestFocus(_otpFocusNodes[i - 1]);
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
            onPressed: _verifying ? null : _submitOtp,
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
    );
  }
}

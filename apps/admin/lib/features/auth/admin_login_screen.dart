import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:admin/core/auth/admin_auth_provider.dart';

class AdminLoginScreen extends ConsumerStatefulWidget {
  const AdminLoginScreen({super.key});

  @override
  ConsumerState<AdminLoginScreen> createState() => _AdminLoginScreenState();
}

class _AdminLoginScreenState extends ConsumerState<AdminLoginScreen> {
  final _phoneController = TextEditingController();
  final _otpController = TextEditingController();
  final _pinController = TextEditingController();
  final _confirmPinController = TextEditingController();
  bool _otpSent = false;
  String? _localError;

  @override
  void dispose() {
    _phoneController.dispose();
    _otpController.dispose();
    _pinController.dispose();
    _confirmPinController.dispose();
    super.dispose();
  }

  Future<void> _handleSendOtp() async {
    setState(() => _localError = null);
    final phone = _phoneController.text.trim();
    if (phone.isEmpty) return;
    try {
      await ref.read(adminAuthProvider.notifier).sendOtp(phone);
      if (mounted) {
        setState(() {
          _otpSent = true;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _localError = e.toString();
        });
      }
    }
  }

  Future<void> _handleVerifyOtp() async {
    setState(() => _localError = null);
    final phone = _phoneController.text.trim();
    final otp = _otpController.text.trim();
    if (otp.isEmpty) return;
    final success = await ref
        .read(adminAuthProvider.notifier)
        .verifyOtp(phone, otp);
    if (!success && mounted) {
      final authState = ref.read(adminAuthProvider);
      if (authState.errorMessage != null) {
        setState(() {
          _localError = authState.errorMessage;
        });
      }
    }
  }

  Future<void> _handleVerifyPin() async {
    setState(() => _localError = null);
    final pin = _pinController.text.trim();
    if (pin.length < 4 || pin.length > 6 || int.tryParse(pin) == null) {
      setState(() {
        _localError = 'رمز PIN يجب أن يكون من 4 إلى 6 أرقام';
      });
      return;
    }
    final success = await ref.read(adminAuthProvider.notifier).verifyPin(pin);
    if (!success && mounted) {
      final authState = ref.read(adminAuthProvider);
      setState(() {
        _localError = authState.errorMessage ?? 'رمز PIN غير صحيح';
      });
    }
  }

  Future<void> _handleSetPin() async {
    setState(() => _localError = null);
    final pin = _pinController.text.trim();
    final confirmPin = _confirmPinController.text.trim();
    if (pin.length < 4 || pin.length > 6 || int.tryParse(pin) == null) {
      setState(() {
        _localError = 'رمز PIN يجب أن يكون من 4 إلى 6 أرقام';
      });
      return;
    }
    if (pin != confirmPin) {
      setState(() {
        _localError = 'رمز PIN والتأكيد غير متطابقين';
      });
      return;
    }
    final success = await ref.read(adminAuthProvider.notifier).setPin(pin);
    if (!success && mounted) {
      final authState = ref.read(adminAuthProvider);
      setState(() {
        _localError = authState.errorMessage ?? 'فشل إعداد رمز PIN';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(adminAuthProvider);
    final errorMessage = authState.errorMessage ?? _localError;
    final isPinReq = authState.isPinRequired;
    final isPinSetupReq = authState.isPinSetupRequired;

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('تسجيل دخول المشرفين'),
        ),
        body: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24.0),
            child: Card(
              elevation: 4,
              child: Padding(
                padding: const EdgeInsets.all(24.0),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'لوحة إشراف الكنيسة',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 24),
                    if (errorMessage != null) ...[
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.red.shade50,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.red.shade300),
                        ),
                        child: Text(
                          errorMessage,
                          style: const TextStyle(
                            color: Colors.red,
                            fontWeight: FontWeight.bold,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                      const SizedBox(height: 16),
                    ],
                    if (isPinReq) ...[
                      const Text(
                        'أدخل رمز PIN',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _pinController,
                        obscureText: true,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'رمز PIN',
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.lock),
                        ),
                      ),
                      const SizedBox(height: 20),
                      ElevatedButton(
                        onPressed: authState.isLoading ? null : _handleVerifyPin,
                        style: ElevatedButton.styleFrom(
                          minimumSize: const Size.fromHeight(48),
                        ),
                        child: authState.isLoading
                            ? const CircularProgressIndicator()
                            : const Text('تأكيد رمز PIN'),
                      ),
                    ] else if (isPinSetupReq) ...[
                      const Text(
                        'إعداد رمز PIN جديد',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _pinController,
                        obscureText: true,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'رمز PIN الجديد',
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.lock_outline),
                        ),
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _confirmPinController,
                        obscureText: true,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'تأكيد رمز PIN',
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.lock_reset),
                        ),
                      ),
                      const SizedBox(height: 20),
                      ElevatedButton(
                        onPressed: authState.isLoading ? null : _handleSetPin,
                        style: ElevatedButton.styleFrom(
                          minimumSize: const Size.fromHeight(48),
                        ),
                        child: authState.isLoading
                            ? const CircularProgressIndicator()
                            : const Text('حفظ رمز PIN والدخول'),
                      ),
                    ] else if (!_otpSent) ...[
                      TextFormField(
                        controller: _phoneController,
                        keyboardType: TextInputType.phone,
                        decoration: const InputDecoration(
                          labelText: 'رقم الهاتف',
                          hintText: '01xxxxxxxxx',
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.phone),
                        ),
                      ),
                      const SizedBox(height: 20),
                      ElevatedButton(
                        onPressed: authState.isLoading ? null : _handleSendOtp,
                        style: ElevatedButton.styleFrom(
                          minimumSize: const Size.fromHeight(48),
                        ),
                        child: authState.isLoading
                            ? const CircularProgressIndicator()
                            : const Text('إرسال الرمز'),
                      ),
                    ] else ...[
                      TextFormField(
                        controller: _otpController,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'رمز التحقق',
                          hintText: '123456',
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.lock_clock),
                        ),
                      ),
                      const SizedBox(height: 20),
                      ElevatedButton(
                        onPressed: authState.isLoading ? null : _handleVerifyOtp,
                        style: ElevatedButton.styleFrom(
                          minimumSize: const Size.fromHeight(48),
                        ),
                        child: authState.isLoading
                            ? const CircularProgressIndicator()
                            : const Text('تأكيد الرمز'),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

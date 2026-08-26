import 'package:admin/core/auth/auth_gateway.dart';
import 'package:flutter/material.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({
    super.key,
    required this.gateway,
    required this.onOtpSent,
  });
  final AuthGateway gateway;
  final void Function(String phone) onOtpSent;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _form = GlobalKey<FormState>();
  final _phone = TextEditingController();
  bool _sending = false;

  Future<void> _submit() async {
    if (!(_form.currentState?.validate() ?? false)) return;
    setState(() => _sending = true);
    try {
      await widget.gateway.sendOtp(_phone.text.trim());
      if (mounted) setState(() => _sending = false);
      widget.onOtpSent(_phone.text.trim());
    } catch (_) {
      if (mounted) {
        setState(() => _sending = false);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('تعذر إرسال الرمز')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        body: Center(
          child: Form(
            key: _form,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'تسجيل الدخول',
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: 280,
                  child: TextFormField(
                    controller: _phone,
                    keyboardType: TextInputType.phone,
                    decoration: const InputDecoration(
                      labelText: 'رقم الهاتف',
                      hintText: '01xxxxxxxxx',
                      border: OutlineInputBorder(),
                    ),
                    validator: (v) => (v == null || v.trim().length < 10)
                        ? 'رقم غير صحيح'
                        : null,
                  ),
                ),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: _sending ? null : _submit,
                  child: const Text('إرسال الرمز'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

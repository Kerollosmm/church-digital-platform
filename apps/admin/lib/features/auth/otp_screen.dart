import 'package:admin/core/auth/auth_gateway.dart';
import 'package:flutter/material.dart';

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
  final _code = TextEditingController();
  bool _verifying = false;

  Future<void> _verify() async {
    setState(() => _verifying = true);
    try {
      final ok = await widget.gateway.verifyOtp(widget.phone, _code.text.trim());
      if (!mounted) return;
      setState(() => _verifying = false);
      if (ok) {
        widget.onVerified();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('الرمز غير صحيح')),
        );
      }
    } catch (_) {
      if (mounted) {
        setState(() => _verifying = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('حدث خطأ أثناء التحقق')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(title: const Text('رمز التحقق')),
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('أدخل الرمز المرسل إلى ${widget.phone}'),
              const SizedBox(height: 16),
              SizedBox(
                width: 200,
                child: TextField(
                  controller: _code,
                  keyboardType: TextInputType.number,
                  maxLength: 6,
                  textAlign: TextAlign.center,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    hintText: '6 أرقام',
                  ),
                ),
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: _verifying ? null : _verify,
                child: const Text('تأكيد'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key, required this.supabase});

  final SupabaseClient supabase;

  @override
  Widget build(BuildContext context) {
    final phone = supabase.auth.currentUser?.phone;
    return Scaffold(
      appBar: AppBar(title: const Text('لوحة الإدارة')),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text('لوحة إدارة الكنيسة', style: TextStyle(fontSize: 20)),
            const SizedBox(height: 8),
            Text(phone == null ? 'غير مسجل' : 'مسجل: $phone'),
          ],
        ),
      ),
    );
  }
}

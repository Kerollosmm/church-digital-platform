import 'package:flutter/material.dart';
import 'package:mobile/screens/dashboard_screen.dart';
import 'package:mobile/services/service_locator.dart';

class TestApp extends StatelessWidget {
  const TestApp({super.key, required this.deps});
  final AppDependencies deps;
  @override
  Widget build(BuildContext context) =>
      MaterialApp(home: DashboardScreen(repository: deps.bookingRepository));
}

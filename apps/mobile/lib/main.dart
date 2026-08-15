import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'app_router.dart';
import 'theme/app_theme.dart';

String get defaultSupabaseUrl {
  if (kIsWeb) return 'http://localhost:54321';
  if (defaultTargetPlatform == TargetPlatform.android)
    return 'http://10.0.2.2:54321';
  return 'http://127.0.0.1:54321';
}

String get resolvedSupabaseUrl {
  const envUrl = String.fromEnvironment('SUPABASE_URL');
  return envUrl.isNotEmpty ? envUrl : defaultSupabaseUrl;
}

const _supabasePublishableKey = String.fromEnvironment('SUPABASE_ANON_KEY');

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (_supabasePublishableKey.isEmpty) {
    throw StateError(
      'Missing SUPABASE_ANON_KEY. Pass via --dart-define=SUPABASE_ANON_KEY=<key>',
    );
  }
  await Supabase.initialize(
    url: resolvedSupabaseUrl,
    publishableKey: _supabasePublishableKey,
  );
  runApp(const ProviderScope(child: ChurchApp()));
}

class ChurchApp extends StatelessWidget {
  const ChurchApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      routerConfig: appRouter,
      title: 'كنيسة',
      locale: const Locale('ar'),
      supportedLocales: const [Locale('ar')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      theme: AppTheme.light(),
    );
  }
}

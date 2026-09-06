import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'app_router.dart';
import 'theme/app_theme.dart';

void validateSupabaseAnonKey(String key) {
  if (key.isEmpty) {
    throw StateError(
      'Missing SUPABASE_ANON_KEY. Pass via --dart-define=SUPABASE_ANON_KEY=<key>',
    );
  }
}

String resolveDefaultSupabaseUrl({
  bool isWeb = kIsWeb,
  TargetPlatform? platform,
}) {
  final targetPlatform = platform ?? defaultTargetPlatform;
  if (isWeb) return 'http://localhost:54321';
  if (targetPlatform == TargetPlatform.android) {
    return 'http://10.0.2.2:54321';
  }
  return 'http://127.0.0.1:54321';
}

String resolveSupabaseUrl({
  String envUrl = const String.fromEnvironment('SUPABASE_URL'),
  bool isRelease = kReleaseMode,
  bool isWeb = kIsWeb,
  TargetPlatform? platform,
}) {
  if (isRelease) {
    if (envUrl.isEmpty) {
      throw StateError(
        'Missing SUPABASE_URL in release mode. Pass via --dart-define=SUPABASE_URL=<url>',
      );
    }
    if (!envUrl.startsWith('https://')) {
      throw StateError(
        'Insecure SUPABASE_URL. Release builds require HTTPS (got: $envUrl)',
      );
    }
    return envUrl;
  }
  return envUrl.isNotEmpty
      ? envUrl
      : resolveDefaultSupabaseUrl(isWeb: isWeb, platform: platform);
}

String get defaultSupabaseUrl => resolveDefaultSupabaseUrl();
String get resolvedSupabaseUrl => resolveSupabaseUrl();

const _supabasePublishableKey = String.fromEnvironment('SUPABASE_ANON_KEY');

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  validateSupabaseAnonKey(_supabasePublishableKey);
  await Supabase.initialize(
    url: resolveSupabaseUrl(),
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

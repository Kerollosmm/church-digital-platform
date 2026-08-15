import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/theme/app_theme.dart';

void main() {
  group('AppTheme unit tests', () {
    test('light theme has correct properties', () {
      final theme = AppTheme.light();
      expect(theme.scaffoldBackgroundColor, const Color(0xFFF7F9FB));
      expect(theme.colorScheme.primary, const Color(0xFF000000));
      expect(theme.colorScheme.secondary, const Color(0xFF904D00));
      expect(theme.textTheme.bodyMedium?.fontFamily, 'Cairo');
      expect(
        theme.filledButtonTheme.style?.minimumSize?.resolve(<WidgetState>{}),
        const Size(64, 48),
      );
    });
  });

  group('AppTheme widget tests', () {
    testWidgets('provides theme values through BuildContext', (tester) async {
      Color? actualScaffoldBg;
      String? actualFontFamily;

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: Builder(
            builder: (context) {
              actualScaffoldBg = Theme.of(context).scaffoldBackgroundColor;
              actualFontFamily = Theme.of(
                context,
              ).textTheme.headlineMedium?.fontFamily;
              return const SizedBox.shrink();
            },
          ),
        ),
      );

      expect(actualScaffoldBg, const Color(0xFFF7F9FB));
      expect(actualFontFamily, 'Cairo');
    });
  });
}

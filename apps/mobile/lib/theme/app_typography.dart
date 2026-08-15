import 'package:flutter/material.dart';

abstract final class AppTypography {
  static const String fontFamily = 'Cairo';

  static const TextStyle displayLg = TextStyle(
    fontFamily: fontFamily,
    fontSize: 48.0,
    fontWeight: FontWeight.w700,
    height: 1.25,
    letterSpacing: -0.02,
  );

  static const TextStyle headlineLg = TextStyle(
    fontFamily: fontFamily,
    fontSize: 32.0,
    fontWeight: FontWeight.w700,
    height: 1.25,
  );

  static const TextStyle headlineLgMobile = TextStyle(
    fontFamily: fontFamily,
    fontSize: 28.0,
    fontWeight: FontWeight.w700,
    height: 1.29,
  );

  static const TextStyle headlineMd = TextStyle(
    fontFamily: fontFamily,
    fontSize: 24.0,
    fontWeight: FontWeight.w600,
    height: 1.33,
  );

  static const TextStyle bodyLg = TextStyle(
    fontFamily: fontFamily,
    fontSize: 18.0,
    fontWeight: FontWeight.w400,
    height: 1.56,
  );

  static const TextStyle bodyMd = TextStyle(
    fontFamily: fontFamily,
    fontSize: 16.0,
    fontWeight: FontWeight.w400,
    height: 1.5,
  );

  static const TextStyle labelMd = TextStyle(
    fontFamily: fontFamily,
    fontSize: 14.0,
    fontWeight: FontWeight.w600,
    height: 1.43,
    letterSpacing: 0.01,
  );

  static TextTheme textTheme() {
    return const TextTheme(
      displayLarge: displayLg,
      headlineLarge: headlineLg,
      headlineMedium: headlineMd,
      bodyLarge: bodyLg,
      bodyMedium: bodyMd,
      labelLarge: labelMd,
      labelMedium: labelMd,
      labelSmall: labelMd,
    );
  }
}

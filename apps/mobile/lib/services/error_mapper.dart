import 'dart:async';
import 'dart:io';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'app_strings.dart';

enum AppErrorKind {
  network,
  auth,
  forbidden,
  notFound,
  conflict,
  server,
  validation,
  unknown,
}

class SupabaseApiException implements Exception {
  const SupabaseApiException({
    required this.kind,
    this.code,
    this.message = '',
    required this.userMessage,
    this.originalError,
  });

  final AppErrorKind kind;
  final String? code;
  final String message;
  final String userMessage;
  final Object? originalError;

  @override
  String toString() => 'SupabaseApiException($kind, $code, $message)';
}

SupabaseApiException mapSupabaseError(Object error, {required String context}) {
  if (error is PostgrestException) {
    final message = error.message.toUpperCase();
    if (error.code == 'PGRST204' || error.code == 'PGRST116') {
      return SupabaseApiException(
        kind: AppErrorKind.notFound,
        code: error.code,
        message: error.message,
        userMessage: AppStrings.notFoundError,
        originalError: error,
      );
    }
    if (error.code == 'PGRST202') {
      return SupabaseApiException(
        kind: AppErrorKind.server,
        code: error.code,
        message: error.message,
        userMessage: AppStrings.serverError,
        originalError: error,
      );
    }
    if (error.code == '42501' || message.contains('FORBIDDEN')) {
      return SupabaseApiException(
        kind: AppErrorKind.forbidden,
        code: error.code,
        message: error.message,
        userMessage: AppStrings.forbiddenError,
        originalError: error,
      );
    }
    if (error.code == '28000' || message.contains('AUTH_REQUIRED')) {
      return SupabaseApiException(
        kind: AppErrorKind.auth,
        code: error.code,
        message: error.message,
        userMessage: AppStrings.authExpired,
        originalError: error,
      );
    }
    if (message.contains('BOOKING_NOT_FOUND') ||
        message.contains('PAYMENT_NOT_FOUND') ||
        message.contains('USER_NOT_FOUND') ||
        message.contains('VIDEO_NOT_FOUND')) {
      return SupabaseApiException(
        kind: AppErrorKind.notFound,
        code: error.code,
        message: error.message,
        userMessage: AppStrings.notFoundError,
        originalError: error,
      );
    }
    if (message.contains('SLOT_') ||
        message.contains('ALREADY_') ||
        message.contains('TOO_MANY_')) {
      return SupabaseApiException(
        kind: AppErrorKind.conflict,
        code: error.code,
        message: error.message,
        userMessage: AppStrings.conflictError,
        originalError: error,
      );
    }
    return SupabaseApiException(
      kind: AppErrorKind.server,
      code: error.code,
      message: error.message,
      userMessage: AppStrings.serverError,
      originalError: error,
    );
  }

  if (error is AuthException) {
    final m = error.message.toLowerCase();
    if (m.contains('invalid') ||
        m.contains('credential') ||
        m.contains('wrong')) {
      return SupabaseApiException(
        kind: AppErrorKind.auth,
        message: error.message,
        userMessage: AppStrings.authInvalid,
        originalError: error,
      );
    }
    return SupabaseApiException(
      kind: AppErrorKind.auth,
      message: error.message,
      userMessage: AppStrings.authExpired,
      originalError: error,
    );
  }

  if (error is SocketException || error is TimeoutException) {
    return SupabaseApiException(
      kind: AppErrorKind.network,
      message: error.toString(),
      userMessage: AppStrings.networkError,
      originalError: error,
    );
  }

  return SupabaseApiException(
    kind: AppErrorKind.unknown,
    message: error.toString(),
    userMessage: AppStrings.unknownError,
    originalError: error,
  );
}

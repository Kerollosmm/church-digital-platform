import 'dart:async';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:mobile/services/error_mapper.dart';

void main() {
  test('maps PostgrestException PGRST202 to server', () {
    final e = PostgrestException(
      message: 'rpc function book_slot not found',
      code: 'PGRST202',
    );
    final m = mapSupabaseError(e, context: 'book_slot');
    expect(m, isA<SupabaseApiException>());
    expect(m.kind, AppErrorKind.server);
    expect(m.code, 'PGRST202');
    expect(m.userMessage, contains('غير متاح'));
  });

  test('maps SLOT_FULL SQLSTATE P0001 to conflict', () {
    final e = PostgrestException(message: 'SLOT_FULL', code: 'P0001');
    final m = mapSupabaseError(e, context: 'book_slot');
    expect(m.kind, AppErrorKind.conflict);
    expect(m.userMessage, contains('ممتلئ'));
  });

  test('maps FORBIDDEN to forbidden', () {
    final e = PostgrestException(message: 'FORBIDDEN', code: '42501');
    final m = mapSupabaseError(e, context: 'book_slot');
    expect(m.kind, AppErrorKind.forbidden);
    expect(m.userMessage, contains('لا تملك صلاحية'));
  });

  test('maps PGRST204 to notFound', () {
    final e = PostgrestException(
      message: 'JSON object requested, multiple (or no) rows returned',
      code: 'PGRST204',
    );
    final m = mapSupabaseError(e, context: 'fetchMyBookings');
    expect(m.kind, AppErrorKind.notFound);
  });

  test('maps AuthException invalid login to auth', () {
    final e = AuthException('Invalid login credentials');
    final m = mapSupabaseError(e, context: 'login');
    expect(m.kind, AppErrorKind.auth);
    expect(m.userMessage, contains('بيانات الدخول غير صحيحة'));
  });

  test('maps SocketException offline to network', () {
    final e = SocketException('connection refused');
    final m = mapSupabaseError(e, context: 'fetchAvailableSlots');
    expect(m.kind, AppErrorKind.network);
    expect(m.userMessage, contains('تعذّر الاتصال بالإنترنت'));
  });

  test('maps TimeoutException to network', () {
    final m = mapSupabaseError(
      TimeoutException('took too long'),
      context: 'rpc',
    );
    expect(m.kind, AppErrorKind.network);
  });

  test('maps FormatException to unknown', () {
    final m = mapSupabaseError(FormatException('bad json'), context: 'parse');
    expect(m.kind, AppErrorKind.unknown);
    expect(m.userMessage, contains('حدث خطأ غير متوقع'));
  });
}

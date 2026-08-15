import '../services/error_mapper.dart';

Future<void> runGuarded(
  Future<void> Function() body, {
  required void Function(String message) onError,
}) async {
  try {
    await body();
  } catch (e) {
    onError(mapSupabaseError(e, context: 'runGuarded').userMessage);
  }
}

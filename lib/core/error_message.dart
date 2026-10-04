import 'package:dio/dio.dart';

/// Pesan error yang ramah untuk ditampilkan di UI.
String errorMessage(Object error, String fallback) {
  if (error is DioException) {
    final m = error.message;
    if (m != null && m.trim().isNotEmpty) return m;
    return fallback;
  }
  final s = error.toString();
  const prefix = 'Exception: ';
  final text = s.startsWith(prefix) ? s.substring(prefix.length) : s;
  return text.trim().isEmpty ? fallback : text;
}

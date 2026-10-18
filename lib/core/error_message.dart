import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';

import 'dio_client.dart';

const String _offlineMessage =
    'Tidak ada koneksi internet. Periksa jaringanmu lalu coba lagi.';
const String _slowMessage = 'Koneksi lambat atau terputus. Coba lagi.';

/// Pesan error yang ramah untuk ditampilkan di UI.
///
/// Tidak pernah menampilkan detail teknis (host / URL / nama library). Error
/// jaringan dipetakan ke pesan sederhana; error lain memakai [fallback].
String errorMessage(Object error, String fallback) {
  if (error is DioException) {
    // Pesan buatan sendiri (mis. base URL belum tersedia) sudah ramah.
    if (error.message == DynamicBaseUrlInterceptor.unavailableMessage) {
      return DynamicBaseUrlInterceptor.unavailableMessage;
    }
    switch (error.type) {
      case DioExceptionType.connectionError:
        return _offlineMessage;
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
        return _slowMessage;
      case DioExceptionType.badResponse:
        final code = error.response?.statusCode;
        return code == null
            ? fallback
            : 'Server sedang bermasalah (kode $code). Coba lagi nanti.';
      default:
        break;
    }
    if (error.error is SocketException) return _offlineMessage;
    if (error.error is TimeoutException) return _slowMessage;
    return fallback;
  }

  if (error is SocketException) return _offlineMessage;
  if (error is TimeoutException) return _slowMessage;

  final s = error.toString();
  const prefix = 'Exception: ';
  final text = (s.startsWith(prefix) ? s.substring(prefix.length) : s).trim();
  if (text.isEmpty) return fallback;

  // Jangan bocorkan detail teknis (host lookup, URL, dsb).
  final lower = text.toLowerCase();
  if (lower.contains('host lookup') ||
      lower.contains('socketexception') ||
      lower.contains('clientexception') ||
      lower.contains('http://') ||
      lower.contains('https://')) {
    return lower.contains('host lookup') || lower.contains('socket')
        ? _offlineMessage
        : fallback;
  }
  return text;
}

import 'remote_config_manager.dart';

/// Port dari Constants.kt
class Constants {
  Constants._();

  /// Base URL API dari Firebase Remote Config (`api_base_url`), tanpa fallback
  /// hardcode. String kosong = belum tersedia (lihat [RemoteConfigManager]).
  static String get baseUrl => RemoteConfigManager.baseUrl ?? '';
  static const String referer = 'https://animeinweb.com/';
  static const String userAgent =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36';
}

/// Port dari buildFullUrl()/getImageUrl()/getThumbnailUrl()/getFullImageUrl()
/// di Models.kt. Path kosong -> "", http(s) dipakai apa adanya,
/// selain itu baseUrl (tanpa "/" akhir) + path (diawali "/").
String buildFullUrl(String? path) {
  if (path == null || path.trim().isEmpty) return '';
  if (path.startsWith('http://') || path.startsWith('https://')) return path;
  final raw = Constants.baseUrl;
  if (raw.isEmpty) return '';
  final base = raw.endsWith('/') ? raw.substring(0, raw.length - 1) : raw;
  final clean = path.startsWith('/') ? path : '/$path';
  return base + clean;
}

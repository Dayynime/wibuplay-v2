/// Port dari Constants.kt
class Constants {
  Constants._();

  static const String baseUrl = 'https://xyz-api.animein.net/';
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
  final base = Constants.baseUrl.endsWith('/')
      ? Constants.baseUrl.substring(0, Constants.baseUrl.length - 1)
      : Constants.baseUrl;
  final clean = path.startsWith('/') ? path : '/$path';
  return base + clean;
}

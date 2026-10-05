import 'dart:async';

import 'package:dio/dio.dart';

/// Info release terbaru dari GitHub.
class UpdateInfo {
  const UpdateInfo({
    required this.tagName,
    required this.downloadUrl,
    required this.releaseBody,
  });

  final String tagName;

  /// Link APK (aset .apk pertama di release). Kosong = release tanpa APK.
  final String downloadUrl;
  final String releaseBody;

  /// Versi tanpa prefix "v".
  String get version => tagName.replaceFirst(RegExp(r'^[vV]'), '');
}

/// Cek update LANGSUNG ke GitHub Releases API (bukan Remote Config), jadi
/// tidak kena cache/throttle. Port GithubUpdateChecker.kt.
///
/// Cara pakai: publish GitHub Release dengan tag versi (mis. `v1.0.1`) dan
/// attach file .apk. Workflow `release.yml` sudah melakukan ini otomatis.
///
/// Repo bisa diganti lewat `--dart-define=UPDATE_REPO=owner/nama-repo`.
class GithubUpdateChecker {
  GithubUpdateChecker._();

  /// GANTI kalau repo rilis Wibuplay berbeda. Repo salah / belum ada release
  /// = dianggap "tidak ada update" (app tidak pernah terkunci karena ini).
  static const String repo =
      String.fromEnvironment('UPDATE_REPO', defaultValue: 'RMBLOGG/wibuplay-v2');

  static const Duration _timeout = Duration(seconds: 6);

  static Future<UpdateInfo?> _fetchLatest() async {
    try {
      final dio = Dio(BaseOptions(
        connectTimeout: _timeout,
        receiveTimeout: _timeout,
        headers: const {'Accept': 'application/vnd.github+json'},
        validateStatus: (s) => s != null && s < 500,
      ));
      final res = await dio.get<dynamic>(
        'https://api.github.com/repos/$repo/releases/latest',
      );
      if (res.statusCode != 200 || res.data is! Map) return null; // 404 = belum ada release
      final json = Map<String, dynamic>.from(res.data as Map);
      final tag = (json['tag_name'] as String?)?.trim() ?? '';
      if (tag.isEmpty) return null;

      // Aset .apk pertama (release.yml juga meng-upload file .sha256).
      var url = '';
      final assets = json['assets'];
      if (assets is List) {
        for (final a in assets) {
          if (a is Map) {
            final name = (a['name'] as String? ?? '').toLowerCase();
            final link = a['browser_download_url'] as String? ?? '';
            if (name.endsWith('.apk') && link.isNotEmpty) {
              url = link;
              break;
            }
          }
        }
      }
      return UpdateInfo(
        tagName: tag,
        downloadUrl: url,
        releaseBody: (json['body'] as String?) ?? '',
      );
    } catch (_) {
      return null;
    }
  }

  /// Bandingkan dua versi segmen demi segmen (mis. "1.2.10" vs "1.3").
  static bool isNewer(String latest, String current) {
    List<int> parse(String v) => v
        .replaceFirst(RegExp(r'^[vV]'), '')
        .split('-')
        .first
        .split('+')
        .first
        .split('.')
        .map((e) => int.tryParse(e) ?? 0)
        .toList();

    final l = parse(latest);
    final c = parse(current);
    final n = l.length > c.length ? l.length : c.length;
    for (var i = 0; i < n; i++) {
      final a = i < l.length ? l[i] : 0;
      final b = i < c.length ? c[i] : 0;
      if (a > b) return true;
      if (a < b) return false;
    }
    return false;
  }

  /// null = tidak ada update, atau fetch gagal (offline dll). Di kedua kasus
  /// app HARUS lanjut jalan normal, bukan dianggap wajib update.
  static Future<UpdateInfo?> checkForUpdate(String currentVersionName) async {
    final latest = await _fetchLatest();
    if (latest == null) return null;
    return isNewer(latest.tagName, currentVersionName) ? latest : null;
  }
}

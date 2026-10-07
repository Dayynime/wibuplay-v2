import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Port IntegrityGuard.kt (Zenime). Deteksi native lewat channel
/// `wibuplay/security` (MainActivity.kt):
///  1. APK ditandatangani sertifikat beda dari yang resmi (APK mod re-sign).
///  2. App proxy/MITM (Reqable, HTTP Toolkit, dll).
///  3. Auto clicker (kata kunci nama app + Accessibility Service gesture).
///
/// SHA-256 sertifikat resmi dikirim saat build lewat
/// `--dart-define=APK_SIG_SHA256=...` (diisi otomatis di release.yml dari
/// keystore). Kosong (build debug/profile) = cek tanda tangan dilewati.
class IntegrityGuard {
  IntegrityGuard._();

  static const MethodChannel _ch = MethodChannel('wibuplay/security');

  static const String _expectedSig =
      String.fromEnvironment('APK_SIG_SHA256', defaultValue: '');

  /// Nama app/alasan yang terdeteksi, atau null kalau aman.
  /// Gagal baca (channel tidak ada, error) dianggap aman supaya tidak salah blok.
  static Future<String?> detectedTool() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return null;
    if (await _isSignatureTampered()) return 'APK tidak resmi (tanda tangan beda)';
    try {
      final r = await _ch.invokeMethod<String>('detectedTool', {'extra': <String>[]});
      return (r == null || r.isEmpty) ? null : r;
    } catch (_) {
      return null;
    }
  }

  static Future<bool> _isSignatureTampered() async {
    final expected = _expectedSig.replaceAll(':', '').trim().toLowerCase();
    if (expected.isEmpty) return false;
    try {
      final hashes = await _ch.invokeListMethod<String>('signatureHashes');
      if (hashes == null || hashes.isEmpty) return false;
      return !hashes.contains(expected);
    } catch (_) {
      return false;
    }
  }

  /// HMAC-SHA256 (hex) pakai key AndroidKeyStore. String kosong = gagal.
  static Future<String> hmacSign(String data) async {
    try {
      return await _ch.invokeMethod<String>('hmacSign', {'data': data}) ?? '';
    } catch (_) {
      return '';
    }
  }
}

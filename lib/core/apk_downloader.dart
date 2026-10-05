import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';

/// State progres download APK update. Port DownloadState di ApkDownloader.kt.
sealed class DownloadState {
  const DownloadState();
}

class DownloadIdle extends DownloadState {
  const DownloadIdle();
}

class Downloading extends DownloadState {
  const Downloading(this.progress, this.received, this.total);

  /// 0..100 (0 kalau ukuran total belum diketahui).
  final int progress;
  final int received;
  final int total;
}

class Downloaded extends DownloadState {
  const Downloaded(this.path, {this.note});

  final String path;

  /// Petunjuk setelah percobaan install (mis. izin "install dari sumber ini").
  final String? note;
}

class DownloadFailed extends DownloadState {
  const DownloadFailed(this.message);

  final String message;
}

/// Download APK update di dalam app (Dio, dengan progres), lalu buka
/// installer sistem lewat open_filex (FileProvider-nya sudah disiapkan plugin).
///
/// Disimpan di folder app-specific, tidak butuh izin storage. File ditulis ke
/// `.part` dulu dan baru di-rename kalau lengkap, jadi APK setengah jadi
/// tidak pernah diberikan ke installer.
class ApkDownloader extends ValueNotifier<DownloadState> {
  ApkDownloader() : super(const DownloadIdle());

  CancelToken? _cancel;
  bool _disposed = false;

  void _set(DownloadState s) {
    if (!_disposed) value = s;
  }

  Future<File> _target() async {
    Directory? dir;
    try {
      dir = await getExternalStorageDirectory();
    } catch (_) {}
    dir ??= await getTemporaryDirectory();
    await dir.create(recursive: true);
    return File('${dir.path}/wibuplay-update.apk');
  }

  Future<void> start(String url) async {
    if (value is Downloading) return;
    final uri = Uri.tryParse(url);
    if (url.isEmpty || uri == null || !uri.hasScheme) {
      _set(const DownloadFailed('Link download APK belum ada di release GitHub ini.'));
      return;
    }

    _set(const Downloading(0, 0, 0));
    final cancel = _cancel = CancelToken();
    File? part;
    try {
      final file = await _target();
      part = File('${file.path}.part');
      if (await file.exists()) await file.delete();
      if (await part.exists()) await part.delete();

      var lastPct = -1;
      await Dio(BaseOptions(
        connectTimeout: const Duration(seconds: 20),
        receiveTimeout: const Duration(minutes: 5),
      )).download(
        url,
        part.path,
        cancelToken: cancel,
        deleteOnError: true,
        onReceiveProgress: (received, total) {
          final pct = total > 0 ? (received * 100 ~/ total) : 0;
          // Hindari rebuild berlebihan: hanya kalau persen berubah.
          if (pct != lastPct || total <= 0) {
            lastPct = pct;
            _set(Downloading(pct, received, total));
          }
        },
      );

      final size = await part.length();
      if (size < 1024 * 100) {
        throw const FormatException('berkas terlalu kecil');
      }
      await part.rename(file.path);
      _set(Downloaded(file.path));
    } on DioException catch (e) {
      if (CancelToken.isCancel(e)) return;
      _set(const DownloadFailed('Unduhan gagal. Cek koneksi internet lalu coba lagi.'));
    } catch (_) {
      _set(const DownloadFailed('Unduhan gagal, coba lagi.'));
      try {
        if (part != null && await part.exists()) await part.delete();
      } catch (_) {}
    }
  }

  /// Buka installer sistem. Kalau app belum diizinkan "Install dari sumber
  /// ini", Android menampilkan layar izin sendiri; setelah mengizinkan,
  /// user tinggal menekan Install lagi.
  Future<void> install() async {
    final s = value;
    if (s is! Downloaded) return;
    try {
      final r = await OpenFilex.open(
        s.path,
        type: 'application/vnd.android.package-archive',
      );
      if (r.type != ResultType.done) {
        _set(Downloaded(
          s.path,
          note: 'Izinkan "Install dari sumber ini" untuk Wibuplay di pengaturan, '
              'lalu tekan Install lagi.',
        ));
      }
    } catch (_) {
      _set(Downloaded(s.path, note: 'Gagal membuka installer, coba tekan Install lagi.'));
    }
  }

  void reset() => _set(const DownloadIdle());

  @override
  void dispose() {
    _disposed = true;
    _cancel?.cancel();
    super.dispose();
  }
}

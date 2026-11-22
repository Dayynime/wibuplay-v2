import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:in_app_update/in_app_update.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../../core/apk_downloader.dart';
import '../../../core/build_flags.dart';
import '../../../core/update_checker.dart';
import '../splash/zenime_splash.dart';
import 'force_update_screen.dart';

enum _Phase { checking, blocked, ok }

/// Gerbang update wajib. Dipasang PALING LUAR (di atas AuthGate): tiap app
/// dibuka, cek release terbaru di GitHub. Kalau lebih baru dari versi yang
/// berjalan, hanya [ForceUpdateScreen] yang tampil dan [child] tidak pernah
/// dibangun, jadi tidak ada cara "skip" ke app.
///
/// Gagal cek (offline, repo belum ada release, timeout) = lanjut normal.
/// Hanya jalan di Android (APK).
class UpdateGate extends StatefulWidget {
  const UpdateGate({
    super.key,
    required this.child,
    this.minSplash = Duration.zero,
  });

  final Widget child;

  /// Lama minimal splash tampil (dihitung dari awal cek update). Dipakai saat
  /// pertama kali buka app supaya splash terlihat dulu sebelum intro; untuk
  /// buka-buka berikutnya biarkan [Duration.zero] biar app tidak tertahan.
  final Duration minSplash;

  @override
  State<UpdateGate> createState() => _UpdateGateState();
}

class _UpdateGateState extends State<UpdateGate> {
  static const Duration _maxWait = Duration(seconds: 7);

  final ApkDownloader _dl = ApkDownloader();
  _Phase _phase = _Phase.checking;

  /// Animasi splash harus selesai dulu sebelum pindah ke app/update.
  bool _splashDone = false;
  UpdateInfo? _info;
  String _current = '';

  @override
  void initState() {
    super.initState();
    _check();
  }

  @override
  void dispose() {
    _dl.dispose();
    super.dispose();
  }

  Future<void> _check() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      if (mounted) setState(() => _phase = _Phase.ok);
      return;
    }
    // Build Google Play: update ditangani Play Store. Aplikasi dari Play
    // dilarang mengunduh/memasang APK sendiri, jadi cek GitHub dilewati.
    // Sebagai gantinya pakai Play In-App Updates: kalau ada versi baru di
    // Play (termasuk track pengujian), tampil layar update resmi dari Play.
    if (BuildFlags.isPlay) {
      final started = DateTime.now();
      try {
        final info = await InAppUpdate.checkForUpdate().timeout(_maxWait);
        if (info.updateAvailability == UpdateAvailability.updateAvailable &&
            info.immediateUpdateAllowed) {
          await InAppUpdate.performImmediateUpdate();
        }
      } catch (_) {
        // Bukan diinstall dari Play, offline, atau timeout -> lanjut normal.
      }
      final remaining = widget.minSplash - DateTime.now().difference(started);
      if (remaining > Duration.zero) await Future<void>.delayed(remaining);
      if (mounted) setState(() => _phase = _Phase.ok);
      return;
    }
    final started = DateTime.now();
    UpdateInfo? update;
    var current = '';
    try {
      final pkg = await PackageInfo.fromPlatform();
      current = pkg.version;
      update = await GithubUpdateChecker.checkForUpdate(current).timeout(_maxWait);
    } catch (_) {
      update = null; // gagal cek -> jangan blokir user
    }
    final remaining = widget.minSplash - DateTime.now().difference(started);
    if (remaining > Duration.zero) await Future<void>.delayed(remaining);
    if (!mounted) return;
    setState(() {
      _info = update;
      _current = current;
      _phase = update != null ? _Phase.blocked : _Phase.ok;
    });
  }

  void _startDownload() => _dl.start(_info?.downloadUrl ?? '');

  @override
  Widget build(BuildContext context) {
    final Widget body;
    switch (_splashDone ? _phase : _Phase.checking) {
      case _Phase.checking:
        body = ZenimeSplash(
          key: const ValueKey('splash'),
          onFinished: () {
            if (mounted) setState(() => _splashDone = true);
          },
        );
      case _Phase.blocked:
        body = ValueListenableBuilder<DownloadState>(
          key: const ValueKey('update'),
          valueListenable: _dl,
          builder: (context, state, _) => ForceUpdateScreen(
            currentVersion: _current,
            latestVersion: _info?.version ?? '',
            releaseNotes: _info?.releaseBody ?? '',
            downloadState: state,
            onDownload: _startDownload,
            onInstall: _dl.install,
            onRetry: _startDownload,
          ),
        );
      case _Phase.ok:
        body = KeyedSubtree(key: const ValueKey('app'), child: widget.child);
    }

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 450),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeIn,
      child: body,
    );
  }
}

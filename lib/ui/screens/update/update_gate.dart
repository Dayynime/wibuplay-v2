import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../../core/apk_downloader.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/update_checker.dart';
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
  const UpdateGate({super.key, required this.child});

  final Widget child;

  @override
  State<UpdateGate> createState() => _UpdateGateState();
}

class _UpdateGateState extends State<UpdateGate> {
  static const Duration _maxWait = Duration(seconds: 7);

  final ApkDownloader _dl = ApkDownloader();
  _Phase _phase = _Phase.checking;
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
    UpdateInfo? update;
    var current = '';
    try {
      final pkg = await PackageInfo.fromPlatform();
      current = pkg.version;
      update = await GithubUpdateChecker.checkForUpdate(current).timeout(_maxWait);
    } catch (_) {
      update = null; // gagal cek -> jangan blokir user
    }
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
    switch (_phase) {
      case _Phase.checking:
        body = const _Splash(key: ValueKey('splash'));
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

/// Layar singkat selama cek update: sama dengan splash bawaan (latar gelap +
/// logo) supaya perpindahan dari splash sistem terasa menyambung.
class _Splash extends StatefulWidget {
  const _Splash({super.key});

  @override
  State<_Splash> createState() => _SplashState();
}

class _SplashState extends State<_Splash> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1300))
        ..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.backgroundDark,
      body: Center(
        child: AnimatedBuilder(
          animation: _c,
          builder: (context, child) {
            final v = Curves.easeInOut.transform(_c.value);
            return Transform.scale(scale: 1 + 0.06 * v, child: child);
          },
          child: ClipRRect(
            borderRadius: BorderRadius.circular(24),
            child: Image.asset('assets/images/logo.jpg', width: 84, height: 84),
          ),
        ),
      ),
    );
  }
}

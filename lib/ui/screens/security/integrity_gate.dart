import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/integrity_guard.dart';
import '../../../core/theme/app_colors.dart';

/// Gerbang keamanan paling luar (port blockedTool di MainActivity.kt Zenime).
///
/// Dicek SEBELUM [onClear] (init Firebase / Remote Config) dan sebelum [child]
/// dibangun, jadi kalau kedeteksi tidak ada request API sama sekali. Dicek
/// lagi tiap app balik ke foreground: app terlarang baru dipasang = langsung
/// diblokir; sudah di-uninstall = app lanjut normal tanpa force-close.
class IntegrityGate extends StatefulWidget {
  const IntegrityGate({super.key, required this.onClear, required this.child});

  /// Dipanggil sekali, setelah lolos cek pertama (init backend).
  final Future<void> Function() onClear;
  final Widget child;

  @override
  State<IntegrityGate> createState() => _IntegrityGateState();
}

class _IntegrityGateState extends State<IntegrityGate> with WidgetsBindingObserver {
  String? _blocked;
  bool _ready = false;
  bool _initStarted = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _check();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _check();
  }

  Future<void> _check() async {
    final tool = await IntegrityGuard.detectedTool();
    if (!mounted) return;
    setState(() => _blocked = tool);
    if (tool == null && !_initStarted) {
      _initStarted = true;
      await widget.onClear();
      if (mounted) setState(() => _ready = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tool = _blocked;
    if (tool != null) {
      return BlockedToolScreen(
        toolName: tool,
        onExit: () => SystemNavigator.pop(),
      );
    }
    if (!_ready) {
      return const Scaffold(backgroundColor: AppColors.backgroundDark);
    }
    return widget.child;
  }
}

/// Port BlockedToolScreen. Tombol back juga cuma keluar.
class BlockedToolScreen extends StatelessWidget {
  const BlockedToolScreen({super.key, required this.toolName, required this.onExit});

  final String toolName;
  final VoidCallback onExit;

  @override
  Widget build(BuildContext context) {
    const accent = AppColors.accentViolet;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) onExit();
      },
      child: Scaffold(
        backgroundColor: AppColors.backgroundDark,
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 28),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 112,
                  height: 112,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: accent.withValues(alpha: 0.12),
                    border: Border.all(color: accent.withValues(alpha: 0.35)),
                  ),
                  child: const Text('\u{1F5FF}', style: TextStyle(fontSize: 52)),
                ),
                const SizedBox(height: 28),
                const Text(
                  'Woy, ngapain itu?',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFFF5F5F7),
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  'Mau ngapain sih kocak pakai apk "$toolName"? '
                  'Nonton tinggal nonton aja... hapus atau matiin dulu tuh apk-nya.',
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 16, color: Color(0xFF9AA0AC)),
                ),
                const SizedBox(height: 20),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(50),
                    color: const Color(0xFF1C222E).withValues(alpha: 0.4),
                    border: Border.all(color: const Color(0xFF9AA0AC).withValues(alpha: 0.25)),
                  ),
                  child: Text(
                    'Terdeteksi: $toolName',
                    style: const TextStyle(fontSize: 14, color: Color(0xFF9AA0AC)),
                  ),
                ),
                const SizedBox(height: 36),
                SizedBox(
                  width: double.infinity,
                  height: 54,
                  child: FilledButton(
                    onPressed: onExit,
                    style: FilledButton.styleFrom(
                      backgroundColor: accent,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    ),
                    child: const Text(
                      'Oke, gue keluar dulu',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  'Udah dihapus atau dimatiin? Buka Zenime lagi, langsung jalan.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 12,
                    color: const Color(0xFF9AA0AC).withValues(alpha: 0.7),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

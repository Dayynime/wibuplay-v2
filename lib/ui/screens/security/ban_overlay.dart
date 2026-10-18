import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/models/chat_models.dart';
import '../../../providers.dart';
import '../../app_routes.dart';
import '../../components/mini_player.dart';

/// Status ban real-time. Diisi [BanWatcher] begitu server bilang user diban,
/// dibaca [BanOverlay] (pola sama dengan RemoteConfigManager.maintenance).
class BanState {
  BanState._();

  static final ValueNotifier<BanStatus?> notifier = ValueNotifier<BanStatus?>(null);
}

/// Dipasang di dalam AuthGate (hanya hidup saat user login). Ngecek ban ke
/// server tiap [interval] selama app di foreground + langsung saat app dibuka
/// lagi dari background. Begitu admin klik ban, user yang lagi buka app
/// otomatis ditendang tanpa relog.
///
/// Gagal cek (jaringan/server) dianggap tidak diban, jadi tidak ada ban palsu.
class BanWatcher extends ConsumerStatefulWidget {
  const BanWatcher({super.key, required this.child, this.interval = const Duration(seconds: 15)});

  final Widget child;
  final Duration interval;

  @override
  ConsumerState<BanWatcher> createState() => _BanWatcherState();
}

class _BanWatcherState extends ConsumerState<BanWatcher> with WidgetsBindingObserver {
  Timer? _timer;
  bool _checking = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Tunda cek pertama: kalau user baru login & ternyata diban, alur login
    // sudah menanganinya sendiri (signOut + pesan error di layar login).
    _timer = Timer(const Duration(seconds: 5), _startLoop);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    super.dispose();
  }

  void _startLoop() {
    _timer?.cancel();
    if (!mounted) return;
    _check();
    _timer = Timer.periodic(widget.interval, (_) => _check());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _startLoop();
    } else if (state == AppLifecycleState.paused) {
      _timer?.cancel();
    }
  }

  Future<void> _check() async {
    if (_checking || !mounted) return;
    _checking = true;
    final repo = ref.read(authRepositoryProvider);
    try {
      final ban = await repo.checkCurrentSessionBan();
      if (!ban.banned) return;
      _timer?.cancel();
      BanState.notifier.value = ban;
      // Tutup semua halaman + hentikan video/audio, lalu logout.
      appNavigatorKey.currentState?.popUntil((r) => r.isFirst);
      MiniPlayerManager.instance.close();
      Future<void>.delayed(const Duration(milliseconds: 450), MiniPlayerManager.instance.close);
      await repo.signOut();
    } catch (_) {
      // Abaikan: dicoba lagi di siklus berikutnya.
    } finally {
      _checking = false;
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// Dipasang di MaterialApp.builder (di ATAS Navigator) biar menutup semua
/// halaman, sama seperti MaintenanceOverlay.
class BanOverlay extends StatelessWidget {
  const BanOverlay({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<BanStatus?>(
      valueListenable: BanState.notifier,
      builder: (context, ban, _) {
        if (ban == null) return const SizedBox.shrink();
        final device = (ban.scope ?? '').toLowerCase().contains('device');
        final reason = (ban.reason ?? '').trim();
        return Positioned.fill(
          child: Material(
            color: const Color(0xFF0B0B10),
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.gpp_bad_rounded, size: 84, color: Colors.redAccent),
                    const SizedBox(height: 24),
                    Text(
                      device ? 'Perangkat Diblokir' : 'Akun Diblokir',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      reason.isEmpty
                          ? (device
                              ? 'Perangkat ini diblokir oleh admin.'
                              : 'Akun kamu diblokir oleh admin.')
                          : reason,
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.white70, fontSize: 15, height: 1.4),
                    ),
                    const SizedBox(height: 32),
                    FilledButton(
                      onPressed: () => BanState.notifier.value = null,
                      style: FilledButton.styleFrom(backgroundColor: Colors.redAccent),
                      child: const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 24, vertical: 4),
                        child: Text('Mengerti'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

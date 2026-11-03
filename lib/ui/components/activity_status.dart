import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_colors.dart';
import '../../data/realtime/online_presence.dart';
import '../../providers.dart';

const Color _kOnline = Color(0xFF22C55E);

/// "Aktif 7 menit lalu" dari waktu [t].
String formatLastSeen(DateTime t) {
  final d = DateTime.now().difference(t.toLocal());
  if (d.inMinutes < 2) return 'Aktif baru saja';
  if (d.inMinutes < 60) return 'Aktif ${d.inMinutes} menit lalu';
  if (d.inHours < 24) return 'Aktif ${d.inHours} jam lalu';
  if (d.inDays < 7) return 'Aktif ${d.inDays} hari lalu';
  if (d.inDays < 30) return 'Aktif ${d.inDays ~/ 7} minggu lalu';
  return 'Lama tidak aktif';
}

/// Status aktif user di profil: "● Sedang aktif" (real-time lewat Presence)
/// atau "Aktif X menit lalu" (dari user_last_seen). Tidak ada data = kosong.
class ActivityStatus extends ConsumerStatefulWidget {
  const ActivityStatus({super.key, required this.uid, this.center = true});

  final String uid;
  final bool center;

  @override
  ConsumerState<ActivityStatus> createState() => _ActivityStatusState();
}

class _ActivityStatusState extends ConsumerState<ActivityStatus> {
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    // Teks "X menit lalu" ikut berjalan tanpa request baru.
    _tick = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final presence = OnlinePresence.instance;
    return ValueListenableBuilder<Map<String, int>>(
      valueListenable: presence.online,
      builder: (context, online, _) {
        final isOnline = (online[widget.uid] ?? 0) > 0;
        // Baru saja offline -> ambil ulang last_seen supaya tidak "lama".
        final last = ref.watch(lastSeenProvider(widget.uid)).valueOrNull;
        if (isOnline) return _row(true, 'Sedang aktif');
        if (last == null) return const SizedBox.shrink();
        return _row(false, formatLastSeen(last));
      },
    );
  }

  Widget _row(bool on, String text) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: widget.center ? MainAxisAlignment.center : MainAxisAlignment.start,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: on ? _kOnline : AppColors.textMuted,
            boxShadow: on ? [BoxShadow(color: _kOnline.withValues(alpha: 0.6), blurRadius: 6)] : null,
          ),
        ),
        const SizedBox(width: 6),
        Text(
          text,
          style: TextStyle(
            color: on ? _kOnline : AppColors.textMuted,
            fontSize: 12,
            fontWeight: on ? FontWeight.w700 : FontWeight.w500,
          ),
        ),
      ],
    );
  }
}

/// "● 128 online di Zenime" untuk header Chat Global (real-time).
class OnlineCountLabel extends StatelessWidget {
  const OnlineCountLabel({super.key});

  @override
  Widget build(BuildContext context) {
    final presence = OnlinePresence.instance;
    return ValueListenableBuilder<bool>(
      valueListenable: presence.ready,
      builder: (context, ready, _) {
        if (!ready) return const SizedBox.shrink();
        return ValueListenableBuilder<Map<String, int>>(
          valueListenable: presence.online,
          builder: (context, online, _) => Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 7,
                height: 7,
                decoration: const BoxDecoration(shape: BoxShape.circle, color: _kOnline),
              ),
              const SizedBox(width: 5),
              Text(
                '${online.length} online di Zenime',
                style: const TextStyle(color: _kOnline, fontSize: 11.5, fontWeight: FontWeight.w600),
              ),
            ],
          ),
        );
      },
    );
  }
}

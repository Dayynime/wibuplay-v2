import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_colors.dart';
import '../../providers.dart';

/// Lama bergabung dalam bulan kalender penuh (14 Agu -> 16 Okt = 2).
int monthsSince(DateTime join, [DateTime? now]) {
  final n = now ?? DateTime.now();
  var m = (n.year - join.year) * 12 + (n.month - join.month);
  if (n.day < join.day) m--;
  return m < 0 ? 0 : m;
}

/// Angka + satuan buat stat profil: < 1 bulan pakai "hari",
/// < 12 bulan pakai "bulan", selebihnya "tahun".
(int, String) joinDuration(DateTime join, [DateTime? now]) {
  final n = now ?? DateTime.now();
  final months = monthsSince(join, n);
  if (months < 1) {
    final days = n.difference(join).inDays;
    return (days < 0 ? 0 : days, 'hari');
  }
  if (months < 12) return (months, 'bulan');
  return (months ~/ 12, 'tahun');
}

/// Kolom stat lama bergabung di baris stat Profil (pengganti stat Favorit),
/// gaya referensi: angka besar + satuan ("2" / "bulan").
/// Dipakai di Profil Saya & Profil Publik.
///
/// [fallback] = tanggal cadangan kalau server belum ada datanya
/// (Profil Saya kirim tanggal pembuatan akun Firebase).
class JoinDateStat extends ConsumerWidget {
  const JoinDateStat({super.key, required this.firebaseUid, this.fallback});

  final String firebaseUid;
  final DateTime? fallback;

  static const _valueStyle = TextStyle(
    color: AppColors.textWhite,
    fontSize: 19,
    fontWeight: FontWeight.w700,
  );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(joinDateProvider(firebaseUid));
    final date = async.valueOrNull ?? (async.isLoading ? null : fallback);

    final Widget value;
    final String label;
    if (date == null) {
      value = Text(async.isLoading ? '...' : '-', style: _valueStyle);
      label = 'bulan';
    } else {
      final (count, unit) = joinDuration(date);
      label = unit;
      value = TweenAnimationBuilder<int>(
        tween: IntTween(begin: 0, end: count),
        duration: const Duration(milliseconds: 1200),
        builder: (context, v, _) => Text('$v', style: _valueStyle),
      );
    }

    return Expanded(
      child: Column(
        children: [
          value,
          const SizedBox(height: 2),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Color(0xB3FFFFFF), fontSize: 11),
          ),
        ],
      ),
    );
  }
}

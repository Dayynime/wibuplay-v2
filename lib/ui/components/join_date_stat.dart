import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_colors.dart';
import '../../providers.dart';

const List<String> _bulan = [
  'Jan', 'Feb', 'Mar', 'Apr', 'Mei', 'Jun',
  'Jul', 'Agu', 'Sep', 'Okt', 'Nov', 'Des',
];

/// "Okt 2025". Sengaja tanpa package intl.
String formatJoinDate(DateTime d) => '${_bulan[d.month - 1]} ${d.year}';

/// Kolom stat "Join Zenime" di baris stat Profil (pengganti stat Favorit).
/// Dipakai di Profil Saya & Profil Publik, gaya sama dengan `_stat` di sana.
///
/// [fallback] = tanggal cadangan kalau server belum ada datanya
/// (Profil Saya kirim tanggal pembuatan akun Firebase).
class JoinDateStat extends ConsumerWidget {
  const JoinDateStat({super.key, required this.firebaseUid, this.fallback});

  final String firebaseUid;
  final DateTime? fallback;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(joinDateProvider(firebaseUid));
    final date = async.valueOrNull ?? (async.isLoading ? null : fallback);
    final text = date != null ? formatJoinDate(date) : (async.isLoading ? '...' : '-');

    return Expanded(
      child: Column(
        children: [
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 400),
            child: FittedBox(
              key: ValueKey(text),
              fit: BoxFit.scaleDown,
              child: Text(
                text,
                maxLines: 1,
                style: const TextStyle(
                  color: AppColors.textWhite,
                  fontSize: 19,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
          const SizedBox(height: 2),
          const Text(
            'Join Zenime',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: TextStyle(color: Color(0xB3FFFFFF), fontSize: 11),
          ),
        ],
      ),
    );
  }
}

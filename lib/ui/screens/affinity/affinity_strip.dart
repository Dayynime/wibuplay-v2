import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../data/models/affinity_models.dart';
import '../../../providers.dart';
import '../../redesign/z_kit.dart';
import '../profile/profile_screen.dart' show ProfileAvatar;
import 'affinity_fx.dart';
import 'affinity_providers.dart';
import 'affinity_screen.dart';

/// Baris "Afinitas" di header profil: cap 絆, jumlah ikatan, avatar bertumpuk.
/// Ketuk = buka halaman Afinitas. Gagal memuat / belum login = disembunyikan.
class AffinityStrip extends ConsumerWidget {
  const AffinityStrip({super.key, required this.uid, this.name, this.canInvite = false});

  final String uid;
  final String? name;
  final bool canInvite;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (uid.isEmpty) return const SizedBox.shrink();
    final list = ref.watch(affinityListSafeProvider(uid)).valueOrNull;
    if (list == null) return const SizedBox.shrink();
    final me = ref.watch(authUserProvider).valueOrNull?.uid ?? '';
    final own = me == uid;
    final items = [...list.items]..sort((a, b) => b.points.compareTo(a.points));
    final shown = items.take(4).toList();
    final soul = list.ofType(AffinityType.soulmate).firstOrNull;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: ZPress(
        onTap: () async {
          await openAffinityScreen(context, uid, name: name, canInvite: canInvite);
          ref.invalidate(affinityListSafeProvider(uid));
        },
        child: Container(
          height: 54,
          padding: const EdgeInsets.fromLTRB(12, 0, 8, 0),
          decoration: BoxDecoration(
            color: const Color(0x8C0B0E14),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
          ),
          child: Row(
            children: [
              AffinitySeal(
                type: soul?.type ?? AffinityType.nakama,
                size: 30,
                stamp: false,
                beat: soul != null,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Text('Afinitas',
                            style: TextStyle(color: AppColors.textWhite, fontSize: 13.5, fontWeight: FontWeight.w800)),
                        const SizedBox(width: 6),
                        Text('絆', style: ZFont.jp(size: 11, color: AppColors.textSecondary, letterSpacing: 0)),
                        if (own && list.incoming > 0) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                            decoration: BoxDecoration(
                              color: AppColors.accentViolet,
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Text('${list.incoming} baru',
                                style: const TextStyle(color: Colors.white, fontSize: 9.5, fontWeight: FontWeight.w800)),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 1),
                    Text(
                      soul != null
                          ? 'Soulmate: ${soul.displayName} · ${list.items.length} ikatan'
                          : (list.items.isEmpty
                              ? (own ? 'Belum ada ikatan · ajak teman' : 'Belum ada ikatan')
                              : '${list.items.length} ikatan'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: AppColors.textSecondary, fontSize: 11),
                    ),
                  ],
                ),
              ),
              if (shown.isNotEmpty)
                SizedBox(
                  width: 22.0 * (shown.length - 1) + 30,
                  height: 30,
                  child: Stack(
                    children: [
                      for (var k = shown.length - 1; k >= 0; k--)
                        Positioned(
                          left: 22.0 * k,
                          child: Container(
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(color: shown[k].type.color, width: 1.5),
                            ),
                            child: ProfileAvatar(
                              url: shown[k].avatarUrl,
                              seed: shown[k].otherUid,
                              label: shown[k].displayName,
                              size: 27,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              const Icon(Icons.chevron_right_rounded, color: AppColors.textSecondary),
            ],
          ),
        ),
      ),
    );
  }
}

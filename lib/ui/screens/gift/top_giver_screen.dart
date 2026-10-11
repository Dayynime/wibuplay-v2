import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../data/models/support_models.dart';
import '../../../providers.dart';
import '../../components/game_badges.dart';
import '../profile/public_profile_screen.dart' show openPublicProfile;

const Color _teal = Color(0xFF2DD4BF);
const Color _gold = Color(0xFFFFC107);
const Color _silver = Color(0xFFC7CDD8);
const Color _bronze = Color(0xFFCE8946);

Color _rankColor(int r) => switch (r) {
      1 => _gold,
      2 => _silver,
      3 => _bronze,
      _ => _teal,
    };

String _days(int d) {
  final s = d.toString().replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => '.');
  return '$s hari';
}

/// Halaman Top Giver: podium 3 besar + daftar semua pemberi Premium.
class TopGiverScreen extends ConsumerWidget {
  const TopGiverScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(topGiversProvider);
    return Scaffold(
      backgroundColor: AppColors.backgroundDark,
      appBar: AppBar(
        backgroundColor: AppColors.backgroundDark,
        foregroundColor: AppColors.textWhite,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        titleSpacing: 0,
        title: const Text('Top Giver', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 20)),
      ),
      body: RefreshIndicator(
        color: _teal,
        onRefresh: () => ref.refresh(topGiversProvider.future),
        child: async.when(
          loading: () => const Center(child: CircularProgressIndicator(color: _teal)),
          error: (_, __) => ListView(
            children: const [
              SizedBox(height: 120),
              Center(child: Text('Gagal memuat. Tarik untuk coba lagi.', style: TextStyle(color: AppColors.textSecondary))),
            ],
          ),
          data: (data) {
            final g = data.givers;
            if (g.isEmpty) {
              return ListView(
                children: const [
                  SizedBox(height: 120),
                  Center(
                    child: Text(
                      'Belum ada yang memberi Premium.\nJadi yang pertama lewat Giveaway!',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: AppColors.textSecondary, height: 1.4),
                    ),
                  ),
                ],
              );
            }
            return ListView(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 40),
              children: [
                _PodiumCard(data: data),
                const SizedBox(height: 22),
                const Text(
                  'Semua Giver',
                  style: TextStyle(color: AppColors.textWhite, fontSize: 20, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 8),
                for (final x in g.skip(3))
                  _GiverTile(
                    giver: x,
                    clan: data.clanTags[x.firebaseUid],
                    level: data.levels[x.firebaseUid],
                  ),
                if (g.length <= 3)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 20),
                    child: Text(
                      'Peringkat 4 dan seterusnya akan muncul di sini.',
                      style: TextStyle(color: AppColors.textMuted),
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _PodiumCard extends StatelessWidget {
  const _PodiumCard({required this.data});

  final TopGiversData data;

  @override
  Widget build(BuildContext context) {
    final g = data.givers;
    Widget slot(int i, double size) => i < g.length
        ? Expanded(child: _PodiumEntry(giver: g[i], clan: data.clanTags[g[i].firebaseUid], size: size))
        : const Expanded(child: SizedBox());
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF0E4A45), Color(0xFF0B2A2F)],
        ),
        border: Border.all(color: const Color(0x402DD4BF)),
      ),
      child: Column(
        children: [
          const Row(
            children: [
              Icon(Icons.card_giftcard, color: _gold, size: 20),
              SizedBox(width: 8),
              Text('Top 3 Giver', style: TextStyle(color: _gold, fontSize: 18, fontWeight: FontWeight.w800)),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [slot(1, 64), slot(0, 84), slot(2, 64)],
          ),
        ],
      ),
    );
  }
}

class _PodiumEntry extends StatelessWidget {
  const _PodiumEntry({required this.giver, required this.size, this.clan});

  final TopGiver giver;
  final double size;
  final String? clan;

  @override
  Widget build(BuildContext context) {
    final color = _rankColor(giver.rank);
    return GestureDetector(
      onTap: () => openPublicProfile(context, giver.firebaseUid),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if ((clan ?? '').isNotEmpty) ...[
            ClanRainbowBadge(text: clan!, height: 18),
            const SizedBox(height: 4),
          ],
          Stack(
            clipBehavior: Clip.none,
            children: [
              Container(
                padding: const EdgeInsets.all(3),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: color, width: 2.5),
                  boxShadow: giver.rank == 1
                      ? [BoxShadow(color: _gold.withValues(alpha: 0.45), blurRadius: 18)]
                      : null,
                ),
                child: UserAvatar(username: giver.username, url: giver.avatarUrl, size: size),
              ),
              if (giver.rank == 1)
                const Positioned(
                  right: -6,
                  top: -12,
                  child: Icon(Icons.workspace_premium, color: _gold, size: 28),
                ),
              Positioned(
                right: 0,
                bottom: 0,
                child: Container(
                  width: 24,
                  height: 24,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: color,
                    shape: BoxShape.circle,
                    border: Border.all(color: const Color(0xFF0B2A2F), width: 2),
                  ),
                  child: Text(
                    '${giver.rank}',
                    style: const TextStyle(color: Color(0xFF15213B), fontWeight: FontWeight.w900, fontSize: 12),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            giver.username,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: AppColors.textWhite, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 2),
          Text(
            _days(giver.days),
            style: const TextStyle(color: _teal, fontWeight: FontWeight.w800),
          ),
        ],
      ),
    );
  }
}

class _GiverTile extends StatelessWidget {
  const _GiverTile({required this.giver, this.clan, this.level});

  final TopGiver giver;
  final String? clan;
  final int? level;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => openPublicProfile(context, giver.firebaseUid),
      borderRadius: BorderRadius.circular(14),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          children: [
            SizedBox(
              width: 58,
              child: Column(
                children: [
                  UserAvatar(username: giver.username, url: giver.avatarUrl, size: 50),
                  const SizedBox(height: 2),
                  Text(
                    '#${giver.rank}',
                    style: const TextStyle(color: _teal, fontWeight: FontWeight.w800, fontSize: 12),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          giver.username,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: AppColors.textWhite, fontSize: 16, fontWeight: FontWeight.w700),
                        ),
                      ),
                      if (giver.userNumber != null) ...[
                        const SizedBox(width: 6),
                        Text('#${giver.userNumber}',
                            style: const TextStyle(color: AppColors.textMuted, fontSize: 12)),
                      ],
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      if ((clan ?? '').isNotEmpty) ...[
                        ClanRainbowBadge(text: clan!),
                        const SizedBox(width: 6),
                      ],
                      if (level != null) LevelBadge(level: level!),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Text(
              _days(giver.days),
              style: const TextStyle(color: _gold, fontSize: 15, fontWeight: FontWeight.w800),
            ),
          ],
        ),
      ),
    );
  }
}

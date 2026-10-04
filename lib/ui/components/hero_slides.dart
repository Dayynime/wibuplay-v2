import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../data/models/clan_models.dart';
import '../../data/models/support_models.dart';
import '../../data/models/xp_models.dart';
import 'game_badges.dart';

const Color heroGold = Color(0xFFFFC107);
const Color heroPink = Color(0xFFFF5C8A);
const Color _silver = Color(0xFFC7CDD8);
const Color _bronze = Color(0xFFCE8946);
const Color _ink = Color(0xFF15213B);

String _compactCount(int v) {
  if (v >= 1000000) return '${(v / 1000000).toStringAsFixed(1).replaceAll('.0', '')}M';
  if (v >= 1000) return '${(v / 1000).toStringAsFixed(1).replaceAll('.0', '')}K';
  return '$v';
}

String _compactRupiah(int v) {
  if (v >= 1000000) return 'Rp${(v / 1000000).toStringAsFixed(1).replaceAll('.0', '').replaceAll('.', ',')}jt';
  if (v >= 1000) return 'Rp${(v / 1000).round()}rb';
  return 'Rp$v';
}

Color _rankColor(int rank) => switch (rank) {
      1 => heroGold,
      2 => _silver,
      3 => _bronze,
      _ => const Color(0x1FFFFFFF),
    };

/// Slide "TOP LEADERBOARD" di carousel Beranda: dua panel kaca (TOP XP dan
/// TOP CLAN) di atas kartu navy dengan glow lembut. Tiap baris: avatar dengan
/// ring + badge peringkat, nama, lalu nilai di bawah nama. Panel TOP XP bisa
/// di-tap ke leaderboard XP; panel clan belum punya halaman tujuan di
/// Wibuplay, jadi tanpa chevron/tap.
class HeroLeaderboardSlide extends StatelessWidget {
  const HeroLeaderboardSlide({
    super.key,
    required this.entries,
    required this.clans,
    required this.onTap,
  });

  final List<UserXpDisplay> entries;
  final List<ClanSummary> clans;
  final VoidCallback onTap;

  static const Color _xpBlue = Color(0xFF4FC3F7);
  static const Color _clanPurple = Color(0xFFB57BFF);

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF1A2646), Color(0xFF0B1324)],
        ),
        border: Border.all(color: const Color(0x14FFFFFF)),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Stack(
        children: [
          // Glow lembut: emas di kanan atas, ungu di kiri bawah.
          const Positioned(
            right: -50,
            top: -60,
            child: _Glow(color: heroGold, size: 170),
          ),
          const Positioned(
            left: -60,
            bottom: -80,
            child: _Glow(color: _clanPurple, size: 190),
          ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              children: [
                SizedBox(
                  height: 22,
                  child: Row(
                    children: [
                      Container(
                        width: 22,
                        height: 22,
                        decoration: BoxDecoration(
                          color: heroGold.withValues(alpha: 0.16),
                          borderRadius: BorderRadius.circular(7),
                        ),
                        child: const Icon(Icons.emoji_events_rounded, size: 14, color: heroGold),
                      ),
                      const SizedBox(width: 8),
                      const Text(
                        'TOP LEADERBOARD',
                        style: TextStyle(
                          color: heroGold,
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.8,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                Expanded(
                  child: Row(
                    children: [
                      Expanded(
                        child: _Panel(
                          icon: Icons.bolt_rounded,
                          label: 'TOP XP',
                          color: _xpBlue,
                          onTap: onTap,
                          rows: [
                            for (var i = 0; i < entries.length && i < 4; i++)
                              _BoardRow(
                                rank: i + 1,
                                avatar: UserAvatar(
                                  username: entries[i].username,
                                  url: entries[i].avatarUrl,
                                  size: 24,
                                ),
                                title: entries[i].username,
                                value: '${_compactCount(entries[i].xp)} XP',
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _Panel(
                          icon: Icons.shield_rounded,
                          label: 'TOP CLAN',
                          color: _clanPurple,
                          rows: [
                            for (var i = 0; i < clans.length && i < 4; i++)
                              _BoardRow(
                                rank: i + 1,
                                avatar: UserAvatar(
                                  username: clans[i].tag,
                                  url: clans[i].photoUrl,
                                  size: 24,
                                ),
                                title: clans[i].tag,
                                value: 'Lv${clans[i].level}',
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Glow extends StatelessWidget {
  const _Glow({required this.color, required this.size});

  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(
            colors: [color.withValues(alpha: 0.13), color.withValues(alpha: 0)],
          ),
        ),
      ),
    );
  }
}

/// Satu panel kolom: header (ikon + label + chevron kalau bisa di-tap) dan
/// maksimal 4 baris yang disebar rata supaya selalu rapi.
class _Panel extends StatelessWidget {
  const _Panel({
    required this.icon,
    required this.label,
    required this.color,
    required this.rows,
    this.onTap,
  });

  final IconData icon;
  final String label;
  final Color color;
  final List<Widget> rows;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.fromLTRB(10, 8, 8, 8),
        decoration: BoxDecoration(
          color: const Color(0x0DFFFFFF),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0x0FFFFFFF)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              height: 16,
              child: Row(
                children: [
                  Icon(icon, size: 14, color: color),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      label,
                      style: TextStyle(
                        color: color,
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.6,
                      ),
                    ),
                  ),
                  if (onTap != null)
                    Icon(Icons.chevron_right_rounded, size: 16, color: color.withValues(alpha: 0.7)),
                ],
              ),
            ),
            const SizedBox(height: 6),
            Expanded(
              child: rows.isEmpty
                  ? const Center(
                      child: Text(
                        'Belum ada data',
                        style: TextStyle(color: Color(0x66FFFFFF), fontSize: 11),
                      ),
                    )
                  : Column(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: rows,
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Satu baris leaderboard (tinggi tetap 28): avatar ber-ring + badge rank di
/// pojok kiri bawah, nama di atas, nilai emas di bawah nama.
class _BoardRow extends StatelessWidget {
  const _BoardRow({
    required this.rank,
    required this.avatar,
    required this.title,
    required this.value,
  });

  final int rank;
  final Widget avatar;
  final String title;
  final String value;

  @override
  Widget build(BuildContext context) {
    final ring = rank <= 3 ? _rankColor(rank) : const Color(0x26FFFFFF);
    return SizedBox(
      height: 28,
      child: Row(
        children: [
          Stack(
            clipBehavior: Clip.none,
            children: [
              Container(
                width: 28,
                height: 28,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: ring, width: 1.5),
                ),
                child: ClipOval(child: avatar),
              ),
              Positioned(left: -4, bottom: -3, child: _RankBadge(rank: rank)),
            ],
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xEBFFFFFF),
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    height: 1.15,
                  ),
                ),
                Text(
                  value,
                  maxLines: 1,
                  style: const TextStyle(
                    color: heroGold,
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    height: 1.15,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Badge angka rank kecil (14) dengan tepi gelap supaya "terpotong" rapi dari
/// ring avatar.
class _RankBadge extends StatelessWidget {
  const _RankBadge({required this.rank});
  final int rank;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 14,
      height: 14,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: rank <= 3 ? _rankColor(rank) : const Color(0xFF2B3550),
        shape: BoxShape.circle,
        border: Border.all(color: const Color(0xFF111B31), width: 1.5),
      ),
      child: Text(
        '$rank',
        style: TextStyle(
          color: rank <= 3 ? _ink : const Color(0xB3FFFFFF),
          fontSize: 8,
          fontWeight: FontWeight.w800,
          height: 1,
        ),
      ),
    );
  }
}

/// Slide "TOP SUPPORT" (podium 3 donatur SociaBuzz teratas).
class HeroSupportSlide extends StatelessWidget {
  const HeroSupportSlide({super.key, required this.supporters});

  final List<TopSupporter> supporters;

  @override
  Widget build(BuildContext context) {
    final top = supporters.take(3).toList();
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF3A1A2C), Color(0xFF1E1B2E)],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.favorite, size: 18, color: heroPink),
              SizedBox(width: 7),
              Text(
                'TOP SUPPORT',
                style: TextStyle(
                  color: heroPink,
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.6,
                ),
              ),
            ],
          ),
          const SizedBox(height: 2),
          const Text(
            'Donatur SociaBuzz teratas',
            style: TextStyle(color: AppColors.textMuted, fontSize: 11),
          ),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                if (top.length > 1) Expanded(child: _Podium(rank: 2, s: top[1], bar: 34, delayMs: 90)),
                if (top.isNotEmpty) Expanded(child: _Podium(rank: 1, s: top[0], bar: 52, delayMs: 0)),
                if (top.length > 2) Expanded(child: _Podium(rank: 3, s: top[2], bar: 22, delayMs: 180)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Podium extends StatelessWidget {
  const _Podium({required this.rank, required this.s, required this.bar, required this.delayMs});

  final int rank;
  final TopSupporter s;
  final double bar;
  final int delayMs;

  @override
  Widget build(BuildContext context) {
    final color = _rankColor(rank);
    final avatar = rank == 1 ? 40.0 : 32.0;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(2),
            decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: color, width: 2)),
            child: UserAvatar(username: s.name, url: s.avatarUrl, size: avatar),
          ),
          const SizedBox(height: 4),
          Text(
            s.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppColors.textWhite, fontSize: 11, fontWeight: FontWeight.w600),
          ),
          Text(
            _compactRupiah(s.totalAmount),
            style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 4),
          // Balok podium tumbuh dari bawah, juara 1 duluan.
          TweenAnimationBuilder<double>(
            tween: Tween<double>(begin: 0, end: bar),
            duration: Duration(milliseconds: 500 + delayMs),
            curve: Curves.easeOutCubic,
            builder: (context, h, _) => Container(
              width: double.infinity,
              height: h,
              alignment: Alignment.topCenter,
              padding: const EdgeInsets.only(top: 3),
              decoration: BoxDecoration(
                borderRadius: const BorderRadius.vertical(top: Radius.circular(8)),
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [color, color.withValues(alpha: 0.55)],
                ),
              ),
              child: h > 14
                  ? Text('$rank',
                      style: const TextStyle(color: _ink, fontSize: 12, fontWeight: FontWeight.w800))
                  : null,
            ),
          ),
        ],
      ),
    );
  }
}

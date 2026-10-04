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

/// Slide "TOP LEADERBOARD" di carousel Beranda: dua kolom, TOP XP (XP nonton
/// bulan ini) dan TOP CLAN, dipisah garis vertikal. Port HeroLeaderboardSlide
/// di HomeScreen.kt (Zenime). Kolom clan belum punya halaman tujuan di
/// Wibuplay, jadi tidak ada chevron/tap di kolom itu.
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

  static const Color _xpBlue = Color(0xFF30ADE6);
  static const Color _clanPurple = Color(0xFFAF52DE);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF15213B), Color(0xFF0C1526)],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.emoji_events, size: 19, color: heroGold),
              SizedBox(width: 7),
              Text(
                'TOP LEADERBOARD',
                style: TextStyle(
                  color: heroGold,
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.6,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _ColumnHeader(
                        icon: Icons.bolt,
                        label: 'TOP XP',
                        color: _xpBlue,
                        onTap: onTap,
                      ),
                      const SizedBox(height: 10),
                      if (entries.isEmpty)
                        const _EmptyHint()
                      else
                        for (var i = 0; i < entries.length && i < 4; i++) ...[
                          if (i > 0) const SizedBox(height: 9),
                          _xpRow(i + 1, entries[i]),
                        ],
                    ],
                  ),
                ),
                Container(
                  width: 1,
                  margin: const EdgeInsets.symmetric(vertical: 2),
                  color: const Color(0x1AFFFFFF),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const _ColumnHeader(
                        icon: Icons.shield,
                        label: 'TOP CLAN',
                        color: _clanPurple,
                      ),
                      const SizedBox(height: 10),
                      if (clans.isEmpty)
                        const _EmptyHint()
                      else
                        for (var i = 0; i < clans.length && i < 4; i++) ...[
                          if (i > 0) const SizedBox(height: 9),
                          _clanRow(i + 1, clans[i]),
                        ],
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

  Widget _xpRow(int rank, UserXpDisplay e) {
    return Row(
      children: [
        _RankBadge(rank: rank),
        const SizedBox(width: 6),
        UserAvatar(username: e.username, url: e.avatarUrl, size: 22),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            e.username,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: Color(0xEBFFFFFF), fontSize: 11),
          ),
        ),
        const SizedBox(width: 4),
        Text(
          _compactCount(e.xp),
          maxLines: 1,
          style: const TextStyle(color: heroGold, fontSize: 10, fontWeight: FontWeight.w700),
        ),
      ],
    );
  }

  Widget _clanRow(int rank, ClanSummary c) {
    return Row(
      children: [
        _RankBadge(rank: rank),
        const SizedBox(width: 6),
        UserAvatar(username: c.tag, url: c.photoUrl, size: 22),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            c.tag,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: Color(0xEBFFFFFF), fontSize: 11),
          ),
        ),
        const SizedBox(width: 4),
        Text(
          'Lv${c.level}',
          maxLines: 1,
          style: const TextStyle(color: heroGold, fontSize: 10, fontWeight: FontWeight.w700),
        ),
      ],
    );
  }
}

/// Header satu kolom leaderboard: ikon + label, chevron di ujung kanan kalau
/// kolomnya bisa di-tap ([onTap] != null).
class _ColumnHeader extends StatelessWidget {
  const _ColumnHeader({
    required this.icon,
    required this.label,
    required this.color,
    this.onTap,
  });

  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Row(
        children: [
          Icon(icon, size: 13, color: color),
          const SizedBox(width: 4),
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                color: color,
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.3,
              ),
            ),
          ),
          if (onTap != null)
            Icon(Icons.chevron_right, size: 15, color: color.withValues(alpha: 0.65)),
        ],
      ),
    );
  }
}

class _EmptyHint extends StatelessWidget {
  const _EmptyHint();

  @override
  Widget build(BuildContext context) {
    return const Text(
      'Belum ada data',
      style: TextStyle(color: Color(0x66FFFFFF), fontSize: 11),
    );
  }
}

class _RankBadge extends StatelessWidget {
  const _RankBadge({required this.rank});
  final int rank;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 16,
      height: 16,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: _rankColor(rank), shape: BoxShape.circle),
      child: Text(
        '$rank',
        style: TextStyle(
          color: rank <= 3 ? _ink : const Color(0xB3FFFFFF),
          fontSize: 9,
          fontWeight: FontWeight.w800,
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

import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
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

/// Slide "TOP LEADERBOARD" (Top XP bulan ini) di carousel Beranda.
class HeroLeaderboardSlide extends StatelessWidget {
  const HeroLeaderboardSlide({super.key, required this.entries, required this.onTap});

  final List<UserXpDisplay> entries;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF2A2650), Color(0xFF1E1B2E)],
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.emoji_events, size: 19, color: heroGold),
                const SizedBox(width: 7),
                const Text(
                  'TOP LEADERBOARD',
                  style: TextStyle(
                    color: heroGold,
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.6,
                  ),
                ),
                const Spacer(),
                Icon(Icons.chevron_right, size: 18, color: heroGold.withValues(alpha: 0.7)),
              ],
            ),
            const SizedBox(height: 2),
            const Text(
              'XP nonton bulan ini',
              style: TextStyle(color: AppColors.textMuted, fontSize: 11),
            ),
            const SizedBox(height: 10),
            for (var i = 0; i < entries.length && i < 4; i++) ...[
              if (i > 0) const SizedBox(height: 8),
              _row(i + 1, entries[i]),
            ],
          ],
        ),
      ),
    );
  }

  Widget _row(int rank, UserXpDisplay e) {
    return Row(
      children: [
        _RankBadge(rank: rank),
        const SizedBox(width: 8),
        UserAvatar(username: e.username, url: e.avatarUrl, size: 26),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            e.username,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: AppColors.textWhite, fontSize: 13, fontWeight: FontWeight.w600),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          '${_compactCount(e.xp)} XP',
          style: const TextStyle(color: heroGold, fontSize: 12, fontWeight: FontWeight.w700),
        ),
      ],
    );
  }
}

class _RankBadge extends StatelessWidget {
  const _RankBadge({required this.rank});
  final int rank;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 18,
      height: 18,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: _rankColor(rank), shape: BoxShape.circle),
      child: Text(
        '$rank',
        style: TextStyle(
          color: rank <= 3 ? _ink : const Color(0xB3FFFFFF),
          fontSize: 10,
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

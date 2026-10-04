import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';

/// Badge "gamer rank" yang dipakai bersama di Chat Global, profil, dan
/// Leaderboard XP supaya tampilannya konsisten (port GameBadges.kt).

/// Bentuk panah/pita: sisi kiri bertakik, sisi kanan runcing.
class _BadgeArrowClipper extends CustomClipper<Path> {
  const _BadgeArrowClipper();

  @override
  Path getClip(Size size) {
    final tip = size.height * 0.42;
    return Path()
      ..moveTo(size.height * 0.28, 0)
      ..lineTo(size.width - tip, 0)
      ..lineTo(size.width, size.height / 2)
      ..lineTo(size.width - tip, size.height)
      ..lineTo(size.height * 0.28, size.height)
      ..lineTo(0, size.height / 2)
      ..close();
  }

  @override
  bool shouldReclip(covariant CustomClipper<Path> oldClipper) => false;
}

/// Badge level emas bentuk panah ("Lv.N").
class LevelBadge extends StatelessWidget {
  const LevelBadge({super.key, required this.level});

  final int level;

  @override
  Widget build(BuildContext context) {
    return ClipPath(
      clipper: const _BadgeArrowClipper(),
      child: Container(
        padding: const EdgeInsets.fromLTRB(8, 2, 10, 2),
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFFFFDE7A), Color(0xFFE8A317), Color(0xFFB8860B)],
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.bolt, size: 11, color: Colors.white),
            const SizedBox(width: 2),
            Text(
              'Lv.$level',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 9,
                fontWeight: FontWeight.w800,
                height: 1.2,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Centang biru untuk akun Premium.
class PremiumCheckBadge extends StatelessWidget {
  const PremiumCheckBadge({super.key, this.size = 14});

  final double size;

  @override
  Widget build(BuildContext context) {
    return Icon(Icons.verified, size: size, color: const Color(0xFF3897F0));
  }
}

/// Avatar bulat dengan fallback huruf pertama username.
class UserAvatar extends StatelessWidget {
  const UserAvatar({super.key, required this.username, this.url, this.size = 44});

  final String username;
  final String? url;
  final double size;

  @override
  Widget build(BuildContext context) {
    final has = url != null && url!.isNotEmpty;
    return Container(
      width: size,
      height: size,
      clipBehavior: Clip.antiAlias,
      decoration: const BoxDecoration(
        color: AppColors.surfaceVariantDark,
        shape: BoxShape.circle,
      ),
      alignment: Alignment.center,
      child: has
          ? Image.network(
              url!,
              width: size,
              height: size,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => _letter(),
            )
          : _letter(),
    );
  }

  Widget _letter() => Text(
        username.isEmpty ? '?' : username.characters.first.toUpperCase(),
        style: TextStyle(
          color: AppColors.textWhite,
          fontSize: size * 0.4,
          fontWeight: FontWeight.w700,
        ),
      );
}

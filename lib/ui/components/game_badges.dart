import 'dart:ui' as ui;

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
  const LevelBadge({super.key, required this.level, this.height});

  final int level;

  /// Tinggi tetap (mis. 20 di header Profil); null = ikut isi.
  final double? height;

  @override
  Widget build(BuildContext context) {
    return ClipPath(
      clipper: const _BadgeArrowClipper(),
      child: Container(
        height: height,
        padding: EdgeInsets.fromLTRB(8, height == null ? 2 : 0, 10, height == null ? 2 : 0),
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFFFFDE7A), Color(0xFFE8A317), Color(0xFFB8860B)],
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Image.asset('assets/images/ic_zcoin_badge.png', width: 11, height: 11),
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

/// Bentuk heksagon pita runcing di dua sisi (port BadgeHexShape di GameBadges.kt).
Path _clanHexPath(Size size) {
  final tip = size.height * 0.5;
  return Path()
    ..moveTo(tip, 0)
    ..lineTo(size.width - tip, 0)
    ..lineTo(size.width, size.height / 2)
    ..lineTo(size.width - tip, size.height)
    ..lineTo(tip, size.height)
    ..lineTo(0, size.height / 2)
    ..close();
}

class _ClanHexClipper extends CustomClipper<Path> {
  const _ClanHexClipper();

  @override
  Path getClip(Size size) => _clanHexPath(size);

  @override
  bool shouldReclip(covariant CustomClipper<Path> oldClipper) => false;
}

class _ClanHexBorderPainter extends CustomPainter {
  const _ClanHexBorderPainter(this.alpha);

  final double alpha;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawPath(
      _clanHexPath(size),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = Colors.white.withValues(alpha: alpha),
    );
  }

  @override
  bool shouldRepaint(covariant _ClanHexBorderPainter old) => old.alpha != alpha;
}

/// Badge tag clan rainbow animasi (fill geser + kilau + border berdenyut),
/// port ClanRainbowBadge di GameBadges.kt.
class ClanRainbowBadge extends StatefulWidget {
  const ClanRainbowBadge({super.key, required this.text, this.height});

  final String text;

  /// Tinggi tetap (mis. 20 di header Profil); null = ikut isi.
  final double? height;

  @override
  State<ClanRainbowBadge> createState() => _ClanRainbowBadgeState();
}

class _ClanRainbowBadgeState extends State<ClanRainbowBadge>
    with SingleTickerProviderStateMixin {
  // Satu controller buat tiga animasi (pelangi 2600ms, kilau 1800ms, denyut
  // border 900ms). 23400ms = kelipatan persekutuan ketiganya, jadi semua
  // loop mulus tanpa loncat.
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 23400),
  )..repeat();

  static const _rainbow = [
    Color(0xFFFF3B30),
    Color(0xFFFF9500),
    Color(0xFFFFCC00),
    Color(0xFF34C759),
    Color(0xFF00C7BE),
    Color(0xFF30ADE6),
    Color(0xFF5856D6),
    Color(0xFFAF52DE),
    Color(0xFFFF3B30),
  ];

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const star = TextStyle(color: Color(0xD9FFFFFF), fontSize: 7, height: 1.2);
    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: _c,
        builder: (context, child) {
          final v = _c.value;
          final rainbow = (v * 9) % 1.0; // 23400 / 2600
          final shine = (v * 13) % 1.0; // 23400 / 1800
          final pulse = (v * 26) % 1.0; // 23400 / 900
          // Denyut bolak-balik 0.35 <-> 0.95.
          final glow = 0.35 + 0.6 * (pulse < 0.5 ? pulse * 2 : (1 - pulse) * 2);
          return CustomPaint(
            foregroundPainter: _ClanHexBorderPainter(glow),
            child: ClipPath(
              clipper: const _ClanHexClipper(),
              child: CustomPaint(
                painter: _ClanFillPainter(
                  rainbow: rainbow,
                  shine: -0.4 + 1.8 * shine,
                ),
                child: child,
              ),
            ),
          );
        },
        child: Container(
          height: widget.height,
          padding: EdgeInsets.symmetric(
            horizontal: 10,
            vertical: widget.height == null ? 2.5 : 0,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const Text('✦', style: star),
              const SizedBox(width: 3),
              Text(
                widget.text.toUpperCase(),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 9,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.6,
                  height: 1.2,
                ),
              ),
              const SizedBox(width: 3),
              const Text('✦', style: star),
            ],
          ),
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

/// Fill pelangi + kilau badge clan, ukurannya PIXEL TETAP seperti
/// ClanRainbowBadge.kt (gradient 260dp yang geser dari -260 ke +260), bukan
/// relatif ke lebar badge. Jadi di badge sempit cuma sepotong pelangi yang
/// kelihatan tiap saat (warnanya berganti pelan), sama persis dengan Zenime.
class _ClanFillPainter extends CustomPainter {
  const _ClanFillPainter({required this.rainbow, required this.shine});

  /// 0..1, fase geser pelangi.
  final double rainbow;

  /// -0.4..1.4, posisi kilau.
  final double shine;

  static const double _sweep = 260;
  static const _colors = [
    Color(0xFFFF3B30),
    Color(0xFFFF9500),
    Color(0xFFFFCC00),
    Color(0xFF34C759),
    Color(0xFF00C7BE),
    Color(0xFF30ADE6),
    Color(0xFF5856D6),
    Color(0xFFAF52DE),
    Color(0xFFFF3B30),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final startX = -_sweep + rainbow * (_sweep * 2);
    canvas.drawRect(
      rect,
      Paint()
        ..shader = ui.Gradient.linear(
          Offset(startX, 0),
          Offset(startX + _sweep, 30),
          _colors,
        ),
    );
    canvas.drawRect(
      rect,
      Paint()
        ..shader = ui.Gradient.linear(
          Offset(shine * 200 - 60, 0),
          Offset(shine * 200 + 60, 26),
          [
            Colors.white.withValues(alpha: 0),
            Colors.white.withValues(alpha: 0.55),
            Colors.white.withValues(alpha: 0),
          ],
        ),
    );
  }

  @override
  bool shouldRepaint(covariant _ClanFillPainter old) =>
      old.rainbow != rainbow || old.shine != shine;
}

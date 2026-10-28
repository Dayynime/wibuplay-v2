import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/xp_models.dart';
import '../../providers.dart';

/// Komponen badge header Profil gaya "Level di Avatar":
/// - [ProfileXpRing]: cincin progress XP emas di sekeliling avatar + pin "LV N".
/// - [ClanNameTag]: tag clan kecil (border pelangi) yang nempel di depan nama.
/// - [ProfileAchievementBadges]: Top Giver / Top XP sebagai chip netral kecil.
/// Role tetap pakai [RoleBadge] dengan `rounded: true`.

const List<Color> _rainbow = [
  Color(0xFFFF3B30),
  Color(0xFFFF9500),
  Color(0xFFFFCC00),
  Color(0xFF34C759),
  Color(0xFF30ADE6),
  Color(0xFFAF52DE),
  Color(0xFFFF3B30),
];

const Color _gold1 = Color(0xFFFFE08A);
const Color _gold2 = Color(0xFFE8A317);
const Color _goldInk = Color(0xFF1B1305);

// ------------------------------------------------------------------ XP ring

/// Bungkus avatar dengan cincin XP + pin level di bawahnya.
/// [avatarSize] = diameter avatar (tanpa frame). Cincin digambar sedikit di
/// luar avatar; frame avatar (kalau ada) tetap tampil di atas cincin, dan pin
/// level digambar paling atas supaya selalu kebaca.
class ProfileXpRing extends ConsumerWidget {
  const ProfileXpRing({
    super.key,
    required this.uid,
    required this.avatarSize,
    required this.child,
  });

  final String uid;
  final double avatarSize;
  final Widget child;

  /// Jarak avatar ke cincin + tebal cincin (dipakai juga buat padding luar).
  static const double gap = 4;
  static const double stroke = 4;
  static const double pinHeight = 22;

  /// Tambahan ruang di tiap sisi avatar yang dipakai cincin.
  static const double ringExtent = gap + stroke;

  /// Seberapa jauh pin level menjorok ke bawah lingkaran cincin.
  static const double pinOverhang = pinHeight / 2;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final xp = uid.isEmpty ? null : ref.watch(myXpProvider(uid)).valueOrNull;
    final level = xp?.level ?? 1;
    final p = XpLevelFormula.progress(xp?.totalXp ?? 0, level);
    final box = avatarSize + ringExtent * 2;

    return SizedBox(
      width: box,
      height: box,
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.center,
        children: [
          Positioned.fill(
            child: TweenAnimationBuilder<double>(
              tween: Tween<double>(begin: 0, end: p.fraction),
              duration: const Duration(milliseconds: 900),
              curve: Curves.easeOutCubic,
              builder: (context, v, _) => CustomPaint(
                painter: _XpRingPainter(fraction: v, stroke: stroke),
              ),
            ),
          ),
          child,
          if (uid.isNotEmpty)
            Positioned(
              bottom: -pinOverhang,
              child: Tooltip(
                message: 'Level $level · ${p.xpIntoLevel} / ${p.xpNeededForLevel} XP',
                triggerMode: TooltipTriggerMode.tap,
                child: LevelPin(level: level, height: pinHeight),
              ),
            ),
        ],
      ),
    );
  }
}

class _XpRingPainter extends CustomPainter {
  const _XpRingPainter({required this.fraction, required this.stroke});

  final double fraction;
  final double stroke;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromLTWH(
      stroke / 2,
      stroke / 2,
      size.width - stroke,
      size.height - stroke,
    );
    final track = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..color = Colors.white.withValues(alpha: 0.14);
    canvas.drawArc(rect, 0, math.pi * 2, false, track);

    if (fraction <= 0) return;
    final sweep = math.pi * 2 * fraction;
    final arc = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..shader = SweepGradient(
        startAngle: 0,
        endAngle: math.pi * 2,
        colors: const [_gold2, _gold1, _gold2],
        transform: const GradientRotation(-math.pi / 2),
      ).createShader(rect);
    // Mulai dari jam 12, searah jarum jam.
    canvas.drawArc(rect, -math.pi / 2, sweep, false, arc);
  }

  @override
  bool shouldRepaint(_XpRingPainter old) =>
      old.fraction != fraction || old.stroke != stroke;
}

/// Pin kapsul emas "★ LV N" di bawah avatar. Border gelap tipis supaya
/// kelihatan "memotong" cincin.
class LevelPin extends StatelessWidget {
  const LevelPin({super.key, required this.level, this.height = 22});

  final int level;
  final double height;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      padding: const EdgeInsets.symmetric(horizontal: 9),
      decoration: BoxDecoration(
        gradient: const LinearGradient(colors: [_gold1, _gold2]),
        borderRadius: BorderRadius.circular(height / 2),
        border: Border.all(color: const Color(0xFF0B0D14), width: 2.5),
        boxShadow: [
          BoxShadow(
            color: _gold2.withValues(alpha: 0.35),
            blurRadius: 10,
            spreadRadius: -2,
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.star_rounded, size: 12, color: _goldInk),
          const SizedBox(width: 2),
          Text(
            'LV $level',
            maxLines: 1,
            style: const TextStyle(
              color: _goldInk,
              fontSize: 11,
              fontWeight: FontWeight.w900,
              letterSpacing: 0.4,
              height: 1.1,
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------- clan tag

/// Tag clan kecil di depan nama: latar gelap, border pelangi yang mengalir,
/// teks pelangi. Animasi berhenti kalau "reduce motion" aktif.
class ClanNameTag extends StatefulWidget {
  const ClanNameTag({super.key, required this.text, this.height = 20, this.onTap});

  final String text;
  final double height;
  final VoidCallback? onTap;

  @override
  State<ClanNameTag> createState() => _ClanNameTagState();
}

class _ClanNameTagState extends State<ClanNameTag> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 4000),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _c.stop();
    } else if (!_c.isAnimating) {
      _c.repeat();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final h = widget.height;
    final tag = GestureDetector(
      onTap: widget.onTap,
      child: RepaintBoundary(
        child: AnimatedBuilder(
          animation: _c,
          builder: (context, _) {
            final g = LinearGradient(
              colors: _rainbow,
              tileMode: TileMode.repeated,
              transform: _Slide(_c.value),
            );
            return Container(
              height: h,
              padding: const EdgeInsets.all(1),
              decoration: BoxDecoration(
                gradient: g,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: const Color(0xEB0E1018),
                  borderRadius: BorderRadius.circular(5),
                ),
                child: ShaderMask(
                  blendMode: BlendMode.srcIn,
                  shaderCallback: (r) => g.createShader(r),
                  child: Text(
                    widget.text,
                    maxLines: 1,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: h * 0.55,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0.6,
                      height: 1.1,
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
    return Tooltip(message: 'Clan ${widget.text}', child: tag);
  }
}

/// Geser gradien sebesar [t] x lebar (efek mengalir, loop mulus karena repeated).
class _Slide extends GradientTransform {
  const _Slide(this.t);
  final double t;

  @override
  Matrix4? transform(Rect bounds, {TextDirection? textDirection}) =>
      Matrix4.translationValues(-bounds.width * t, 0, 0);
}

// ------------------------------------------------------------- achievements

/// Chip pencapaian netral: ikon + label + "#rank" berwarna.
class ProfileAchievementChip extends StatelessWidget {
  const ProfileAchievementChip({
    super.key,
    required this.icon,
    required this.label,
    required this.rank,
    required this.color,
    this.height = 22,
    this.tooltip,
    this.onTap,
  });

  final IconData icon;
  final String label;
  final int rank;
  final Color color;
  final double height;
  final String? tooltip;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final chip = GestureDetector(
      onTap: onTap,
      child: Container(
        height: height,
        padding: const EdgeInsets.symmetric(horizontal: 9),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 12, color: color),
            const SizedBox(width: 4),
            Text(
              label,
              style: const TextStyle(
                color: Color(0xFFD7DAE5),
                fontSize: 10.5,
                fontWeight: FontWeight.w600,
                height: 1.1,
              ),
            ),
            const SizedBox(width: 4),
            Text(
              '#$rank',
              style: TextStyle(
                color: color,
                fontSize: 10.5,
                fontWeight: FontWeight.w900,
                height: 1.1,
              ),
            ),
          ],
        ),
      ),
    );
    return tooltip == null ? chip : Tooltip(message: tooltip!, child: chip);
  }
}

/// Top Giver & Top XP versi chip netral. Tidak render apa-apa untuk peringkat
/// yang tidak dimiliki user.
class ProfileAchievementBadges extends ConsumerWidget {
  const ProfileAchievementBadges({super.key, required this.firebaseUid});

  final String firebaseUid;

  static const Color giverColor = Color(0xFFFFC54D);
  static const Color xpColor = Color(0xFF7DD3FC);

  /// Dipakai buat menyusun Wrap: list kosong = tidak ada pencapaian.
  static List<Widget> chips(WidgetRef ref, String uid) {
    if (uid.isEmpty) return const [];
    final giver = ref.watch(topGiverRankProvider(uid));
    final xp = ref.watch(topXpRankProvider(uid));
    return [
      if (giver != null)
        ProfileAchievementChip(
          icon: Icons.card_giftcard,
          label: 'Top Giver',
          rank: giver,
          color: giverColor,
          tooltip: 'Peringkat $giver di leaderboard Top Giver',
        ),
      if (xp != null)
        ProfileAchievementChip(
          icon: Icons.bolt_rounded,
          label: 'Top XP',
          rank: xp,
          color: xpColor,
          tooltip: 'Peringkat $xp XP bulan ini',
        ),
    ];
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final list = chips(ref, firebaseUid);
    if (list.isEmpty) return const SizedBox.shrink();
    return Wrap(spacing: 6, runSpacing: 6, children: list);
  }
}

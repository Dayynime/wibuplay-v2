import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_colors.dart';
import '../../data/models/xp_models.dart';
import '../../providers.dart';
import '../redesign/z_kit.dart';

/// Satu tingkat rank. Rank ditentukan otomatis dari level XP.
class RankTier {
  const RankTier(this.name, this.min, this.hi, this.mid, this.dk);

  final String name;

  /// Level minimal untuk rank ini.
  final int min;

  /// Warna terang, utama, gelap.
  final Color hi, mid, dk;
}

const kRankTiers = <RankTier>[
  RankTier('Rookie', 1, Color(0xFFEEF1F6), Color(0xFF9AA3B2), Color(0xFF3C4250)),
  RankTier('Bronze', 50, Color(0xFFFFD9B3), Color(0xFFC8814A), Color(0xFF5A2F12)),
  RankTier('Silver', 100, Color(0xFFFFFFFF), Color(0xFFC3CCDB), Color(0xFF4E5769)),
  RankTier('Sapphire', 500, Color(0xFFD6E6FF), Color(0xFF3F73FF), Color(0xFF0F2370)),
  RankTier('Platinum', 1500, Color(0xFFF4ECFF), Color(0xFFB9A2FF), Color(0xFF4A33A0)),
  RankTier('Diamond', 5000, Color(0xFFF6E3FF), Color(0xFFC06BFF), Color(0xFF4B137F)),
  RankTier('Master', 10000, Color(0xFFDCEFFF), Color(0xFF2F8DFF), Color(0xFF0B347A)),
  RankTier('Grandmaster', 30000, Color(0xFFFFF6CF), Color(0xFFF4B234), Color(0xFF6E4204)),
  RankTier('Champion', 70000, Color(0xFFFFD6C2), Color(0xFFFF3B2F), Color(0xFF5E0A06)),
  RankTier('Celestial', 100000, Color(0xFFFFFDF2), Color(0xFFF7DC8C), Color(0xFF9A7426)),
  RankTier('Mythical', 150000, Color(0xFFF1E4FF), Color(0xFF9B5CFF), Color(0xFF2A0B62)),
  RankTier('Immortal', 250000, Color(0xFFFF7A8A), Color(0xFFC3102B), Color(0xFF14020A)),
  RankTier('Eternal', 500000, Color(0xFFFFFBEA), Color(0xFFFFD45E), Color(0xFF7A5200)),
];

/// Indeks rank untuk [level]. Eternal berlaku untuk 500.000 ke atas.
int rankIndexForLevel(int level) {
  for (var i = kRankTiers.length - 1; i >= 0; i--) {
    if (level >= kRankTiers[i].min) return i;
  }
  return 0;
}

String _fmtNum(int n) {
  final s = n.toString();
  final b = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) b.write('.');
    b.write(s[i]);
  }
  return b.toString();
}

/// Rentang level rank ke-[i], mis. "1.500–4.999" atau "500.000+".
String rankRangeLabel(int i) {
  final t = kRankTiers[i];
  if (i == kRankTiers.length - 1) return '${_fmtNum(t.min)}+';
  return '${_fmtNum(t.min)}–${_fmtNum(kRankTiers[i + 1].min - 1)}';
}

// ---------------------------------------------------------------------------
// Lambang beranimasi
// ---------------------------------------------------------------------------

/// Lambang rank dari aset assets/ranks/rank_<i>.webp, dihidupkan dengan
/// cahaya berdenyut, gerak mengambang, kilau menyapu, dan partikel cahaya
/// (makin tinggi rank, makin ramai). [animate] false = gambar diam.
class RankEmblem extends StatefulWidget {
  const RankEmblem({super.key, required this.tier, this.size = 84, this.animate = true});

  final int tier;
  final double size;
  final bool animate;

  @override
  State<RankEmblem> createState() => _RankEmblemState();
}

class _RankEmblemState extends State<RankEmblem> with SingleTickerProviderStateMixin {
  late final AnimationController _ctl = AnimationController(vsync: this, duration: const Duration(seconds: 4));

  @override
  void initState() {
    super.initState();
    if (widget.animate) _ctl.repeat();
  }

  @override
  void didUpdateWidget(covariant RankEmblem old) {
    super.didUpdateWidget(old);
    if (widget.animate && !_ctl.isAnimating) _ctl.repeat();
    if (!widget.animate && _ctl.isAnimating) _ctl.stop();
  }

  @override
  void dispose() {
    _ctl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final i = math.min(math.max(widget.tier, 0), kRankTiers.length - 1);
    final tier = kRankTiers[i];
    final size = widget.size;
    final image = Image.asset(
      'assets/ranks/rank_$i.webp',
      width: size,
      height: size,
      fit: BoxFit.contain,
      filterQuality: FilterQuality.medium,
      gaplessPlayback: true,
    );
    if (!widget.animate) {
      return SizedBox.square(dimension: size, child: image);
    }
    // Kekuatan efek naik mengikuti rank (0..1).
    final power = i / (kRankTiers.length - 1);
    return RepaintBoundary(
      child: SizedBox.square(
        dimension: size,
        child: AnimatedBuilder(
          animation: _ctl,
          child: image,
          builder: (context, child) {
            final t = _ctl.value;
            final pulse = 0.5 + 0.5 * math.sin(t * _tau * 2);
            final bob = math.sin(t * _tau) * size * 0.025;
            // Kilau lewat sekali per putaran, lalu jeda.
            final sx = -3.0 + 6.0 * t;
            return Stack(
              clipBehavior: Clip.none,
              alignment: Alignment.center,
              children: [
                // Cahaya belakang berdenyut.
                Container(
                  width: size * 0.62,
                  height: size * 0.62,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: tier.mid.withValues(alpha: (0.18 + 0.22 * power) * (0.6 + 0.4 * pulse)),
                        blurRadius: size * (0.28 + 0.12 * pulse),
                        spreadRadius: size * 0.04,
                      ),
                    ],
                  ),
                ),
                // Partikel di belakang lambang.
                CustomPaint(size: Size.square(size), painter: _RankFxPainter(i, t, behind: true)),
                Transform.translate(
                  offset: Offset(0, bob),
                  child: Transform.scale(
                    scale: 1 + 0.02 * pulse,
                    child: ShaderMask(
                      blendMode: BlendMode.srcATop,
                      shaderCallback: (rect) => LinearGradient(
                        begin: Alignment(sx - 0.5, -1),
                        end: Alignment(sx + 0.5, 1),
                        colors: [
                          Colors.white.withValues(alpha: 0),
                          Colors.white.withValues(alpha: 0.45),
                          Colors.white.withValues(alpha: 0),
                        ],
                        stops: const [0.35, 0.5, 0.65],
                      ).createShader(rect),
                      child: child,
                    ),
                  ),
                ),
                // Kilau bintang di depan lambang.
                CustomPaint(size: Size.square(size), painter: _RankFxPainter(i, t, behind: false)),
              ],
            );
          },
        ),
      ),
    );
  }
}

const double _tau = math.pi * 2;

/// Partikel & kilau bintang. Jumlah dan warnanya naik mengikuti rank.
class _RankFxPainter extends CustomPainter {
  _RankFxPainter(this.i, this.t, {required this.behind});

  final int i;
  final double t;
  final bool behind;

  @override
  bool shouldRepaint(covariant _RankFxPainter o) => o.t != t || o.i != i;

  @override
  void paint(Canvas canvas, Size size) {
    final tier = kRankTiers[i];
    final w = size.width;
    final c = Offset(w / 2, w / 2);
    if (behind) {
      // Partikel cahaya naik (Silver ke atas), makin banyak di rank tinggi.
      if (i < 2) return;
      final n = 3 + i;
      final col = i == 11 ? const Color(0xFFFF4D5E) : tier.hi;
      for (var k = 0; k < n; k++) {
        final ph = (t * (1 + (k % 3)) + k / n) % 1;
        final a = math.sin(ph * math.pi);
        final x = c.dx + math.sin(k * 12.9898) * w * 0.38 + math.sin(ph * _tau + k) * w * 0.02;
        final y = c.dy + w * 0.32 - ph * w * 0.72;
        canvas.drawCircle(
          Offset(x, y),
          w * (0.008 + (k % 3) * 0.003),
          Paint()..color = (k.isOdd ? col : Colors.white).withValues(alpha: (a * 0.85).clamp(0.0, 1.0).toDouble()),
        );
      }
      return;
    }
    // Kilau bintang 4 sisi yang berkedip di sekitar lambang.
    final n = i < 3 ? 2 : (i < 9 ? 3 : 5);
    for (var k = 0; k < n; k++) {
      final ph = (t * 2 + k / n) % 1;
      final a = math.pow(math.sin(ph * math.pi), 3).toDouble();
      if (a < 0.02) continue;
      final ang = k * 2.39996 + 0.7;
      final rr = w * (0.30 + 0.08 * ((k * 37) % 5) / 5);
      final p = Offset(c.dx + math.cos(ang) * rr, c.dy + math.sin(ang) * rr * 0.8);
      final r = w * (0.025 + 0.02 * a);
      final star = Path()
        ..moveTo(p.dx, p.dy - r)
        ..quadraticBezierTo(p.dx, p.dy, p.dx + r, p.dy)
        ..quadraticBezierTo(p.dx, p.dy, p.dx, p.dy + r)
        ..quadraticBezierTo(p.dx, p.dy, p.dx - r, p.dy)
        ..quadraticBezierTo(p.dx, p.dy, p.dx, p.dy - r)
        ..close();
      canvas.drawPath(
        star,
        Paint()
          ..color = tier.hi.withValues(alpha: a * 0.9)
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, w * 0.02),
      );
      canvas.drawPath(star, Paint()..color = Colors.white.withValues(alpha: a));
    }
  }
}

// ---------------------------------------------------------------------------
// Kartu rank di profil
// ---------------------------------------------------------------------------

/// Kartu rank di profil (sendiri & publik): lambang besar, nama rank, dan
/// progress menuju rank berikutnya. Ketuk = daftar semua rank.
class ProfileRankCard extends ConsumerWidget {
  const ProfileRankCard({super.key, required this.uid});

  final String uid;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (uid.isEmpty) return const SizedBox.shrink();
    final async = ref.watch(myXpProvider(uid));
    // Masih memuat pertama kali: jangan tampilkan Rookie dulu lalu berubah.
    if (async.isLoading && !async.hasValue) return const SizedBox.shrink();
    final xp = async.valueOrNull;
    final level = xp?.level ?? 1;
    final idx = rankIndexForLevel(level);
    final tier = kRankTiers[idx];
    final next = idx + 1 < kRankTiers.length ? kRankTiers[idx + 1] : null;
    final levelFrac = XpLevelFormula.progress(xp?.totalXp ?? 0, level).fraction;
    final frac = next == null
        ? 1.0
        : (((level - tier.min) + levelFrac) / (next.min - tier.min)).clamp(0.0, 1.0).toDouble();
    final left = next == null ? 0 : next.min - level;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: ZPress(
        onTap: () => showRankListSheet(context, idx),
        child: Container(
          padding: const EdgeInsets.fromLTRB(6, 6, 8, 6),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
              colors: [tier.mid.withValues(alpha: 0.16), const Color(0x8C0B0E14)],
            ),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: tier.mid.withValues(alpha: 0.35)),
          ),
          child: Row(
            children: [
              RankEmblem(tier: idx, size: 84),
              const SizedBox(width: 6),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('RANK',
                        style: TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 1.2)),
                    ShaderMask(
                      shaderCallback: (r) => LinearGradient(colors: [tier.hi, tier.mid]).createShader(r),
                      child: Text(tier.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w900)),
                    ),
                    const SizedBox(height: 6),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(99),
                      child: SizedBox(
                        height: 7,
                        child: Stack(
                          children: [
                            Container(color: Colors.white.withValues(alpha: 0.10)),
                            FractionallySizedBox(
                              widthFactor: frac,
                              child: Container(
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(colors: [tier.mid, (next ?? tier).mid]),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      next == null
                          ? 'Lv ${_fmtNum(level)} · Rank tertinggi'
                          : 'Lv ${_fmtNum(level)} · ${_fmtNum(left)} level lagi ke ${next.name}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: AppColors.textSecondary, fontSize: 11),
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

/// Daftar semua rank. Rank yang belum tercapai tampil redup.
Future<void> showRankListSheet(BuildContext context, int current) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: const Color(0xFF10131B),
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
    builder: (ctx) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.75,
      maxChildSize: 0.92,
      minChildSize: 0.4,
      builder: (ctx, scroll) => ListView(
        controller: scroll,
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 24),
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(99)),
            ),
          ),
          const SizedBox(height: 14),
          const Text('Tingkat Rank',
              style: TextStyle(color: AppColors.textWhite, fontSize: 18, fontWeight: FontWeight.w900)),
          const SizedBox(height: 4),
          const Text('Rank naik otomatis mengikuti level. Kumpulkan XP untuk membuka rank berikutnya.',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
          const SizedBox(height: 14),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: kRankTiers.length,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              mainAxisSpacing: 10,
              crossAxisSpacing: 10,
              childAspectRatio: 0.78,
            ),
            itemBuilder: (_, i) => _RankTile(index: i, current: current),
          ),
        ],
      ),
    ),
  );
}

const _greyscale = ColorFilter.matrix(<double>[
  0.2126, 0.7152, 0.0722, 0, 0, //
  0.2126, 0.7152, 0.0722, 0, 0, //
  0.2126, 0.7152, 0.0722, 0, 0, //
  0, 0, 0, 1, 0,
]);

class _RankTile extends StatelessWidget {
  const _RankTile({required this.index, required this.current});

  final int index, current;

  @override
  Widget build(BuildContext context) {
    final t = kRankTiers[index];
    final isCur = index == current;
    final locked = index > current;
    Widget emblem = RankEmblem(tier: index, size: 72, animate: isCur);
    if (locked) emblem = Opacity(opacity: 0.45, child: ColorFiltered(colorFilter: _greyscale, child: emblem));
    return Container(
      decoration: BoxDecoration(
        color: isCur ? t.mid.withValues(alpha: 0.14) : Colors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: isCur ? t.mid.withValues(alpha: 0.8) : Colors.white.withValues(alpha: 0.08)),
      ),
      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          emblem,
          Text(t.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  color: locked ? AppColors.textSecondary : t.hi, fontSize: 12.5, fontWeight: FontWeight.w900)),
          Text('Lv ${rankRangeLabel(index)}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: AppColors.textSecondary, fontSize: 10)),
          if (isCur)
            Padding(
              padding: const EdgeInsets.only(top: 3),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1.5),
                decoration: BoxDecoration(color: t.mid, borderRadius: BorderRadius.circular(99)),
                child: const Text('Saat ini',
                    style: TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.w800)),
              ),
            ),
        ],
      ),
    );
  }
}

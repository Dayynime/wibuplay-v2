import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' show FontFeature;

import 'package:flutter/material.dart';

import '../../core/decor_tick.dart';
import '../../core/theme/app_colors.dart';
import '../components/game_badges.dart';
import 'z_kit.dart';

// =============================================================================
// Kit tampilan papan peringkat (Leaderboard XP & Top Giver): podium 3 kartu
// bergradien medali dengan karangan daun, panel daftar peringkat 4+.
// Murni tampilan; data & aksi tap diberikan oleh layar pemakainya.
// =============================================================================

class ZMedal {
  ZMedal._();

  static const Color gold = Color(0xFFF6BE4F);
  static const Color goldDeep = Color(0xFFE08A1E);
  static const Color silver = Color(0xFFD5DEEC);
  static const Color silverDeep = Color(0xFF2F63D8);
  static const Color bronze = Color(0xFFF0A35E);
  static const Color bronzeDeep = Color(0xFFC2552A);
  static const Color xp = AppColors.accentTeal;

  /// Warna karangan daun di daftar (emas lembut).
  static const Color laurel = Color(0xFFE2B04A);
}

String zGroupInt(int n) {
  final s = n.toString();
  final b = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) b.write('.');
    b.write(s[i]);
  }
  return b.toString();
}

String _ordinal(int n) {
  final mod100 = n % 100;
  if (mod100 >= 11 && mod100 <= 13) return 'th';
  return switch (n % 10) { 1 => 'st', 2 => 'nd', 3 => 'rd', _ => 'th' };
}

/// Ikon (permata) + nilai (gaya referensi leaderboard).
class ZGemValue extends StatelessWidget {
  const ZGemValue(this.text, {super.key, this.size = 15, this.color = ZMedal.xp, this.icon = Icons.diamond_rounded});

  final String text;
  final double size;
  final Color color;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: size * 0.95, color: color),
        SizedBox(width: size * 0.3),
        Text(
          text,
          maxLines: 1,
          style: ZFont.display(size: size, color: color, height: 1.1).copyWith(
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// KARANGAN DAUN + PERINGKAT
// ─────────────────────────────────────────────────────────────────────────────

/// Karangan daun (laurel) dengan angka peringkat + akhiran kecil di tengah.
class ZLaurelRank extends StatelessWidget {
  const ZLaurelRank({super.key, required this.rank, required this.size, required this.color, this.glow = false});

  final int rank;
  final double size;
  final Color color;
  final bool glow;

  @override
  Widget build(BuildContext context) {
    // Lapisan sendiri: digambar sekali lalu dipakai ulang, tidak ikut
    // digambar ulang saat border avatar animasi di sebelahnya berganti frame.
    return RepaintBoundary(
      child: SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _LaurelPainter(color, glow: glow),
        child: Center(
          child: Padding(
            padding: EdgeInsets.only(bottom: size * 0.06),
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: '$rank',
                    style: ZFont.display(size: size * 0.34, color: Colors.white, height: 1),
                  ),
                  WidgetSpan(
                    alignment: PlaceholderAlignment.top,
                    child: Padding(
                      padding: EdgeInsets.only(left: size * 0.01),
                      child: Text(
                        _ordinal(rank),
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: size * 0.15,
                          fontWeight: FontWeight.w700,
                          height: 1,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
    );
  }
}

class _LaurelPainter extends CustomPainter {
  _LaurelPainter(this.color, {this.glow = false});

  final Color color;
  final bool glow;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final c = Offset(w / 2, size.height * 0.52);
    final r = w * 0.38;
    final leaf = Paint()..color = color;
    final stem = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(1.0, w * 0.025)
      ..strokeCap = StrokeCap.round;
    if (glow) {
      // Cahaya lembut tanpa blur (blur mahal di GPU).
      canvas.drawCircle(
        c,
        r * 1.25,
        Paint()
          ..shader = RadialGradient(
            colors: [color.withValues(alpha: 0.30), color.withValues(alpha: 0)],
          ).createShader(Rect.fromCircle(center: c, radius: r * 1.25)),
      );
    }

    // Dua tangkai melengkung dari bawah ke atas (kiri & kanan).
    const start = 0.66 * math.pi; // bawah-kiri
    const end = 1.34 * math.pi; // atas-kiri
    canvas.drawArc(Rect.fromCircle(center: c, radius: r), start, end - start, false, stem);
    canvas.drawArc(Rect.fromCircle(center: c, radius: r), math.pi - end, end - start, false, stem);

    const n = 6;
    final lw = w * 0.16, lh = w * 0.065;
    for (var side = 0; side < 2; side++) {
      for (var i = 0; i < n; i++) {
        final t = i / (n - 1);
        var a = start + (end - start) * t;
        if (side == 1) a = math.pi - a;
        final p = c + Offset(math.cos(a), math.sin(a)) * r;
        // Sepasang daun mengarah ke atas sepanjang tangkai, mengecil di ujung.
        final scale = 1.0 - 0.3 * t;
        final tangent = side == 0 ? a + math.pi / 2 : a - math.pi / 2;
        for (final dir in const [0.6, -0.6]) {
          canvas.save();
          canvas.translate(p.dx, p.dy);
          canvas.rotate(tangent + dir);
          canvas.drawOval(
            Rect.fromCenter(
              center: Offset(lw * 0.5 * scale, 0),
              width: lw * scale,
              height: lh * scale,
            ),
            leaf,
          );
          canvas.restore();
        }
      }
    }
  }

  @override
  bool shouldRepaint(_LaurelPainter old) => old.color != color || old.glow != glow;
}

// ─────────────────────────────────────────────────────────────────────────────
// PODIUM
// ─────────────────────────────────────────────────────────────────────────────

/// Data satu kartu podium.
class ZPodiumItem {
  const ZPodiumItem({
    required this.rank,
    required this.uid,
    required this.username,
    required this.value,
    required this.valueText,
    this.avatarUrl,
    this.isMe = false,
    this.nameTrailing,
    this.extra,
    this.icon = Icons.diamond_rounded,
  });

  final int rank;
  final String uid;
  final String username;
  final String? avatarUrl;
  final bool isMe;

  /// Angka utama (dihitung naik saat masuk) + cara menampilkannya.
  final int value;
  final String Function(int v) valueText;
  final IconData icon;

  /// Widget kecil di samping nama (mis. centang).
  final Widget? nameTrailing;

  /// Baris tambahan di bawah nama (mis. tag clan / badge).
  final Widget? extra;
}

/// Podium 3 kartu tinggi (2 kiri, 1 tengah, 3 kanan) bergradien medali.
class ZPodium extends StatefulWidget {
  const ZPodium({super.key, required this.items, required this.onTap});

  /// Maks 3 item, urut peringkat 1, 2, 3.
  final List<ZPodiumItem> items;
  final void Function(ZPodiumItem item) onTap;

  @override
  State<ZPodium> createState() => _ZPodiumState();
}

class _ZPodiumState extends State<ZPodium> with TickerProviderStateMixin {
  // Animasi masuk sekali jalan: kartu naik berurutan 3 → 2 → 1, angka menghitung.
  late final AnimationController _intro = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1600),
  );

  // Kilau berkala di kartu (loop 4 dtk, digambar ulang maks DecorTick.fps).
  late final AnimationController _loop = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 4),
  );
  late final Animation<double> _loopTick = DecorAnimation(_loop);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _intro.value = 1;
      _loop.stop();
    } else {
      if (_intro.isDismissed) _intro.forward();
      if (!_loop.isAnimating) _loop.repeat();
    }
  }

  @override
  void dispose() {
    _intro.dispose();
    _loop.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ZPodiumItem? at(int i) => i < widget.items.length ? widget.items[i] : null;

    Widget slot(int rank) {
      final e = at(rank - 1);
      if (e == null) return const Expanded(child: SizedBox.shrink());
      final cfg = switch (rank) {
        1 => (ZMedal.gold, ZMedal.goldDeep, 196.0, 74.0, 0.20),
        2 => (ZMedal.silver, ZMedal.silverDeep, 164.0, 62.0, 0.10),
        _ => (ZMedal.bronze, ZMedal.bronzeDeep, 164.0, 62.0, 0.0),
      };
      return Expanded(
        flex: rank == 1 ? 11 : 10,
        child: _ZPodiumCard(
          item: e,
          rank: rank,
          light: cfg.$1,
          deep: cfg.$2,
          height: cfg.$3,
          avatarSize: cfg.$4,
          start: cfg.$5,
          intro: _intro,
          loop: _loopTick,
          onTap: () => widget.onTap(e),
        ),
      );
    }

    return RepaintBoundary(
      child: Padding(
        padding: const EdgeInsets.only(top: 6, bottom: 14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            slot(2),
            const SizedBox(width: 8),
            slot(1),
            const SizedBox(width: 8),
            slot(3),
          ],
        ),
      ),
    );
  }
}

class _ZPodiumCard extends StatelessWidget {
  const _ZPodiumCard({
    required this.item,
    required this.rank,
    required this.onTap,
    required this.light,
    required this.deep,
    required this.height,
    required this.avatarSize,
    required this.start,
    required this.intro,
    required this.loop,
  });

  final ZPodiumItem item;
  final int rank;
  final VoidCallback onTap;
  final Color light;
  final Color deep;
  final double height;
  final double avatarSize;
  final double start;
  final Animation<double> intro;
  final Animation<double> loop;

  @override
  Widget build(BuildContext context) {
    final card = GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            height: height,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                // Kartu bergradien: gelap di atas, warna medali di bawah.
                Positioned.fill(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              stops: const [0, 0.45, 1],
                              colors: [
                                AppColors.surfaceDark,
                                Color.lerp(AppColors.surfaceDark, deep, 0.55)!,
                                deep,
                              ],
                            ),
                          ),
                        ),
                        // Kilau diagonal berkala (juara 1 lebih terang). Lapisan
                        // sendiri, digambar ulang maks DecorTick.fps.
                        RepaintBoundary(
                          child: AnimatedBuilder(
                            animation: loop,
                            builder: (context, _) {
                              final v = loop.value;
                              return DecoratedBox(
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    begin: Alignment(-3 + 6 * v, -1),
                                    end: Alignment(-2 + 6 * v, 1),
                                    colors: [
                                      Colors.white.withValues(alpha: 0),
                                      Colors.white.withValues(alpha: rank == 1 ? 0.16 : 0.08),
                                      Colors.white.withValues(alpha: 0),
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                        // Garis tepi atas berkilau warna medali.
                        Positioned(
                          top: 0,
                          left: 0,
                          right: 0,
                          height: 2,
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: [light.withValues(alpha: 0), light, light.withValues(alpha: 0)],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                // Karangan daun + peringkat di atas kartu.
                Positioned(
                  top: rank == 1 ? 8 : 10,
                  left: 0,
                  right: 0,
                  child: Center(
                    child: ZLaurelRank(
                      rank: rank,
                      size: rank == 1 ? 74 : 62,
                      color: light,
                      glow: rank == 1,
                    ),
                  ),
                ),
                // Avatar besar di bawah kartu (border yang dibeli tetap tampil).
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 10,
                  child: Center(
                    // Border avatar bisa animasi: lapisan sendiri supaya kartu
                    // (gradien, karangan daun) tidak ikut digambar ulang.
                    child: RepaintBoundary(
                      child: UserAvatar(
                        username: item.username,
                        url: item.avatarUrl,
                        size: avatarSize,
                        frameUid: item.uid,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: Text(
                  item.username + (item.isMe ? ' (Kamu)' : ''),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: AppColors.textWhite,
                    fontSize: rank == 1 ? 13.5 : 12.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              if (item.nameTrailing != null)
                Padding(padding: const EdgeInsets.only(left: 3), child: item.nameTrailing),
            ],
          ),
          if (item.extra != null) ...[
            const SizedBox(height: 4),
            FittedBox(fit: BoxFit.scaleDown, child: item.extra),
          ],
          const SizedBox(height: 4),
          AnimatedBuilder(
            animation: intro,
            builder: (context, _) {
              final count = Interval(start + 0.2, 1, curve: Curves.easeOutCubic).transform(intro.value);
              return FittedBox(
                fit: BoxFit.scaleDown,
                child: ZGemValue(
                  item.valueText((item.value * count).round()),
                  icon: item.icon,
                  size: rank == 1 ? 17 : 15,
                  color: Colors.white,
                ),
              );
            },
          ),
        ],
      ),
    );

    // Masuk: naik + memudar berurutan.
    return AnimatedBuilder(
      animation: intro,
      child: card,
      builder: (context, child) {
        final v = Interval(start, start + 0.5, curve: Curves.easeOutCubic).transform(intro.value);
        return Opacity(
          opacity: v,
          child: Transform.translate(offset: Offset(0, 30 * (1 - v)), child: child),
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// PANEL DAFTAR PERINGKAT 4+
// ─────────────────────────────────────────────────────────────────────────────

/// Kepala panel: sudut atas membulat + tonjolan bercahaya di tengah.
class ZPanelTop extends StatelessWidget {
  const ZPanelTop({super.key});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 22,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(
            top: 6,
            child: DecoratedBox(
              decoration: const BoxDecoration(
                color: AppColors.surfaceDark,
                borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
              ),
            ),
          ),
          // Tonjolan bercahaya (penanda panel).
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: Center(
              child: Container(
                width: 72,
                height: 7,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(colors: [AppColors.accentViolet, AppColors.accentTeal]),
                  borderRadius: BorderRadius.circular(6),
                  boxShadow: [
                    BoxShadow(color: AppColors.accentTeal.withValues(alpha: 0.55), blurRadius: 14),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class ZPanelBottom extends StatelessWidget {
  const ZPanelBottom({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 16,
      decoration: const BoxDecoration(
        color: AppColors.surfaceDark,
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(24)),
      ),
    );
  }
}

/// Fade + geser halus saat baris pertama kali muncul (hanya ~10 baris pertama,
/// sisanya langsung tampil supaya scroll tetap ringan).
class ZStaggerIn extends StatefulWidget {
  const ZStaggerIn({super.key, required this.index, required this.child, this.enabled = true});

  final int index;
  final Widget child;

  /// false = langsung tampil tanpa animasi.
  final bool enabled;

  @override
  State<ZStaggerIn> createState() => _ZStaggerInState();
}

class _ZStaggerInState extends State<ZStaggerIn> with SingleTickerProviderStateMixin {
  late final bool _animate = widget.enabled && widget.index < 10;
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 460),
  );
  late final Animation<double> _curve = CurvedAnimation(parent: _c, curve: Curves.easeOutCubic);
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    if (_animate) {
      // Mulai setelah podium hampir selesai naik.
      _timer = Timer(Duration(milliseconds: 650 + widget.index * 60), () {
        if (mounted) _c.forward();
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_animate) return widget.child;
    return AnimatedBuilder(
      animation: _curve,
      child: widget.child,
      builder: (context, child) => Opacity(
        opacity: _curve.value,
        child: Transform.translate(offset: Offset(0, 12 * (1 - _curve.value)), child: child),
      ),
    );
  }
}

/// Satu baris panel peringkat 4+: avatar, nama, nilai + badge, karangan daun.
class ZRankRow extends StatelessWidget {
  const ZRankRow({
    super.key,
    required this.rank,
    required this.uid,
    required this.username,
    required this.value,
    required this.onTap,
    this.avatarUrl,
    this.nameTrailing,
    this.badges = const [],
    this.isMe = false,
    this.last = false,
    this.avatar,
    this.trailing,
  });

  final int rank;
  final String uid;
  final String username;
  final String? avatarUrl;
  final Widget value;
  final Widget? nameTrailing;
  final List<Widget> badges;
  final bool isMe;
  final bool last;
  final VoidCallback onTap;

  /// Ganti avatar bawaan (mis. foto clan).
  final Widget? avatar;

  /// Ganti karangan daun di kanan (mis. panah saat daftar tidak diperingkat).
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    // Peringkat 1-3 memakai warna medali + cahaya, sisanya emas lembut.
    final (laurelColor, glow) = switch (rank) {
      1 => (ZMedal.gold, true),
      2 => (ZMedal.silver, true),
      3 => (ZMedal.bronze, true),
      _ => (ZMedal.laurel, false),
    };
    return DecoratedBox(
      // Bagian tengah panel: warnanya sama supaya menyambung.
      decoration: const BoxDecoration(color: AppColors.surfaceDark),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 6),
          padding: const EdgeInsets.fromLTRB(10, 11, 8, 11),
          decoration: BoxDecoration(
            // Baris milikku disorot biru lembut.
            color: isMe ? AppColors.accentViolet.withValues(alpha: 0.14) : null,
            borderRadius: isMe ? BorderRadius.circular(14) : null,
            border: isMe
                ? Border.all(color: AppColors.accentViolet.withValues(alpha: 0.4))
                : (last ? null : Border(bottom: BorderSide(color: Colors.white.withValues(alpha: 0.07)))),
          ),
          child: Row(
            children: [
              // Border avatar animasi di lapisan sendiri (baris tidak ikut digambar ulang).
              RepaintBoundary(
                child: avatar ?? UserAvatar(username: username, url: avatarUrl, size: 46, frameUid: uid),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            username + (isMe ? ' (Kamu)' : ''),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: AppColors.textWhite,
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        if (nameTrailing != null)
                          Padding(padding: const EdgeInsets.only(left: 4), child: nameTrailing),
                      ],
                    ),
                    const SizedBox(height: 5),
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [value, ...badges],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              trailing ?? ZLaurelRank(rank: rank, size: 46, color: laurelColor, glow: glow),
            ],
          ),
        ),
      ),
    );
  }
}

/// Isi panel di antara kepala & baris (warna panel, padding samping).
class ZPanelBody extends StatelessWidget {
  const ZPanelBody({super.key, required this.child, this.padding = const EdgeInsets.fromLTRB(12, 4, 12, 4)});

  final Widget child;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: AppColors.surfaceDark,
      child: Padding(padding: padding, child: child),
    );
  }
}

/// Pemilih segmen di dalam panel (gaya referensi): pilihan aktif terisi warna.
class ZPanelSegment extends StatelessWidget {
  const ZPanelSegment({super.key, required this.labels, required this.index, required this.onChanged});

  final List<String> labels;
  final int index;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 44,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppColors.backgroundDark.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0x12FFFFFF)),
      ),
      child: LayoutBuilder(
        builder: (context, c) {
          final w = c.maxWidth / labels.length;
          return Stack(
            children: [
              AnimatedPositioned(
                duration: const Duration(milliseconds: 260),
                curve: Curves.easeOutQuint,
                left: index * w,
                top: 0,
                bottom: 0,
                width: w,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: AppColors.accentViolet,
                    borderRadius: BorderRadius.circular(9),
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.accentViolet.withValues(alpha: 0.4),
                        blurRadius: 12,
                        spreadRadius: -4,
                      ),
                    ],
                  ),
                ),
              ),
              Row(
                children: [
                  for (var i = 0; i < labels.length; i++)
                    Expanded(
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () => onChanged(i),
                        child: Center(
                          child: AnimatedDefaultTextStyle(
                            duration: const Duration(milliseconds: 200),
                            style: TextStyle(
                              color: i == index ? Colors.white : AppColors.textSecondary,
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                            ),
                            child: Text(labels[i], maxLines: 1),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }
}

/// Judul pemisah "◆ Peringkat Teratas ◆" dengan garis memudar di kiri-kanan.
class ZPanelDivider extends StatelessWidget {
  const ZPanelDivider(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    const c = ZMedal.laurel;
    Widget line(bool left) => Expanded(
          child: Container(
            height: 1,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: left
                    ? [c.withValues(alpha: 0), c.withValues(alpha: 0.6)]
                    : [c.withValues(alpha: 0.6), c.withValues(alpha: 0)],
              ),
            ),
          ),
        );
    Widget diamond() => Transform.rotate(
          angle: math.pi / 4,
          child: Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(border: Border.all(color: c, width: 1.2)),
          ),
        );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          line(true),
          const SizedBox(width: 6),
          diamond(),
          const SizedBox(width: 8),
          Text(text, style: const TextStyle(color: c, fontSize: 12, fontWeight: FontWeight.w600)),
          const SizedBox(width: 8),
          diamond(),
          const SizedBox(width: 6),
          line(false),
        ],
      ),
    );
  }
}

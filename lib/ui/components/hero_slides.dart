import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/decor_tick.dart';
import '../../core/theme/app_colors.dart';
import '../../data/models/clan_models.dart';
import '../../data/models/support_models.dart';
import '../../data/models/xp_models.dart';
import 'game_badges.dart';
import '../screens/profile/public_profile_screen.dart';
import 'clan_tag_badge.dart';
import '../redesign/z_kit.dart';

// =============================================================================
// Slide leaderboard di carousel Beranda (Top XP / Top Clan, Top Support,
// Top Giver).
//
// Gaya: panel "liquid glass" di atas pemandangan berwarna (warna ikut slide),
// isinya disajikan seperti dashboard data, bukan dekorasi:
//  - Top XP / Clan : angka bergulir per digit (odometer) + bar perbandingan
//                    terhadap peringkat 1, toggle XP | Clan berbentuk lensa cair.
//  - Top Support   : satu bar bertumpuk (porsi tiap donatur) + total.
//  - Top Giver     : grid kotak, 1 kotak = N hari Premium yang dibagikan,
//                    terisi seperti gelombang diagonal.
// Semua animasi masuk diputar ulang tiap slide kelihatan, dan mati kalau HP
// diset "hapus animasi".
// =============================================================================

const Color heroGold = Color(0xFFFFC107);
const Color heroPink = Color(0xFFFF5C8A);
const Color heroTeal = Color(0xFF2DD4BF);

const Color _clanOrange = Color(0xFFFF8A65);
const Color _rose = Color(0xFFFF6F91);
const Color _mint = Color(0xFF34D3B5);
const Color _muted = Color(0xFF9AA0AC);


/// Kurva keluar cepat lalu mendarat halus (dipakai hampir semua gerak).
const Curve _outExpo = Cubic(0.16, 1, 0.3, 1);

/// Kurva pegas: melewati target sedikit lalu kembali (lensa cair).
const Curve _spring = Cubic(0.34, 1.56, 0.64, 1);

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

/// 12500 -> "12.500".
String _groupInt(int v) {
  final s = v.abs().toString();
  final b = StringBuffer(v < 0 ? '-' : '');
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) b.write('.');
    b.write(s[i]);
  }
  return b.toString();
}

/// Ambil potongan [start]..[end] dari timeline [t] (0..1) lalu lewatkan lewat
/// [curve]. Hasil 0 sebelum [start], 1 setelah [end].
double _seg(double t, double start, double end, [Curve curve = Curves.easeOutCubic]) {
  if (t <= start) return 0;
  if (t >= end) return 1;
  return curve.transform((t - start) / (end - start));
}

// ---------------------------------------------------------------------------
// Infrastruktur animasi
// ---------------------------------------------------------------------------

/// Pemilik dua controller untuk satu slide:
///  - `enter`: animasi masuk sekali jalan (stagger), main tiap slide aktif.
///  - `loop` : animasi ambient berulang (kilau kaca yang bergeser pelan).
/// Keduanya cuma jalan selama slide kelihatan ([active]) supaya hemat baterai,
/// dan mati kalau HP diset "hapus animasi".
class _SlideMotion extends StatefulWidget {
  const _SlideMotion({
    super.key,
    required this.active,
    required this.builder,
    this.enterDuration = const Duration(milliseconds: 1500),
    this.loopDuration = const Duration(seconds: 9),
  });

  final bool active;
  final Duration enterDuration;
  final Duration loopDuration;
  final Widget Function(BuildContext context, Animation<double> enter, Animation<double> loop) builder;

  @override
  State<_SlideMotion> createState() => _SlideMotionState();
}

class _SlideMotionState extends State<_SlideMotion> with TickerProviderStateMixin {
  late final AnimationController _enter =
      AnimationController(vsync: this, duration: widget.enterDuration);
  late final AnimationController _loop =
      AnimationController(vsync: this, duration: widget.loopDuration);

  /// Kilau loop digambar ulang maks DecorTick.fps; animasi masuk tetap penuh.
  late final Animation<double> _loopTick = DecorAnimation(_loop);
  bool _reduce = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduce = MediaQuery.disableAnimationsOf(context);
    _sync();
  }

  @override
  void didUpdateWidget(_SlideMotion oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.active != widget.active) _sync();
  }

  void _sync() {
    if (!widget.active) {
      // Slide sudah di luar layar: reset supaya animasi masuk main lagi nanti.
      _enter.value = 0;
      _loop.stop();
      return;
    }
    if (_reduce) {
      _enter.value = 1;
      _loop.stop();
      return;
    }
    if (_enter.status == AnimationStatus.dismissed) _enter.forward();
    // Loop kilau kaca tidak dipakai lagi (latar polos gaya preview): tidak
    // dijalankan supaya tidak ada ticker yang berputar sia-sia.
  }

  @override
  void dispose() {
    _enter.dispose();
    _loop.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.builder(context, _enter, _loopTick);
}

/// Muncul bertahap: fade + geser, mengikuti potongan [start]..[end] dari
/// timeline [t].
class _Reveal extends StatelessWidget {
  const _Reveal({
    required this.t,
    required this.start,
    required this.end,
    required this.child,
    this.dx = 0,
    this.dy = 10,
  });

  final Animation<double> t;
  final double start;
  final double end;
  final double dx;
  final double dy;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: t,
      child: child,
      builder: (context, child) {
        final v = _seg(t.value, start, math.min(1.0, end), _outExpo);
        return Opacity(
          opacity: v.clamp(0.0, 1.0).toDouble(),
          child: Transform.translate(offset: Offset(dx * (1 - v), dy * (1 - v)), child: child),
        );
      },
    );
  }
}

/// Efek tekan: mengecil sedikit + agak pudar selama jari menempel.
class _Pressable extends StatefulWidget {
  const _Pressable({
    required this.onTap,
    required this.child,
    this.pressedScale = 0.96,
    this.alignment = Alignment.center,
  });

  final VoidCallback? onTap;
  final Widget child;
  final double pressedScale;
  final Alignment alignment;

  @override
  State<_Pressable> createState() => _PressableState();
}

class _PressableState extends State<_Pressable> {
  bool _down = false;

  void _set(bool v) {
    if (_down != v && mounted) setState(() => _down = v);
  }

  @override
  Widget build(BuildContext context) {
    if (widget.onTap == null) return widget.child;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => _set(true),
      onTapUp: (_) => _set(false),
      onTapCancel: () => _set(false),
      onTap: widget.onTap,
      child: AnimatedScale(
        scale: _down ? widget.pressedScale : 1.0,
        alignment: widget.alignment,
        duration: const Duration(milliseconds: 110),
        curve: Curves.easeOut,
        child: AnimatedOpacity(
          opacity: _down ? 0.85 : 1.0,
          duration: const Duration(milliseconds: 110),
          child: widget.child,
        ),
      ),
    );
  }
}

/// Parallax saat geser antar slide: lapisan ini bergerak lebih lambat dari
/// kartunya ([depth] = fraksi lebar). Struktur widget sengaja tetap supaya
/// state anak tidak ke-reset waktu offset melewati 0.
class _ParallaxLayer extends StatelessWidget {
  const _ParallaxLayer({
    required this.offset,
    required this.depth,
    required this.child,
    this.fade = false,
  });

  final ValueListenable<double>? offset;
  final double depth;
  final bool fade;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final o = offset;
    if (o == null) return child;
    return ValueListenableBuilder<double>(
      valueListenable: o,
      child: child,
      builder: (context, d, child) {
        final opacity = fade ? (1 - d.abs() * 0.6).clamp(0.0, 1.0).toDouble() : 1.0;
        return Opacity(
          opacity: opacity,
          child: FractionalTranslation(translation: Offset(d * depth, 0), child: child),
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Panggung kaca: pemandangan berwarna + panel liquid glass di atasnya
// ---------------------------------------------------------------------------

class _ScenePalette {
  const _ScenePalette(this.sky, this.moon, this.far, this.near, this.moonX);

  final Color sky;
  final Color moon;
  final Color far;
  final Color near;

  /// Posisi bulan (0 = kiri, 1 = kanan).
  final double moonX;
}

const _ScenePalette _sceneXp =
    _ScenePalette(Color(0xFF122047), Color(0xFF6CB8FF), Color(0xFF1E3A78), Color(0xFF0B1430), 0.78);
const _ScenePalette _sceneSupport =
    _ScenePalette(Color(0xFF3A1426), Color(0xFFFF6F91), Color(0xFF6B2340), Color(0xFF1E0B14), 0.22);
const _ScenePalette _sceneGiver =
    _ScenePalette(Color(0xFF0D3A3D), Color(0xFF5EEAD4), Color(0xFF145457), Color(0xFF082224), 0.55);

class _GlassStage extends StatelessWidget {
  const _GlassStage({
    required this.palette,
    required this.accent,
    required this.loop,
    required this.child,
    this.pageOffset,
    this.onTap,
  });

  final _ScenePalette palette;
  final Color accent;
  final Animation<double> loop;
  final Widget child;
  final ValueListenable<double>? pageOffset;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    // Gaya preview: latar biru laut polos + tekstur titik di pojok, tanpa
    // pemandangan/kaca (lebih ringan digambar saat carousel bergeser).
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Stack(
        fit: StackFit.expand,
        children: [
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topRight,
                end: Alignment.bottomLeft,
                // Latar sama untuk semua slide (biru laut), tanpa rona warna
                // per slide, seperti preview.
                colors: [AppColors.surfaceVariantDark, AppColors.surfaceDark],
              ),
            ),
          ),
          const ZScreentone(opacity: 0.12),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
            child: _ParallaxLayer(
              offset: pageOffset,
              depth: 0.06,
              fade: true,
              child: child,
            ),
          ),
        ],
      ),
    );
  }
}

/// Angka yang bergulir per digit seperti odometer. Karakter selain angka
/// (titik, huruf, "Rp") tampil diam.
class _Odometer extends StatelessWidget {
  const _Odometer({
    required this.text,
    required this.style,
    required this.t,
    required this.start,
    this.span = 0.5,
    this.stagger = 0.035,
  });

  final String text;
  final TextStyle style;
  final Animation<double> t;
  final double start;
  final double span;
  final double stagger;

  @override
  Widget build(BuildContext context) {
    final s = style.copyWith(
      height: 1.2,
      fontFeatures: const [ui.FontFeature.tabularFigures()],
    );
    final h = (s.fontSize ?? 14) * 1.2;
    final children = <Widget>[];
    var k = 0;
    for (final ch in text.split('')) {
      final code = ch.codeUnitAt(0);
      if (code >= 48 && code <= 57) {
        final digit = code - 48;
        final a = math.min(0.95, start + k * stagger);
        k++;
        children.add(
          ClipRect(
            child: Align(
              alignment: Alignment.topCenter,
              heightFactor: 0.1,
              child: AnimatedBuilder(
                animation: t,
                builder: (context, child) {
                  final p = _seg(t.value, a, math.min(1.0, a + span), _outExpo);
                  return Transform.translate(offset: Offset(0, -h * digit * p), child: child);
                },
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (var d = 0; d < 10; d++) SizedBox(height: h, child: Text('$d', style: s)),
                  ],
                ),
              ),
            ),
          ),
        );
      } else {
        children.add(SizedBox(height: h, child: Text(ch, style: s)));
      }
    }
    return Row(mainAxisSize: MainAxisSize.min, children: children);
  }
}

/// Bar tipis yang tergambar dari kiri sampai [ratio] (0..1).
class _Bar extends StatelessWidget {
  const _Bar({required this.ratio, required this.color, required this.t, required this.start});

  final double ratio;
  final Color color;
  final Animation<double> t;
  final double start;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(2),
      child: SizedBox(
        height: 3,
        child: ColoredBox(
          color: const Color(0x1AFFFFFF),
          child: AnimatedBuilder(
            animation: t,
            builder: (context, _) {
              final p = _seg(t.value, start, math.min(1.0, start + 0.5), _outExpo);
              return Align(
                alignment: Alignment.centerLeft,
                child: FractionallySizedBox(
                  widthFactor: (ratio * p).clamp(0.0, 1.0).toDouble(),
                  heightFactor: 1,
                  child: ColoredBox(color: color),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

Widget _titleBlock(String title, String subtitle) {
  return Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: ZFont.display(size: 20, height: 1.1),
      ),
      const SizedBox(height: 2),
      Text(
        subtitle,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(color: AppColors.textMuted, fontSize: 11.5, height: 1.2),
      ),
    ],
  );
}

const Widget _empty = Center(
  child: Text('Belum ada data', style: TextStyle(color: Color(0x66FFFFFF), fontSize: 11)),
);

/// Toggle dua pilihan dengan lensa kaca yang meluncur, melar lalu memantul
/// seperti tetesan cairan saat pindah.
class _LiquidSegment extends StatefulWidget {
  const _LiquidSegment({required this.labels, required this.index, required this.onChanged});

  final List<String> labels;
  final int index;
  final ValueChanged<int> onChanged;

  @override
  State<_LiquidSegment> createState() => _LiquidSegmentState();
}

class _LiquidSegmentState extends State<_LiquidSegment> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 560),
    value: 1,
  );
  late int _from = widget.index;

  static const double _segW = 50;
  static const double _h = 34;
  static const double _pad = 3;

  @override
  void didUpdateWidget(_LiquidSegment old) {
    super.didUpdateWidget(old);
    if (old.index != widget.index) {
      _from = old.index;
      if (MediaQuery.disableAnimationsOf(context)) {
        _c.value = 1;
      } else {
        _c.forward(from: 0);
      }
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final n = widget.labels.length;
    return Container(
      width: _segW * n + _pad * 2,
      height: _h,
      padding: const EdgeInsets.all(_pad),
      decoration: BoxDecoration(
        color: const Color(0x47000000),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0x1FFFFFFF)),
      ),
      child: Stack(
        children: [
          AnimatedBuilder(
            animation: _c,
            builder: (context, _) {
              final t = _c.value;
              final x = ui.lerpDouble(_from * _segW, widget.index * _segW, _spring.transform(t))!;
              final w = math.sin(math.pi * t);
              return Positioned(
                left: x,
                top: 0,
                bottom: 0,
                width: _segW,
                child: Transform(
                  alignment: Alignment.center,
                  transform: Matrix4.diagonal3Values(1 + 0.24 * w, 1 - 0.16 * w, 1),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(9),
                      border: Border.all(color: const Color(0x38FFFFFF)),
                      gradient: const LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [Color(0x42FFFFFF), Color(0x1AFFFFFF)],
                      ),
                      boxShadow: const [
                        BoxShadow(color: Color(0x66000000), blurRadius: 10, offset: Offset(0, 4)),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
          Row(
            children: [
              for (var i = 0; i < n; i++)
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () {
                    if (i == widget.index) return;
                    HapticFeedback.selectionClick();
                    widget.onChanged(i);
                  },
                  child: SizedBox(
                    width: _segW,
                    height: _h - _pad * 2,
                    child: Center(
                      child: AnimatedDefaultTextStyle(
                        duration: const Duration(milliseconds: 250),
                        style: TextStyle(
                          color: i == widget.index ? Colors.white : _muted,
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                        ),
                        child: Text(widget.labels[i]),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Slide Top XP / Top Clan
// ---------------------------------------------------------------------------

// ---------------------------------------------------------------------------
// Tata letak slide leaderboard (gaya preview): judul + sub di kiri atas,
// kontrol/chip di kanan, 3 baris peringkat dengan bar, lalu footer.
// ---------------------------------------------------------------------------

const Color _lbGold = Color(0xFFF6BE4F);

Widget _lbHeader(Animation<double> t, String title, String sub, {Widget? trailing}) {
  return Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Expanded(
        child: _Reveal(t: t, start: 0, end: 0.3, dy: -6, child: _titleBlock(title, sub)),
      ),
      if (trailing != null) ...[const SizedBox(width: 10), trailing],
    ],
  );
}

Widget _lbFooter(Widget left, String action) {
  return SizedBox(
    height: 18,
    child: Row(
      children: [
        Expanded(
          child: DefaultTextStyle.merge(
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: AppColors.textMuted, fontSize: 12),
            child: left,
          ),
        ),
        Text(
          action,
          style: const TextStyle(color: AppColors.textWhite, fontSize: 12, fontWeight: FontWeight.w700),
        ),
        const Icon(Icons.chevron_right_rounded, size: 16, color: AppColors.textWhite),
      ],
    ),
  );
}

Widget _lbRow({
  required int i,
  required int rank,
  required Animation<double> t,
  required Color accent,
  required Widget avatar,
  required String name,
  required double ratio,
  required String value,
  Widget? nameTrailing,
  VoidCallback? onTap,
}) {
  final start = 0.06 + i * 0.08;
  return _Reveal(
    t: t,
    start: start,
    end: start + 0.32,
    dx: -12,
    dy: 0,
    child: _Pressable(
      onTap: onTap,
      alignment: Alignment.centerLeft,
      child: SizedBox(
        height: 32,
        child: Row(
          children: [
            SizedBox(
              width: 20,
              child: Text(
                '$rank',
                textAlign: TextAlign.center,
                style: ZFont.display(size: 15, color: rank == 1 ? _lbGold : AppColors.textMuted, height: 1),
              ),
            ),
            const SizedBox(width: 10),
            avatar,
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: AppColors.textWhite,
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            height: 1.2,
                          ),
                        ),
                      ),
                      if (nameTrailing != null) ...[const SizedBox(width: 5), nameTrailing],
                    ],
                  ),
                  const SizedBox(height: 5),
                  _Bar(ratio: ratio, color: accent.withValues(alpha: i == 0 ? 1 : 0.6), t: t, start: start + 0.06),
                ],
              ),
            ),
            const SizedBox(width: 10),
            _Odometer(
              text: value,
              style: ZFont.display(size: 14),
              t: t,
              start: start + 0.04,
            ),
          ],
        ),
      ),
    ),
  );
}

/// Badan slide: header, daftar (mengisi ruang), footer.
Widget _lbBody({required Widget header, required Widget list, required Widget footer}) {
  return Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      header,
      const SizedBox(height: 10),
      Expanded(child: list),
      const SizedBox(height: 8),
      footer,
    ],
  );
}

class HeroLeaderboardSlide extends StatefulWidget {
  const HeroLeaderboardSlide({
    super.key,
    required this.entries,
    required this.clans,
    required this.onTap,
    this.onClanTap,
    this.active = true,
    this.pageOffset,
  });

  final List<UserXpDisplay> entries;
  final List<ClanSummary> clans;
  final VoidCallback onTap;

  /// Tap panel saat mode Clan (buka halaman Clan). Null = tidak bisa di-tap.
  final VoidCallback? onClanTap;

  /// true = slide sedang kelihatan (animasi masuk + loop jalan).
  final bool active;

  /// Posisi slide relatif ke tengah pager (-1..1) untuk efek parallax.
  final ValueListenable<double>? pageOffset;

  @override
  State<HeroLeaderboardSlide> createState() => _HeroLeaderboardSlideState();
}

class _HeroLeaderboardSlideState extends State<HeroLeaderboardSlide> {
  bool _clanMode = false;

  @override
  Widget build(BuildContext context) {
    final hasXp = widget.entries.isNotEmpty;
    final hasClan = widget.clans.isNotEmpty;
    final clan = hasXp ? (_clanMode && hasClan) : hasClan;
    final accent = clan ? _clanOrange : AppColors.accentViolet;

    return _SlideMotion(
      active: widget.active,
      enterDuration: const Duration(milliseconds: 1600),
      builder: (context, enter, loop) {
        return _GlassStage(
          palette: _sceneXp,
          accent: accent,
          loop: loop,
          pageOffset: widget.pageOffset,
          onTap: clan ? widget.onClanTap : widget.onTap,
          child: _lbBody(
            header: _lbHeader(
              enter,
              clan ? 'Top Clan' : 'Top XP',
              clan ? 'Level clan' : 'Bulan ini',
              trailing: (hasXp && hasClan)
                  ? _LiquidSegment(
                      labels: const ['XP', 'Clan'],
                      index: clan ? 1 : 0,
                      onChanged: (i) => setState(() => _clanMode = i == 1),
                    )
                  : null,
            ),
            // Daftar punya controller sendiri (di-key per mode) supaya ganti
            // XP <-> Clan memutar ulang odometer & bar dari awal.
            list: _SlideMotion(
              key: ValueKey<bool>(clan),
              active: widget.active,
              enterDuration: const Duration(milliseconds: 1500),
              builder: (context, rowsIn, _) =>
                  clan ? _clanRows(rowsIn, accent) : _xpRows(context, rowsIn, accent),
            ),
            footer: _lbFooter(
              Text(clan ? 'Clan dengan level tertinggi' : 'Peringkat XP bulan ini'),
              clan ? 'Clan' : 'Leaderboard',
            ),
          ),
        );
      },
    );
  }

  Widget _xpRows(BuildContext context, Animation<double> t, Color accent) {
    final list = widget.entries.take(3).toList();
    if (list.isEmpty) return _empty;
    final max = list.map((e) => e.xp).fold<int>(1, math.max);
    return Column(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        for (var i = 0; i < list.length; i++)
          _lbRow(
            i: i,
            rank: i + 1,
            t: t,
            accent: accent,
            avatar: UserAvatar(
              username: list[i].username,
              url: list[i].avatarUrl,
              size: 30,
              frameUid: list[i].firebaseUid,
            ),
            name: list[i].username,
            ratio: list[i].xp / max,
            value: '${_compactCount(list[i].xp)} XP',
            onTap: () => openPublicProfile(context, list[i].firebaseUid),
          ),
      ],
    );
  }

  Widget _clanRows(Animation<double> t, Color accent) {
    final list = widget.clans.take(3).toList();
    if (list.isEmpty) return _empty;
    final max = list.map((e) => e.level).fold<int>(1, math.max);
    return Column(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        for (var i = 0; i < list.length; i++)
          _lbRow(
            i: i,
            rank: i + 1,
            t: t,
            accent: accent,
            avatar: UserAvatar(username: list[i].tag, url: list[i].photoUrl, size: 30),
            name: list[i].tag,
            ratio: list[i].level / max,
            value: 'Lv ${list[i].level}',
          ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Slide Top Support
// ---------------------------------------------------------------------------

class HeroSupportSlide extends StatelessWidget {
  const HeroSupportSlide({
    super.key,
    required this.supporters,
    this.onTap,
    this.active = true,
    this.pageOffset,
  });

  final List<TopSupporter> supporters;

  /// Tap slide = buka halaman Top Support. Null = tidak bisa di-tap.
  final VoidCallback? onTap;

  /// true = slide sedang kelihatan (animasi masuk + loop jalan).
  final bool active;

  /// Posisi slide relatif ke tengah pager (-1..1) untuk efek parallax.
  final ValueListenable<double>? pageOffset;

  @override
  Widget build(BuildContext context) {
    final top = supporters.take(3).toList();
    final total = top.fold<int>(0, (a, s) => a + s.totalAmount);
    final max = top.map((s) => s.totalAmount).fold<int>(1, math.max);
    return _SlideMotion(
      active: active,
      enterDuration: const Duration(milliseconds: 1800),
      builder: (context, enter, loop) {
        return _GlassStage(
          palette: _sceneSupport,
          accent: _rose,
          loop: loop,
          pageOffset: pageOffset,
          onTap: onTap,
          child: _lbBody(
            header: _lbHeader(
              enter,
              'Top Support',
              'Donatur teratas',
              trailing: const ZChip('Terima kasih', icon: Icons.favorite_rounded, tone: ZTone.gold),
            ),
            list: top.isEmpty
                ? _empty
                : Column(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      for (var i = 0; i < top.length; i++)
                        _lbRow(
                          i: i,
                          rank: top[i].rank,
                          t: enter,
                          accent: AppColors.accentViolet,
                          avatar: UserAvatar(
                            username: top[i].name,
                            url: top[i].avatarUrl,
                            size: 30,
                            frameUid: top[i].firebaseUid,
                          ),
                          name: top[i].name,
                          ratio: top[i].totalAmount / max,
                          value: _compactRupiah(top[i].totalAmount),
                          onTap: (top[i].firebaseUid ?? '').isEmpty
                              ? null
                              : () => openPublicProfile(context, top[i].firebaseUid!),
                        ),
                    ],
                  ),
            footer: _lbFooter(
              Text('Total ${_compactRupiah(total)} dari ${top.length} teratas'),
              'Semua',
            ),
          ),
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Slide Top Giver
// ---------------------------------------------------------------------------

/// Slide "Top Giver" (total hari Premium yang dibagikan, sepanjang masa).
class HeroGiverSlide extends StatelessWidget {
  const HeroGiverSlide({
    super.key,
    required this.givers,
    this.clanTags = const {},
    this.onTap,
    this.active = true,
    this.pageOffset,
  });

  final List<TopGiver> givers;
  final Map<String, String> clanTags;
  final VoidCallback? onTap;
  final bool active;
  final ValueListenable<double>? pageOffset;

  @override
  Widget build(BuildContext context) {
    final top = givers.take(3).toList();
    final totalDays = givers.fold<int>(0, (a, x) => a + x.days);
    final max = top.map((x) => x.days).fold<int>(1, math.max);
    return _SlideMotion(
      active: active,
      enterDuration: const Duration(milliseconds: 1800),
      builder: (context, enter, loop) {
        return _GlassStage(
          palette: _sceneGiver,
          accent: _mint,
          loop: loop,
          pageOffset: pageOffset,
          onTap: onTap,
          child: _lbBody(
            header: _lbHeader(
              enter,
              'Top Giver',
              'Hari Premium yang dibagikan',
              trailing: const ZChip('Gift', icon: Icons.card_giftcard_rounded, tone: ZTone.brand),
            ),
            list: top.isEmpty
                ? _empty
                : Column(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      for (var i = 0; i < top.length; i++)
                        _lbRow(
                          i: i,
                          rank: top[i].rank,
                          t: enter,
                          accent: _mint,
                          avatar: UserAvatar(
                            username: top[i].username,
                            url: top[i].avatarUrl,
                            size: 30,
                            frameUid: top[i].firebaseUid,
                          ),
                          name: top[i].username,
                          nameTrailing: (clanTags[top[i].firebaseUid] ?? '').isEmpty
                              ? null
                              : ClanTagBadge(text: clanTags[top[i].firebaseUid]!, height: 14),
                          ratio: top[i].days / max,
                          value: '${_groupInt(top[i].days)}h',
                          onTap: top[i].firebaseUid.isEmpty
                              ? null
                              : () => openPublicProfile(context, top[i].firebaseUid),
                        ),
                    ],
                  ),
            footer: _lbFooter(
              Text.rich(
                TextSpan(
                  text: 'Total dibagikan ',
                  children: [
                    TextSpan(
                      text: '${_groupInt(totalDays)} hari',
                      style: const TextStyle(color: AppColors.textWhite, fontWeight: FontWeight.w700),
                    ),
                  ],
                ),
              ),
              'Semua',
            ),
          ),
        );
      },
    );
  }
}

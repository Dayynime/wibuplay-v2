import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/theme/app_colors.dart';
import '../../data/models/anichin_models.dart';
import '../screens/donghua/donghua_widgets.dart';

const Color _gold = Color(0xFFFFB300);
const Color _silver = Color(0xFFCFD8DC);
const Color _bronze = Color(0xFFFF9E6B);
const Color _ink = Color(0xFF1A1200);
const double _sectionHeight = 372;

/// Section "Donghua" di Beranda gaya bento: #1 besar di kiri (border emas
/// berputar, poster zoom pelan, tombol play berdenyut), #2 & #3 bertumpuk di
/// kanan. Kartu masuk bergantian, ditekan akan mengecil + haptic.
/// Data: 3 kartu pertama dari Anichin (API-nya belum punya rating/views).
class DonghuaHotSection extends StatefulWidget {
  const DonghuaHotSection({
    super.key,
    required this.cards,
    required this.onCardClick,
    required this.onSeeAllClick,
  });

  final List<AnichinCard> cards;
  final ValueChanged<String> onCardClick;
  final VoidCallback onSeeAllClick;

  @override
  State<DonghuaHotSection> createState() => _DonghuaHotSectionState();
}

class _DonghuaHotSectionState extends State<DonghuaHotSection>
    with TickerProviderStateMixin {
  // Animasi masuk sekali jalan.
  late final AnimationController _enter = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1000),
  )..forward();

  // Animasi ambient yang berulang (border, zoom poster, kilau, denyut).
  late final AnimationController _ambient = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 8),
  )..repeat();

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Hormati setting "hapus animasi" dari sistem.
    if (MediaQuery.disableAnimationsOf(context)) {
      _ambient.stop();
      _enter.value = 1;
    } else if (!_ambient.isAnimating) {
      _ambient.repeat();
    }
  }

  @override
  void dispose() {
    _enter.dispose();
    _ambient.dispose();
    super.dispose();
  }

  void _tap(AnichinCard c) {
    final slug = c.slug;
    if (slug != null && slug.isNotEmpty) widget.onCardClick(slug);
  }

  /// Fade + naik + sedikit membesar, dengan jeda per [index].
  Widget _enterWrap(int index, Widget child) {
    final start = (index * 0.16).clamp(0.0, 0.7);
    final end = (start + 0.6).clamp(0.0, 1.0);
    final curve = Interval(start, end, curve: Curves.easeOutCubic);
    return AnimatedBuilder(
      animation: _enter,
      child: child,
      builder: (context, c) {
        final v = curve.transform(_enter.value);
        return Opacity(
          opacity: v,
          child: Transform.translate(
            offset: Offset(0, 30 * (1 - v)),
            child: Transform.scale(scale: 0.93 + 0.07 * v, child: c),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final top = widget.cards.take(3).toList();
    if (top.isEmpty) return const SizedBox.shrink();

    final hero = _enterWrap(
      0,
      RepaintBoundary(
        child: _Pressable(
          onTap: () => _tap(top[0]),
          child: _HeroCard(card: top[0], ambient: _ambient),
        ),
      ),
    );

    Widget mini(int i) => _enterWrap(
          i,
          RepaintBoundary(
            child: _Pressable(
              onTap: () => _tap(top[i]),
              child: _MiniCard(
                rank: i + 1,
                card: top[i],
                color: i == 1 ? _silver : _bronze,
                ambient: _ambient,
                phase: i * 0.37,
              ),
            ),
          ),
        );

    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _enterWrap(
            0,
            _Header(ambient: _ambient, onSeeAll: widget.onSeeAllClick),
          ),
          SizedBox(
            height: _sectionHeight,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Row(
                children: [
                  Expanded(child: hero),
                  if (top.length > 1) ...[
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        children: [
                          Expanded(child: mini(1)),
                          const SizedBox(height: 10),
                          // Kalau data cuma 2, sisakan ruang biar kartu #2 tidak melar.
                          if (top.length > 2)
                            Expanded(child: mini(2))
                          else
                            const Spacer(),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ------------------------------------------------------------------ helpers

/// 0..1..0 mulus, [times] kali per siklus ambient.
double _pulse(double v, double times) =>
    0.5 - 0.5 * math.cos(2 * math.pi * v * times);

/// Kartu mengecil sedikit saat ditekan + haptic ringan saat diketuk.
class _Pressable extends StatefulWidget {
  const _Pressable({required this.child, required this.onTap});

  final Widget child;
  final VoidCallback onTap;

  @override
  State<_Pressable> createState() => _PressableState();
}

class _PressableState extends State<_Pressable> {
  bool _down = false;

  void _set(bool v) {
    if (_down != v) setState(() => _down = v);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => _set(true),
      onTapUp: (_) => _set(false),
      onTapCancel: () => _set(false),
      onTap: () {
        HapticFeedback.selectionClick();
        widget.onTap();
      },
      child: AnimatedScale(
        scale: _down ? 0.96 : 1.0,
        duration: const Duration(milliseconds: 130),
        curve: Curves.easeOut,
        child: widget.child,
      ),
    );
  }
}

/// Kilau putih yang menyapu child secara berkala (hanya di area non-transparan).
class _Shine extends StatelessWidget {
  const _Shine({required this.animation, required this.child, this.phase = 0});

  final Animation<double> animation;
  final Widget child;
  final double phase;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: animation,
      child: child,
      builder: (context, c) {
        final t = (animation.value * 2 + phase) % 1.0;
        final x = -1.6 + 3.6 * t;
        return ShaderMask(
          blendMode: BlendMode.srcATop,
          shaderCallback: (rect) => LinearGradient(
            begin: Alignment(x - 0.6, -0.4),
            end: Alignment(x + 0.6, 0.4),
            colors: [
              Colors.transparent,
              Colors.white.withValues(alpha: 0.55),
              Colors.transparent,
            ],
          ).createShader(rect),
          child: c,
        );
      },
    );
  }
}

// ------------------------------------------------------------------- header

class _Header extends StatelessWidget {
  const _Header({required this.ambient, required this.onSeeAll});

  final Animation<double> ambient;
  final VoidCallback onSeeAll;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 8),
      child: Row(
        children: [
          AnimatedBuilder(
            animation: ambient,
            builder: (context, _) {
              final p = _pulse(ambient.value, 4);
              return Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Color(0xFFFFA000), Color(0xFFFF3D71)],
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFFFF5A36)
                          .withValues(alpha: 0.20 + 0.30 * p),
                      blurRadius: 6 + 8 * p,
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.local_fire_department_rounded,
                  size: 19,
                  color: Colors.white,
                ),
              );
            },
          ),
          const SizedBox(width: 10),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Donghua',
                  style: TextStyle(
                    color: AppColors.textWhite,
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.2,
                    height: 1.1,
                  ),
                ),
                SizedBox(height: 2),
                Text(
                  'Lagi hangat sekarang',
                  style: TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          Material(
            color: AppColors.accentViolet.withValues(alpha: 0.16),
            shape: const StadiumBorder(),
            child: InkWell(
              customBorder: const StadiumBorder(),
              onTap: onSeeAll,
              child: const Padding(
                padding: EdgeInsets.fromLTRB(12, 6, 6, 6),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Lihat semua',
                      style: TextStyle(
                        color: AppColors.accentVioletLight,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Icon(
                      Icons.chevron_right_rounded,
                      size: 18,
                      color: AppColors.accentVioletLight,
                    ),
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

// --------------------------------------------------------------- hero (#1)

class _HeroCard extends StatelessWidget {
  const _HeroCard({required this.card, required this.ambient});

  final AnichinCard card;
  final Animation<double> ambient;

  @override
  Widget build(BuildContext context) {
    final type = cleanMeta(card.type);

    final inner = ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: Stack(
        fit: StackFit.expand,
        children: [
          const ColoredBox(color: AppColors.surfaceDark),
          // Poster full-bleed dengan zoom pelan (Ken Burns).
          AnimatedBuilder(
            animation: ambient,
            child: DonghuaImage(card.thumbnail, alignment: Alignment.topCenter),
            builder: (context, child) => Transform.scale(
              scale: 1.06 + 0.07 * _pulse(ambient.value, 1),
              child: child,
            ),
          ),
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Color(0x40000000),
                  Colors.transparent,
                  Color(0xF2120F1F),
                ],
                stops: [0.0, 0.42, 1.0],
              ),
            ),
          ),
          Positioned(
            top: 0,
            left: 0,
            child: _Shine(
              animation: ambient,
              child: const _RankBadge(rank: 1, color: _gold, big: true),
            ),
          ),
          if (type != null)
            Positioned(top: 10, right: 10, child: _GlassChip(type)),
          Positioned(
            left: 12,
            right: 12,
            bottom: 12,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (card.eps != null) ...[
                        _EpsPill('Eps ${card.eps}'),
                        const SizedBox(height: 7),
                      ],
                      Text(
                        cardTitle(card),
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 15.5,
                          fontWeight: FontWeight.w800,
                          height: 1.2,
                          shadows: [Shadow(color: Colors.black54, blurRadius: 8)],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                _PlayButton(ambient: ambient),
              ],
            ),
          ),
        ],
      ),
    );

    // Border emas->ungu yang berputar + glow emas yang bernapas.
    return AnimatedBuilder(
      animation: ambient,
      child: inner,
      builder: (context, child) {
        final v = ambient.value;
        return DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(22),
            boxShadow: [
              BoxShadow(
                color: _gold.withValues(alpha: 0.10 + 0.14 * _pulse(v, 2)),
                blurRadius: 22,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Container(
            padding: const EdgeInsets.all(1.8),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(22),
              gradient: SweepGradient(
                transform: GradientRotation(v * 2 * math.pi),
                colors: const [
                  _gold,
                  AppColors.accentViolet,
                  Color(0x33FFB300),
                  _gold,
                ],
                stops: const [0.0, 0.35, 0.7, 1.0],
              ),
            ),
            child: child,
          ),
        );
      },
    );
  }
}

class _PlayButton extends StatelessWidget {
  const _PlayButton({required this.ambient});

  final Animation<double> ambient;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 54,
      height: 54,
      child: AnimatedBuilder(
        animation: ambient,
        builder: (context, _) {
          final p = _pulse(ambient.value, 4);
          return Stack(
            alignment: Alignment.center,
            children: [
              // Cincin yang membesar lalu memudar.
              Container(
                width: 38 + 16 * p,
                height: 38 + 16 * p,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _gold.withValues(alpha: 0.28 * (1 - p)),
                ),
              ),
              Container(
                width: 38,
                height: 38,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Color(0xFFFFD866), _gold],
                  ),
                ),
                child: const Icon(Icons.play_arrow_rounded, size: 26, color: _ink),
              ),
            ],
          );
        },
      ),
    );
  }
}

// ------------------------------------------------------------ mini (#2, #3)

class _MiniCard extends StatelessWidget {
  const _MiniCard({
    required this.rank,
    required this.card,
    required this.color,
    required this.ambient,
    required this.phase,
  });

  final int rank;
  final AnichinCard card;
  final Color color;
  final Animation<double> ambient;
  final double phase;

  @override
  Widget build(BuildContext context) {
    final type = cleanMeta(card.type);

    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(19),
        child: Stack(
          fit: StackFit.expand,
          children: [
            const ColoredBox(color: AppColors.surfaceDark),
            AnimatedBuilder(
              animation: ambient,
              child: DonghuaImage(card.thumbnail, alignment: Alignment.topCenter),
              builder: (context, child) => Transform.scale(
                scale: 1.06 + 0.06 * _pulse((ambient.value + phase) % 1.0, 1),
                child: child,
              ),
            ),
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Color(0x33000000),
                    Colors.transparent,
                    Color(0xF2120F1F),
                  ],
                  stops: [0.0, 0.40, 1.0],
                ),
              ),
            ),
            Positioned(
              top: 0,
              left: 0,
              child: _Shine(
                animation: ambient,
                phase: phase,
                child: _RankBadge(rank: rank, color: color),
              ),
            ),
            if (type != null)
              Positioned(top: 8, right: 8, child: _GlassChip(type)),
            Positioned(
              left: 10,
              right: 10,
              bottom: 10,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (card.eps != null) ...[
                    _EpsPill('Eps ${card.eps}', small: true),
                    const SizedBox(height: 5),
                  ],
                  Text(
                    cardTitle(card),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w800,
                      height: 1.2,
                      shadows: [Shadow(color: Colors.black54, blurRadius: 6)],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ----------------------------------------------------------------- bagian kecil

class _RankBadge extends StatelessWidget {
  const _RankBadge({required this.rank, required this.color, this.big = false});

  final int rank;
  final Color color;
  final bool big;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: big ? 12 : 10, vertical: big ? 6 : 5),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color.lerp(color, Colors.white, 0.35)!, color],
        ),
        borderRadius: const BorderRadius.only(bottomRight: Radius.circular(16)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (big) ...[
            const Icon(Icons.local_fire_department_rounded, size: 16, color: _ink),
            const SizedBox(width: 2),
          ],
          Text(
            '#$rank',
            style: TextStyle(
              color: _ink,
              fontSize: big ? 15 : 13,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}

class _EpsPill extends StatelessWidget {
  const _EpsPill(this.text, {this.small = false});

  final String text;
  final bool small;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: small ? 7 : 9, vertical: small ? 3 : 4),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [AppColors.accentViolet, AppColors.accentVioletDark],
        ),
        borderRadius: BorderRadius.circular(small ? 8 : 10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.play_arrow_rounded, size: small ? 12 : 14, color: Colors.white),
          const SizedBox(width: 2),
          Text(
            text,
            style: TextStyle(
              color: Colors.white,
              fontSize: small ? 10.5 : 11.5,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _GlassChip extends StatelessWidget {
  const _GlassChip(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3.5),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
      ),
      child: Text(
        text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 10,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

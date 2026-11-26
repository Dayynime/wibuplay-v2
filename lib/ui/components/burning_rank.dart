import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../redesign/z_kit.dart';

/// Angka peringkat yang "terbakar" saat pertama kali masuk layar:
///  1. garis angka tergambar seperti sapuan kuas (miring, kiri-atas ke
///     kanan-bawah) dengan ujung kuas merah yang menyala;
///  2. merah naik mengisi angka dari bawah;
///  3. garisnya meredup, tinggal angka merah.
/// Diam (langsung jadi) kalau HP diset "hapus animasi".
class BurningRankNumber extends StatefulWidget {
  const BurningRankNumber(
    this.rank, {
    super.key,
    this.size = 40,
    this.outline = AppColors.textMuted,
    this.fill = AppColors.accentViolet,
    this.delayMs = 0,
  });

  final int rank;
  final double size;
  final Color outline;
  final Color fill;
  final int delayMs;

  @override
  State<BurningRankNumber> createState() => _BurningRankNumberState();
}

class _BurningRankNumberState extends State<BurningRankNumber> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1300));
  ScrollPosition? _pos;
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _started = true;
      _c.value = 1;
      return;
    }
    final p = Scrollable.maybeOf(context)?.position;
    if (p != _pos) {
      _pos?.removeListener(_check);
      _pos = p;
      _pos?.addListener(_check);
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => _check());
  }

  void _check() {
    if (_started || !mounted) return;
    final box = context.findRenderObject() as RenderBox?;
    if (box == null || !box.attached || !box.hasSize) return;
    final y = box.localToGlobal(Offset.zero).dy;
    if (y < MediaQuery.sizeOf(context).height * 0.88) {
      _started = true;
      _pos?.removeListener(_check);
      Future.delayed(Duration(milliseconds: widget.delayMs), () {
        if (mounted) _c.forward();
      });
    }
  }

  @override
  void dispose() {
    _pos?.removeListener(_check);
    _c.dispose();
    super.dispose();
  }

  TextStyle _fillStyle() {
    final base = ZFont.display(size: widget.size, height: 1, letterSpacing: -1);
    return base.copyWith(color: widget.fill, fontWeight: FontWeight.w800, height: 1, letterSpacing: -1);
  }

  @override
  Widget build(BuildContext context) {
    final text = '${widget.rank}';
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) {
        final t = _c.value;
        final draw = Curves.easeInOutCubic.transform((t / 0.55).clamp(0.0, 1.0));
        final fill = Curves.easeOutCubic.transform(((t - 0.45) / 0.4).clamp(0.0, 1.0));
        final dim = ((t - 0.8) / 0.2).clamp(0.0, 1.0);
        final outlineColor = Color.lerp(
          Color.lerp(widget.outline, widget.fill, draw < 1 ? 0.6 : 0)!,
          widget.outline.withValues(alpha: 0.35),
          dim,
        )!;
        return Stack(
          alignment: Alignment.center,
          children: [
            // Isi merah naik dari bawah.
            if (fill > 0)
              ClipRect(
                clipper: _FromBottom(fill),
                child: Text(text, style: _fillStyle()),
              ),
            // Garis: disapu kuas diagonal (ujung lembut).
            ShaderMask(
              blendMode: BlendMode.dstIn,
              shaderCallback: (r) => LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: const [Colors.white, Colors.white, Colors.transparent],
                stops: [0, (draw * 1.15 - 0.15).clamp(0.0, 1.0), (draw * 1.15).clamp(0.0, 1.0)],
              ).createShader(r),
              child: ZRankNumber(widget.rank, size: widget.size, color: outlineColor),
            ),
          ],
        );
      },
    );
  }
}

class _FromBottom extends CustomClipper<Rect> {
  const _FromBottom(this.p);

  final double p;

  @override
  Rect getClip(Size s) => Rect.fromLTRB(-4, s.height * (1 - p), s.width + 4, s.height + 4);

  @override
  bool shouldReclip(_FromBottom old) => old.p != p;
}

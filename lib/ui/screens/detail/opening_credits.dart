import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import '../../../core/lite_mode.dart';
import '../../../core/theme/app_colors.dart';
import '../../redesign/z_kit.dart';

/// Satu baris kredit: label Jepang vertikal + label kecil + isi.
class CreditLine {
  const CreditLine(this.jp, this.label, this.value);

  final String jp;
  final String label;
  final String value;
}

/// Kredit ala opening anime di pojok kanan atas hero Detail.
///
/// [anim] 0..1 (dikendalikan halaman Detail):
///  - garis merah tipis tumbuh ke bawah;
///  - tiap baris muncul bergantian dari blur ke tajam;
///  - setelah selesai, kredit tetap tampil (sedikit redup) sebagai info.
class OpeningCredits extends StatelessWidget {
  const OpeningCredits({super.key, required this.lines, required this.anim});

  final List<CreditLine> lines;
  final Animation<double> anim;

  @override
  Widget build(BuildContext context) {
    final lite = LiteMode.enabled;
    return IgnorePointer(
      child: AnimatedBuilder(
        animation: anim,
        builder: (context, _) {
          final t = anim.value;
          final line = Curves.easeOutCubic.transform((t / 0.85).clamp(0.0, 1.0));
          return Stack(
            clipBehavior: Clip.none,
            children: [
              // Garis merah di tepi kanan.
              Positioned(
                right: -9,
                top: -8,
                child: Container(
                  width: 1,
                  height: (lines.length * 46.0) * line,
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [AppColors.accentViolet, Color(0x00E4344A)],
                    ),
                  ),
                ),
              ),
              Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  for (var i = 0; i < lines.length; i++) ...[
                    if (i > 0) const SizedBox(height: 10),
                    _line(lines[i], _part(t, 0.08 + i * 0.18, 0.32), lite, t >= 1),
                  ],
                ],
              ),
            ],
          );
        },
      ),
    );
  }

  static double _part(double t, double a, double d) => Curves.easeOutCubic.transform(((t - a) / d).clamp(0.0, 1.0));

  Widget _line(CreditLine c, double v, bool lite, bool done) {
    if (v <= 0) return const SizedBox(height: 36);
    final jp = ZFont.jp(size: 9.5, color: AppColors.accentVioletLight, letterSpacing: 0);
    Widget body = Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              c.label.toUpperCase(),
              style: const TextStyle(color: Color(0x8CFFFFFF), fontSize: 8, fontWeight: FontWeight.w700, letterSpacing: 3),
            ),
            const SizedBox(height: 2),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 190),
              child: Text(
                c.value.toUpperCase(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.right,
                style: ZFont.display(size: 15, weight: FontWeight.w300, letterSpacing: 3.5).copyWith(
                  shadows: const [Shadow(color: Color(0xB3000000), blurRadius: 8)],
                ),
              ),
            ),
          ],
        ),
        const SizedBox(width: 7),
        // Label Jepang vertikal (satu huruf per baris).
        Column(
          mainAxisSize: MainAxisSize.min,
          children: [for (final ch in c.jp.characters) Text(ch, style: jp.copyWith(height: 1.1))],
        ),
      ],
    );
    final o = (done ? 0.88 : 1.0) * v;
    if (!lite && v < 1) {
      final sigma = 6 * (1 - v);
      body = ImageFiltered(imageFilter: ImageFilter.blur(sigmaX: sigma, sigmaY: sigma), child: body);
    }
    return Opacity(
      opacity: o.clamp(0.0, 1.0),
      child: Transform.translate(offset: Offset(0, 6 * (1 - v)), child: body),
    );
  }
}

/// Pita hitam atas & bawah (letterbox) selama kredit berjalan, lalu membuka.
class CreditLetterbox extends StatelessWidget {
  const CreditLetterbox({super.key, required this.anim, required this.height});

  final Animation<double> anim;

  /// Tinggi area hero (pita bawah ditaruh di dasarnya).
  final double height;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: AnimatedBuilder(
        animation: anim,
        builder: (context, _) {
          // Tertutup penuh sampai 0.78, lalu membuka.
          final open = Curves.easeInOutCubic.transform(((anim.value - 0.78) / 0.22).clamp(0.0, 1.0));
          if (open >= 1) return const SizedBox.shrink();
          const bar = 44.0;
          return Stack(
            children: [
              Positioned(left: 0, right: 0, top: -bar * open, height: bar, child: const ColoredBox(color: Colors.black)),
              Positioned(
                left: 0,
                right: 0,
                top: height - bar,
                height: bar * (1 - open),
                child: const ColoredBox(color: Colors.black),
              ),
            ],
          );
        },
      ),
    );
  }
}

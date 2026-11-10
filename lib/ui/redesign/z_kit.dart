import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/theme/app_colors.dart';

// =============================================================================
// Kit desain Zenime "Samudra" (redesain Nov 2026, sama dengan preview HTML).
//
// Font: Plus Jakarta Sans (teks), Bricolage Grotesque (judul), Noto Sans JP
// (label Jepang). Diambil lewat google_fonts lalu disimpan di HP; selama belum
// terunduh (atau offline di pembukaan pertama) otomatis pakai font bawaan.
// Semua komponen di sini murni tampilan: tidak ada logika/data.
// =============================================================================

class ZFont {
  ZFont._();

  static final Map<String, TextStyle> _cache = {};

  static TextStyle _get(String family, TextStyle base) {
    final key = '$family|${base.fontSize}|${base.fontWeight}|${base.color?.toARGB32()}|'
        '${base.height}|${base.letterSpacing}';
    return _cache.putIfAbsent(key, () {
      try {
        return GoogleFonts.getFont(family, textStyle: base);
      } catch (_) {
        return base; // keluarga font tidak dikenal: pakai bawaan
      }
    });
  }

  /// Judul tebal berkarakter (judul layar, section, hero).
  static TextStyle display({
    double size = 19,
    FontWeight weight = FontWeight.w800,
    Color color = AppColors.textWhite,
    double? height,
    double? letterSpacing,
  }) =>
      _get(
        'Bricolage Grotesque',
        TextStyle(
          fontSize: size,
          fontWeight: weight,
          color: color,
          height: height,
          letterSpacing: letterSpacing ?? -size * 0.018,
        ),
      );

  /// Label Jepang kecil (eyebrow).
  static TextStyle jp({
    double size = 10.5,
    FontWeight weight = FontWeight.w700,
    Color color = AppColors.accentVioletLight,
    double letterSpacing = 2,
  }) =>
      _get(
        'Noto Sans JP',
        TextStyle(fontSize: size, fontWeight: weight, color: color, letterSpacing: letterSpacing, height: 1.25),
      );

  /// Font teks seluruh app (dipasang di ThemeData).
  static TextTheme bodyTheme(TextTheme base) {
    try {
      return GoogleFonts.plusJakartaSansTextTheme(base);
    } catch (_) {
      return base;
    }
  }
}

/// Warna nada chip.
enum ZTone { glass, brand, jade, gold, ghost, scrim }

/// Chip kecil bulat (status, EP, skor, "Baru").
class ZChip extends StatelessWidget {
  const ZChip(this.text, {super.key, this.icon, this.tone = ZTone.glass, this.live = false});

  final String text;
  final IconData? icon;
  final ZTone tone;

  /// Titik kecil di depan (mis. Ongoing / Tayang sekarang).
  final bool live;

  @override
  Widget build(BuildContext context) {
    final (bg, fg, border) = switch (tone) {
      ZTone.brand => (AppColors.accentViolet, Colors.white, null),
      ZTone.jade => (const Color(0x292FD3A2), const Color(0xFF2FD3A2), null),
      ZTone.gold => (const Color(0x29F6BE4F), const Color(0xFFF6BE4F), null),
      ZTone.ghost => (Colors.transparent, AppColors.textWhite, const Color(0x2EFFFFFF)),
      ZTone.scrim => (const Color(0xB806111D), Colors.white, null),
      ZTone.glass => (const Color(0x1FFFFFFF), Colors.white, null),
    };
    return Container(
      height: 22,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
        border: border == null ? null : Border.all(color: border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (live) ...[
            Container(width: 6, height: 6, decoration: BoxDecoration(color: fg, shape: BoxShape.circle)),
            const SizedBox(width: 5),
          ],
          if (icon != null) ...[
            Icon(icon, size: 12, color: tone == ZTone.glass || tone == ZTone.scrim ? const Color(0xFFF6BE4F) : fg),
            const SizedBox(width: 3),
          ],
          Text(
            text,
            maxLines: 1,
            style: TextStyle(color: fg, fontSize: 10.5, fontWeight: FontWeight.w700, letterSpacing: 0.2, height: 1.1),
          ),
        ],
      ),
    );
  }
}

/// Tekstur titik ala screentone manga di pojok kanan atas, memudar ke
/// kiri-bawah. Statis (digambar sekali), jadi murah.
class ZScreentone extends StatelessWidget {
  const ZScreentone({super.key, this.opacity = 0.16, this.spacing = 6});

  final double opacity;
  final double spacing;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: RepaintBoundary(
        child: CustomPaint(painter: _TonePainter(opacity, spacing), size: Size.infinite),
      ),
    );
  }
}

class _TonePainter extends CustomPainter {
  _TonePainter(this.opacity, this.spacing);

  final double opacity;
  final double spacing;

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()..isAntiAlias = true;
    final diag = size.width + size.height;
    for (double y = spacing / 2; y < size.height * 0.62; y += spacing) {
      for (double x = size.width - spacing / 2; x > size.width * 0.38; x -= spacing) {
        // Memudar menjauh dari pojok kanan atas.
        final d = ((size.width - x) + y) / (diag * 0.55);
        final a = opacity * (1 - d).clamp(0.0, 1.0);
        if (a <= 0.01) continue;
        p.color = Color.fromRGBO(255, 255, 255, a);
        canvas.drawCircle(Offset(x, y), 0.9, p);
      }
    }
  }

  @override
  bool shouldRepaint(_TonePainter old) => old.opacity != opacity || old.spacing != spacing;
}

/// Pembungkus "tekan": mengecil 3% saat ditekan (160 ms), seperti preview.
class ZPress extends StatefulWidget {
  const ZPress({super.key, required this.child, this.onTap, this.onLongPress});

  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  @override
  State<ZPress> createState() => _ZPressState();
}

class _ZPressState extends State<ZPress> {
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
      onTap: widget.onTap,
      onLongPress: widget.onLongPress,
      child: AnimatedScale(
        scale: _down ? 0.97 : 1,
        duration: const Duration(milliseconds: 160),
        curve: Curves.easeOutQuint,
        child: widget.child,
      ),
    );
  }
}

/// Angka peringkat besar bergaris (gaya anime).
class ZRankNumber extends StatelessWidget {
  const ZRankNumber(this.rank, {super.key, this.size = 40, this.color = AppColors.textMuted});

  final int rank;
  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final base = ZFont.display(size: size, height: 1, letterSpacing: -1);
    // TextStyle tidak boleh punya color DAN foreground sekaligus.
    return Text(
      '$rank',
      style: TextStyle(
        fontFamily: base.fontFamily,
        fontFamilyFallback: base.fontFamilyFallback,
        fontSize: size,
        fontWeight: FontWeight.w800,
        height: 1,
        letterSpacing: -1,
        foreground: Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5
          ..color = color,
      ),
    );
  }
}

/// Bayangan bawah untuk teks di atas gambar.
const LinearGradient zBottomShade = LinearGradient(
  begin: Alignment.topCenter,
  end: Alignment.bottomCenter,
  stops: [0.3, 1],
  colors: [Color(0x0006111D), Color(0xEB06111D)],
);

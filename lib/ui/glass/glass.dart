import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';

// =============================================================================
// LIQUID GLASS - satu-satunya tempat gaya kaca di app.
//
// Semua layar, card, sheet, app bar, dan bottom bar memakai komponen di file
// ini, jadi tampilannya konsisten dan bisa diubah dari satu tempat (token di
// class [Glass]). Toggle "Liquid Glass" di Pengaturan mematikan semuanya sekaligus
// dan kembali ke tampilan solid lama.
// =============================================================================

/// Token gaya kaca. Ubah angka di sini untuk menyetel seluruh app.
class Glass {
  Glass._();

  /// Kekuatan blur (sigma).
  static const double blurThin = 12;
  static const double blurRegular = 20;
  static const double blurThick = 30;

  /// Warna dasar kaca (navy keabuan, sedikit lebih terang dari latar).
  static const Color tint = Color(0xFF1A2130);

  /// Opasitas isi kaca (makin kecil makin bening).
  static const double fillTop = 0.58;
  static const double fillBottom = 0.44;
}

enum GlassBlur { none, thin, regular, thick }

double _sigmaOf(GlassBlur b) => switch (b) {
      GlassBlur.none => 0,
      GlassBlur.thin => Glass.blurThin,
      GlassBlur.regular => Glass.blurRegular,
      GlassBlur.thick => Glass.blurThick,
    };

// -----------------------------------------------------------------------------
// Setting (toggle "Liquid Glass")
// -----------------------------------------------------------------------------

class GlassSettings extends ChangeNotifier {
  GlassSettings._(this._prefs, this._enabled);

  static const String _key = 'liquid_glass_v1';

  final SharedPreferences _prefs;
  bool _enabled;

  bool get enabled => _enabled;

  static Future<GlassSettings> open() async {
    final prefs = await SharedPreferences.getInstance();
    return GlassSettings._(prefs, prefs.getBool(_key) ?? true);
  }

  Future<void> setEnabled(bool value) async {
    if (value == _enabled) return;
    _enabled = value;
    notifyListeners();
    await _prefs.setBool(_key, value);
  }
}

/// Di-override di main() (sama seperti localStoreProvider).
final glassSettingsProvider = ChangeNotifierProvider<GlassSettings>(
  (ref) => throw UnimplementedError('glassSettingsProvider harus di-override di main()'),
);

// -----------------------------------------------------------------------------
// GlassScope: tandai area "padat" (list/grid panjang) supaya card di dalamnya
// tidak memakai BackdropFilter per item (berat di HP low-end). Di mode padat
// kaca tetap terlihat (gradien + tepi terang) tapi tanpa blur.
// -----------------------------------------------------------------------------

class GlassScope extends InheritedWidget {
  const GlassScope({super.key, required this.dense, required super.child});

  final bool dense;

  static bool denseOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<GlassScope>()?.dense ?? false;

  @override
  bool updateShouldNotify(GlassScope old) => old.dense != dense;
}

// -----------------------------------------------------------------------------
// GlassSurface: permukaan kaca dasar. Semua komponen lain dibangun dari ini.
// -----------------------------------------------------------------------------

class GlassSurface extends ConsumerWidget {
  const GlassSurface({
    super.key,
    required this.child,
    this.borderRadius,
    this.blur = GlassBlur.regular,
    this.padding,
    this.tint,
    this.strength = 1.0,
    this.shadow = false,
    this.solidColor,
  });

  final Widget child;
  final BorderRadius? borderRadius;
  final GlassBlur blur;
  final EdgeInsetsGeometry? padding;

  /// Warna dasar kaca. Default [Glass.tint]. Isi dengan aksen untuk state aktif.
  final Color? tint;

  /// Pengali kecerahan kaca (1.0 normal, >1 lebih pekat).
  final double strength;

  /// Bayangan lembut di luar kaca (untuk elemen melayang: bottom bar, sheet).
  final bool shadow;

  /// Warna saat Liquid Glass dimatikan. Default [AppColors.surfaceCard].
  final Color? solidColor;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final on = ref.watch(glassSettingsProvider.select((s) => s.enabled));
    final radius = borderRadius ?? AppShapes.card;
    final inner = padding == null ? child : Padding(padding: padding!, child: child);

    if (!on) {
      return DecoratedBox(
        decoration: BoxDecoration(
          color: solidColor ?? AppColors.surfaceCard,
          borderRadius: radius,
          border: Border.all(color: AppColors.surfaceElevated.withValues(alpha: 0.6)),
        ),
        child: ClipRRect(borderRadius: radius, child: inner),
      );
    }

    final dense = GlassScope.denseOf(context);
    final sigma = dense ? 0.0 : _sigmaOf(blur);
    final base = tint ?? Glass.tint;
    final top = Color.alphaBlend(
      Colors.white.withValues(alpha: 0.09 * strength),
      base.withValues(alpha: (Glass.fillTop * strength).clamp(0.0, 0.95)),
    );
    final bottom = Color.alphaBlend(
      Colors.white.withValues(alpha: 0.02 * strength),
      base.withValues(alpha: (Glass.fillBottom * strength).clamp(0.0, 0.95)),
    );

    Widget body = DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: radius,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [top, bottom],
        ),
      ),
      child: CustomPaint(
        foregroundPainter: _GlassEdgePainter(radius),
        child: inner,
      ),
    );

    if (sigma > 0) {
      body = ClipRRect(
        borderRadius: radius,
        child: BackdropFilter(
          filter: ui.ImageFilter.blur(sigmaX: sigma, sigmaY: sigma),
          child: body,
        ),
      );
    } else {
      body = ClipRRect(borderRadius: radius, child: body);
    }

    return RepaintBoundary(
      child: CustomPaint(
        painter: shadow ? _OuterShadowPainter(radius) : null,
        child: body,
      ),
    );
  }
}

/// Tepi kaca: garis 1px gradien (terang di kiri atas, redup di tengah, sedikit
/// aksen di kanan bawah) + kilap tipis di tepi atas. Ini yang bikin terasa
/// "liquid", bukan sekadar kotak transparan.
class _GlassEdgePainter extends CustomPainter {
  const _GlassEdgePainter(this.radius);

  final BorderRadius radius;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final rect = Offset.zero & size;
    final rrect = radius.toRRect(rect).deflate(0.5);

    final edge = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          Colors.white.withValues(alpha: 0.34),
          Colors.white.withValues(alpha: 0.07),
          Colors.white.withValues(alpha: 0.03),
          AppColors.accentViolet.withValues(alpha: 0.18),
        ],
        stops: const [0, 0.38, 0.7, 1],
      ).createShader(rect);
    canvas.drawRRect(rrect, edge);

    final inset = radius.topLeft.x * 0.55;
    if (size.width > inset * 2 + 4) {
      final shine = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..shader = LinearGradient(
          colors: [
            Colors.white.withValues(alpha: 0),
            Colors.white.withValues(alpha: 0.38),
            Colors.white.withValues(alpha: 0),
          ],
        ).createShader(Rect.fromLTWH(inset, 0, size.width - inset * 2, 1));
      canvas.drawLine(Offset(inset, 0.5), Offset(size.width - inset, 0.5), shine);
    }
  }

  @override
  bool shouldRepaint(_GlassEdgePainter old) => old.radius != radius;
}

/// Bayangan hanya di LUAR bentuk kaca (kalau dibiarkan tembus ke dalam, isi
/// kaca jadi keruh).
class _OuterShadowPainter extends CustomPainter {
  const _OuterShadowPainter(this.radius);

  final BorderRadius radius;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final rrect = radius.toRRect(Offset.zero & size);
    final outside = Path.combine(
      PathOperation.difference,
      Path()..addRect(rrect.outerRect.inflate(80)),
      Path()..addRRect(rrect),
    );
    canvas.save();
    canvas.clipPath(outside);
    canvas.drawRRect(
      rrect.shift(const Offset(0, 10)),
      Paint()
        ..color = const Color(0x55000000)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 14),
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(_OuterShadowPainter old) => old.radius != radius;
}

// -----------------------------------------------------------------------------
// Backdrop: latar "aurora" statis. Kaca butuh sesuatu di belakangnya untuk
// diburamkan; di atas navy polos efeknya tidak kelihatan.
// -----------------------------------------------------------------------------

class GlassBackdrop extends StatelessWidget {
  const GlassBackdrop({super.key});

  @override
  Widget build(BuildContext context) {
    return const RepaintBoundary(
      child: Stack(
        fit: StackFit.expand,
        children: [
          ColoredBox(color: AppColors.backgroundDark),
          _Glow(Alignment(-1.0, -0.85), 1.0, AppColors.accentViolet, 0.20),
          _Glow(Alignment(1.1, -0.1), 0.9, Color(0xFF3B5BDB), 0.14),
          _Glow(Alignment(-0.6, 1.1), 1.0, Color(0xFF7C3AED), 0.12),
        ],
      ),
    );
  }
}

class _Glow extends StatelessWidget {
  const _Glow(this.center, this.radius, this.color, this.alpha);

  final Alignment center;
  final double radius;
  final Color color;
  final double alpha;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: RadialGradient(
          center: center,
          radius: radius,
          colors: [color.withValues(alpha: alpha), color.withValues(alpha: 0)],
        ),
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// GlassScaffold: pengganti Scaffold (drop-in). Latar aurora + isi transparan.
// -----------------------------------------------------------------------------

class GlassScaffold extends ConsumerWidget {
  const GlassScaffold({
    super.key,
    this.appBar,
    this.body,
    this.floatingActionButton,
    this.backgroundColor,
  });

  final PreferredSizeWidget? appBar;
  final Widget? body;
  final Widget? floatingActionButton;
  final Color? backgroundColor;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final on = ref.watch(glassSettingsProvider.select((s) => s.enabled));
    if (!on) {
      return Scaffold(
        backgroundColor: backgroundColor ?? AppColors.backgroundDark,
        appBar: appBar,
        body: body,
        floatingActionButton: floatingActionButton,
      );
    }
    return Stack(
      fit: StackFit.expand,
      children: [
        const GlassBackdrop(),
        Scaffold(
          backgroundColor: Colors.transparent,
          appBar: appBar,
          body: body,
          floatingActionButton: floatingActionButton,
        ),
      ],
    );
  }
}

// -----------------------------------------------------------------------------
// GlassAppBar: pengganti AppBar (drop-in untuk parameter yang dipakai app).
// -----------------------------------------------------------------------------

class GlassAppBar extends ConsumerWidget implements PreferredSizeWidget {
  const GlassAppBar({
    super.key,
    this.leading,
    this.title,
    this.actions,
    this.centerTitle,
    this.titleSpacing,
    this.foregroundColor,
    this.backgroundColor,
    this.surfaceTintColor,
    this.elevation,
    this.scrolledUnderElevation,
    this.bottom,
    this.automaticallyImplyLeading = true,
    this.toolbarHeight,
  });

  final Widget? leading;
  final Widget? title;
  final List<Widget>? actions;
  final bool? centerTitle;
  final double? titleSpacing;
  final Color? foregroundColor;
  final Color? backgroundColor;
  final Color? surfaceTintColor;
  final double? elevation;
  final double? scrolledUnderElevation;
  final PreferredSizeWidget? bottom;
  final bool automaticallyImplyLeading;
  final double? toolbarHeight;

  @override
  Size get preferredSize => Size.fromHeight(
        (toolbarHeight ?? kToolbarHeight) + (bottom?.preferredSize.height ?? 0),
      );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final on = ref.watch(glassSettingsProvider.select((s) => s.enabled));
    final bar = AppBar(
      leading: leading,
      title: title,
      actions: actions,
      centerTitle: centerTitle,
      titleSpacing: titleSpacing,
      foregroundColor: foregroundColor,
      backgroundColor: on ? Colors.transparent : (backgroundColor ?? AppColors.backgroundDark),
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      bottom: bottom,
      automaticallyImplyLeading: automaticallyImplyLeading,
      toolbarHeight: toolbarHeight,
    );
    if (!on) return bar;

    return ClipRect(
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: Glass.blurRegular, sigmaY: Glass.blurRegular),
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Glass.tint.withValues(alpha: 0.66),
                Glass.tint.withValues(alpha: 0.40),
              ],
            ),
            border: Border(
              bottom: BorderSide(color: Colors.white.withValues(alpha: 0.09)),
            ),
          ),
          child: bar,
        ),
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// GlassCard: card kaca dengan efek tekan (mengecil 0.97, membal balik).
// -----------------------------------------------------------------------------

class GlassCard extends StatefulWidget {
  const GlassCard({
    super.key,
    required this.child,
    this.onTap,
    this.onLongPress,
    this.padding = const EdgeInsets.all(14),
    this.borderRadius,
    this.blur = GlassBlur.thin,
    this.tint,
  });

  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final EdgeInsetsGeometry padding;
  final BorderRadius? borderRadius;
  final GlassBlur blur;
  final Color? tint;

  @override
  State<GlassCard> createState() => _GlassCardState();
}

class _GlassCardState extends State<GlassCard> {
  bool _down = false;

  void _set(bool v) {
    if (widget.onTap == null && widget.onLongPress == null) return;
    if (_down != v) setState(() => _down = v);
  }

  @override
  Widget build(BuildContext context) {
    final surface = GlassSurface(
      borderRadius: widget.borderRadius ?? AppShapes.card,
      blur: widget.blur,
      tint: widget.tint,
      padding: widget.padding,
      child: widget.child,
    );
    if (widget.onTap == null && widget.onLongPress == null) return surface;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => _set(true),
      onTapUp: (_) => _set(false),
      onTapCancel: () => _set(false),
      onTap: widget.onTap,
      onLongPress: widget.onLongPress,
      child: AnimatedScale(
        scale: _down ? 0.97 : 1.0,
        duration: const Duration(milliseconds: 140),
        curve: Curves.easeOutBack,
        child: surface,
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// GlassIconButton & GlassChip: tombol bulat / chip kaca (mis. tombol kembali di
// atas poster, filter genre).
// -----------------------------------------------------------------------------

class GlassIconButton extends StatelessWidget {
  const GlassIconButton({
    super.key,
    required this.icon,
    required this.onTap,
    this.size = 40,
    this.iconSize = 20,
    this.tooltip,
  });

  final IconData icon;
  final VoidCallback onTap;
  final double size;
  final double iconSize;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final button = GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: SizedBox(
        width: size,
        height: size,
        child: GlassSurface(
          borderRadius: BorderRadius.circular(size / 2),
          blur: GlassBlur.thin,
          child: Center(child: Icon(icon, size: iconSize, color: AppColors.textWhite)),
        ),
      ),
    );
    return tooltip == null ? button : Tooltip(message: tooltip!, child: button);
  }
}

class GlassChip extends StatelessWidget {
  const GlassChip({
    super.key,
    required this.label,
    this.selected = false,
    this.onTap,
    this.icon,
  });

  final String label;
  final bool selected;
  final VoidCallback? onTap;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final color = selected ? AppColors.accentViolet : AppColors.textSecondary;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: GlassSurface(
        borderRadius: AppShapes.pill,
        blur: GlassBlur.thin,
        tint: selected ? AppColors.accentViolet : null,
        strength: selected ? 0.6 : 1.0,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 15, color: color),
              const SizedBox(width: 6),
            ],
            Text(
              label,
              style: TextStyle(
                color: selected ? AppColors.textWhite : color,
                fontSize: 12.5,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// Bottom sheet kaca. Drop-in untuk showModalBottomSheet: parameter
// backgroundColor/shape dipakai hanya untuk membaca radius sudut atas.
// -----------------------------------------------------------------------------

Future<T?> showGlassSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  Color? backgroundColor,
  ShapeBorder? shape,
  BoxConstraints? constraints,
  bool isScrollControlled = false,
  bool useSafeArea = false,
  bool useRootNavigator = false,
  bool showDragHandle = false,
  bool isDismissible = true,
  bool enableDrag = true,
  Color? barrierColor,
}) {
  var radius = 28.0;
  if (shape is RoundedRectangleBorder) {
    final br = shape.borderRadius;
    if (br is BorderRadius) radius = br.topLeft.x;
  }
  return showModalBottomSheet<T>(
    context: context,
    useRootNavigator: useRootNavigator,
    isScrollControlled: isScrollControlled,
    useSafeArea: useSafeArea,
    constraints: constraints,
    isDismissible: isDismissible,
    enableDrag: enableDrag,
    backgroundColor: Colors.transparent,
    elevation: 0,
    barrierColor: barrierColor ?? Colors.black.withValues(alpha: 0.45),
    builder: (ctx) => _GlassSheetFrame(
      radius: radius,
      showDragHandle: showDragHandle,
      solidColor: backgroundColor,
      child: builder(ctx),
    ),
  );
}

class _GlassSheetFrame extends StatelessWidget {
  const _GlassSheetFrame({
    required this.radius,
    required this.showDragHandle,
    required this.child,
    this.solidColor,
  });

  final double radius;
  final bool showDragHandle;
  final Widget child;
  final Color? solidColor;

  @override
  Widget build(BuildContext context) {
    final content = showDragHandle
        ? Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 38,
                height: 4,
                margin: const EdgeInsets.only(top: 10, bottom: 6),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.28),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Flexible(child: child),
            ],
          )
        : child;
    return GlassSurface(
      borderRadius: BorderRadius.vertical(top: Radius.circular(radius)),
      blur: GlassBlur.thick,
      strength: 1.2,
      solidColor: solidColor ?? AppColors.surfaceDark,
      child: content,
    );
  }
}

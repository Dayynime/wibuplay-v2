import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../core/image_cache.dart';
import '../../core/theme/app_colors.dart';
import 'net_image.dart';

/// Warna dominan sebuah poster, dipakai untuk latar Beranda & Detail yang
/// "ikut warna poster".
///
/// Gambar diambil dari cache gambar yang sama dengan NetImage (jadi biasanya
/// tidak download ulang), diperkecil ke 24 px, lalu dirata-rata dengan bobot
/// saturasi (piksel abu-abu/hitam/putih hampir tidak dihitung). Hasilnya
/// diredam ke kecerahan gelap supaya teks putih tetap terbaca.
class PosterTint {
  PosterTint._();

  static final Map<String, Color> _cache = {};
  static final Map<String, Future<Color?>> _pending = {};

  static Color? cached(String url) => _cache[url];

  static Future<Color?> of(String url) {
    if (url.isEmpty) return Future.value(null);
    final hit = _cache[url];
    if (hit != null) return Future.value(hit);
    return _pending[url] ??= _compute(url).whenComplete(() => _pending.remove(url));
  }

  static Future<Color?> _compute(String url) async {
    try {
      final provider = ResizeImage(
        CachedNetworkImageProvider(url, cacheManager: AppImageCache.images, headers: netImageHeaders),
        width: 24,
        allowUpscaling: false,
      );
      final info = await _resolve(provider);
      if (info == null) return null;
      final data = await info.image.toByteData(format: ui.ImageByteFormat.rawRgba);
      info.dispose();
      if (data == null) return null;

      double r = 0, g = 0, b = 0, wSum = 0;
      final bytes = data.buffer.asUint8List();
      for (var i = 0; i + 3 < bytes.length; i += 4) {
        final pr = bytes[i] / 255, pg = bytes[i + 1] / 255, pb = bytes[i + 2] / 255;
        final mx = math.max(pr, math.max(pg, pb)), mn = math.min(pr, math.min(pg, pb));
        final sat = mx == 0 ? 0.0 : (mx - mn) / mx;
        // Piksel hampir hitam/putih atau abu-abu nyaris tidak dihitung.
        final w = 0.03 + sat * sat * (mx > 0.12 ? 1 : 0.1);
        r += pr * w;
        g += pg * w;
        b += pb * w;
        wSum += w;
      }
      if (wSum == 0) return null;
      final avg = Color.fromARGB(255, (r / wSum * 255).round(), (g / wSum * 255).round(), (b / wSum * 255).round());
      final hsl = HSLColor.fromColor(avg);
      final tuned = hsl
          .withSaturation(hsl.saturation.clamp(0.30, 0.72))
          .withLightness(0.30)
          .toColor();
      _cache[url] = tuned;
      return tuned;
    } catch (_) {
      return null; // gambar gagal dimuat: latar tetap polos
    }
  }

  static Future<ImageInfo?> _resolve(ImageProvider provider) {
    final c = Completer<ImageInfo?>();
    final stream = provider.resolve(ImageConfiguration.empty);
    late final ImageStreamListener l;
    l = ImageStreamListener(
      (info, _) {
        stream.removeListener(l);
        if (!c.isCompleted) c.complete(info);
      },
      onError: (_, __) {
        stream.removeListener(l);
        if (!c.isCompleted) c.complete(null);
      },
    );
    stream.addListener(l);
    return c.future.timeout(const Duration(seconds: 8), onTimeout: () {
      stream.removeListener(l);
      return null;
    });
  }
}

/// Cahaya warna poster di bagian atas layar: gradasi dari warna poster ke
/// latar gelap. Warna berganti halus (900 ms) saat [url] berubah; [url] null
/// = memudar ke polos.
class PosterGlow extends StatefulWidget {
  const PosterGlow({super.key, required this.url, this.height = 560, this.strength = 1});

  final String? url;
  final double height;

  /// 0..1, pengali kepekatan (dipakai untuk memudarkan saat di-scroll).
  final double strength;

  @override
  State<PosterGlow> createState() => _PosterGlowState();
}

class _PosterGlowState extends State<PosterGlow> {
  Color? _color;
  int _req = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(PosterGlow old) {
    super.didUpdateWidget(old);
    if (old.url != widget.url) _load();
  }

  void _load() {
    final url = widget.url;
    final id = ++_req;
    if (url == null || url.isEmpty) {
      _color = null; // dipanggil dari initState/didUpdateWidget: build menyusul
      return;
    }
    final hit = PosterTint.cached(url);
    if (hit != null) {
      _color = hit;
      return;
    }
    PosterTint.of(url).then((c) {
      if (!mounted || id != _req || c == null) return;
      setState(() => _color = c);
    });
  }

  @override
  Widget build(BuildContext context) {
    final target = _color ?? AppColors.backgroundDark;
    return IgnorePointer(
      child: SizedBox(
        height: widget.height,
        width: double.infinity,
        child: TweenAnimationBuilder<Color?>(
          tween: ColorTween(end: target),
          duration: const Duration(milliseconds: 900),
          curve: Curves.easeOutCubic,
          builder: (context, c, _) {
            final col = c ?? target;
            final s = widget.strength.clamp(0.0, 1.0);
            return DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  stops: const [0, 0.45, 1],
                  colors: [
                    col.withValues(alpha: 0.85 * s),
                    col.withValues(alpha: 0.35 * s),
                    col.withValues(alpha: 0),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

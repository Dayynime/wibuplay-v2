import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../core/constants.dart';
import '../../core/theme/app_colors.dart';
import 'shimmer.dart';

/// Header yang sama dengan request API (Referer + User-Agent browser).
/// Banyak CDN menolak User-Agent bawaan Dart.
const Map<String, String> _imageHeaders = {
  'Referer': Constants.referer,
  'User-Agent': Constants.userAgent,
  'Accept': 'image/webp,image/png,image/jpeg,image/*;q=0.8,*/*;q=0.5',
};

/// Dipakai juga buat preload gambar (mis. hero banner).
const Map<String, String> netImageHeaders = _imageHeaders;

/// Gambar jaringan dengan cache. Pakai di tempat yang ukurannya sudah pasti
/// (Positioned.fill / SizedBox / AspectRatio). URL kosong -> area kosong.
/// Saat memuat tampil shimmer; kalau gagal tampil ikon + sisa pesan error
/// supaya penyebabnya kelihatan.
class NetImage extends StatelessWidget {
  const NetImage(
    this.url, {
    super.key,
    this.fit = BoxFit.cover,
    this.alignment = Alignment.center,
  });

  final String url;
  final BoxFit fit;
  final Alignment alignment;

  @override
  Widget build(BuildContext context) {
    if (url.isEmpty) return const SizedBox.expand();
    return CachedNetworkImage(
      imageUrl: url,
      httpHeaders: _imageHeaders,
      fit: fit,
      alignment: alignment,
      fadeInDuration: const Duration(milliseconds: 200),
      fadeOutDuration: Duration.zero,
      placeholder: (context, url) => const SizedBox.expand(
        child: ShimmerBox(borderRadius: BorderRadius.zero),
      ),
      errorWidget: (context, url, error) => const ClipRect(
        child: ColoredBox(
          color: AppColors.surfaceCard,
          child: Center(
            child: Icon(Icons.broken_image_outlined,
                size: 20, color: AppColors.textMuted),
          ),
        ),
      ),
    );
  }
}

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../core/constants.dart';

/// Gambar jaringan dengan cache. Pakai di tempat yang ukurannya sudah pasti
/// (Positioned.fill / SizedBox / AspectRatio). URL kosong -> area kosong.
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
      // Server gambar memblokir request tanpa Referer (hotlink protection).
      // Di versi Kotlin header ini ditambahkan HeaderInterceptor milik OkHttp/Coil.
      httpHeaders: const {
        'Referer': Constants.referer,
        'User-Agent': Constants.userAgent,
      },
      fit: fit,
      alignment: alignment,
      fadeInDuration: const Duration(milliseconds: 200),
      fadeOutDuration: Duration.zero,
      errorWidget: (context, url, error) {
        debugPrint('NetImage gagal: $url -> $error');
        return const SizedBox.expand();
      },
    );
  }
}

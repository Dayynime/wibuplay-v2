import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

/// Gambar jaringan dengan cache. Pakai di tempat yang ukurannya sudah pasti
/// (Positioned.fill / SizedBox / AspectRatio). URL kosong -> area kosong.
class NetImage extends StatelessWidget {
  const NetImage(this.url, {super.key, this.fit = BoxFit.cover});

  final String url;
  final BoxFit fit;

  @override
  Widget build(BuildContext context) {
    if (url.isEmpty) return const SizedBox.expand();
    return CachedNetworkImage(
      imageUrl: url,
      fit: fit,
      fadeInDuration: const Duration(milliseconds: 200),
      fadeOutDuration: Duration.zero,
      errorWidget: (context, url, error) => const SizedBox.expand(),
    );
  }
}

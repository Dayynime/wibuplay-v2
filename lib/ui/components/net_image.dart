import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../core/constants.dart';
import '../../core/theme/app_colors.dart';
import '../../data/api/anichin_network.dart';
import 'shimmer.dart';

/// Header yang sama dengan request API (Referer + User-Agent browser).
/// Banyak CDN menolak User-Agent bawaan Dart.
/// Getter (bukan const) supaya Referer selalu ikut nilai Remote Config terbaru.
/// Dipakai juga buat preload gambar (mis. hero banner).
Map<String, String> get netImageHeaders => {
      if (Constants.referer case final r?) 'Referer': r,
      'User-Agent': Constants.userAgent,
      'Accept': 'image/webp,image/png,image/jpeg,image/*;q=0.8,*/*;q=0.5',
    };

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

  /// Poster donghua (riwayat / download) disimpan sebagai URL situs Anichin
  /// dan butuh Referer situs itu, bukan Referer API anime.
  static Map<String, String> _headersFor(String url) {
    final host = Uri.tryParse(url)?.host ?? '';
    final anichinHost = Uri.tryParse(AnichinNetwork.sourceBase)?.host ?? '';
    if (host.isNotEmpty && (host == anichinHost || host.contains('anichin'))) {
      return AnichinNetwork.imageHeaders;
    }
    return netImageHeaders;
  }

  @override
  Widget build(BuildContext context) {
    if (url.isEmpty) return const SizedBox.expand();
    return CachedNetworkImage(
      imageUrl: url,
      httpHeaders: _headersFor(url),
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

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../data/api/anichin_network.dart';
import '../../../data/models/anichin_models.dart';
import '../../components/shimmer.dart';

/// Gambar dari situs sumber donghua. Butuh User-Agent + Referer, kalau tidak
/// sering diblok. Pakai di tempat yang ukurannya sudah pasti.
class DonghuaImage extends StatelessWidget {
  const DonghuaImage(
    this.path, {
    super.key,
    this.fit = BoxFit.cover,
    this.alignment = Alignment.center,
  });

  final String? path;
  final BoxFit fit;
  final Alignment alignment;

  @override
  Widget build(BuildContext context) {
    final url = AnichinNetwork.imageUrl(path);
    if (url == null) return const SizedBox.expand();
    return CachedNetworkImage(
      imageUrl: url,
      httpHeaders: AnichinNetwork.imageHeaders,
      fit: fit,
      alignment: alignment,
      fadeInDuration: const Duration(milliseconds: 200),
      fadeOutDuration: Duration.zero,
      placeholder: (_, __) => const SizedBox.expand(
        child: ShimmerBox(borderRadius: BorderRadius.zero),
      ),
      errorWidget: (_, __, ___) => const ColoredBox(
        color: AppColors.surfaceCard,
        child: Center(
          child: Icon(Icons.broken_image_outlined, color: AppColors.textMuted),
        ),
      ),
    );
  }
}

/// "Unknown" dari scraper dianggap kosong.
String? cleanMeta(String? v) {
  final t = v?.trim();
  if (t == null || t.isEmpty || t == 'Unknown') return null;
  return t;
}

String cardTitle(AnichinCard c) {
  final t = (c.title ?? '').trim().isNotEmpty ? c.title! : (c.headline ?? '');
  return t.trim().isEmpty ? 'Tanpa Judul' : t;
}

// "rilisan_terbaru" -> "Rilisan Terbaru"
String prettySectionName(String? raw) {
  final words = (raw ?? '')
      .replaceAll('_', ' ')
      .trim()
      .split(' ')
      .where((w) => w.isNotEmpty)
      .map((w) => w[0].toUpperCase() + w.substring(1))
      .toList();
  return words.isEmpty ? 'Donghua' : words.join(' ');
}

/// Chip kecil di atas poster (tipe / nomor episode).
class OverlayChip extends StatelessWidget {
  const OverlayChip(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.62),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 10,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

/// Kartu poster donghua (2:3) + judul. Lebar ditentukan parent.
class DonghuaCard extends StatelessWidget {
  const DonghuaCard({super.key, required this.card, required this.onTap});

  final AnichinCard card;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    // Badge tipe cuma untuk yang bukan "Donghua" (mis. Movie), sisanya noise.
    final type = cleanMeta(card.type);
    final showType = type != null && type.toLowerCase() != 'donghua';
    final badge = card.eps != null ? 'Ep ${card.eps}' : cleanMeta(card.status);

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AspectRatio(
            aspectRatio: 2 / 3,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  const ColoredBox(color: AppColors.surfaceDark),
                  DonghuaImage(card.thumbnail),
                  if (showType)
                    Positioned(top: 6, left: 6, child: OverlayChip(type)),
                  if (badge != null)
                    Positioned(bottom: 6, left: 6, child: OverlayChip(badge)),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            cardTitle(card),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.92),
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              height: 17 / 12.5,
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------- episode

final RegExp _numberRegex = RegExp(r'\d+(?:[.,]\d+)?');
// cocok "episode" maupun typo "epsiode" yang ada di beberapa slug/judul situs sumber
final RegExp _episodeInText = RegExp(r'ep[a-z]*sode\s*(\d+(?:[.,]\d+)?)', caseSensitive: false);

/// Nomor episode: dari field `episode` kalau ada, kalau tidak diambil dari judul.
String? episodeLabelOrNull(AnichinEpisodeRef ep) {
  final fromField = ep.episode == null ? null : _numberRegex.firstMatch(ep.episode!)?.group(0);
  if (fromField != null) return fromField;
  return _episodeInText.firstMatch(ep.subtitle ?? ep.name ?? '')?.group(1);
}

/// Episode buat tombol play. API memberi urutan terbaru dulu, jadi ambil yang
/// nomornya paling kecil; kalau ada nomor yang tidak terbaca, ambil item terakhir.
AnichinEpisodeRef? startEpisodeOf(List<AnichinEpisodeRef> episodes) {
  if (episodes.isEmpty) return null;
  final numbered = <(AnichinEpisodeRef, double)>[];
  for (final ep in episodes) {
    final n = double.tryParse((episodeLabelOrNull(ep) ?? '').replaceAll(',', '.'));
    if (n != null) numbered.add((ep, n));
  }
  if (numbered.length == episodes.length) {
    return numbered.reduce((a, b) => b.$2 < a.$2 ? b : a).$1;
  }
  return episodes.last;
}

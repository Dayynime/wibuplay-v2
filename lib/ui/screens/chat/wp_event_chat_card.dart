import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../data/models/chat_models.dart';
import '../../../data/models/wallpaper_models.dart';
import '../../../providers.dart';
import '../../app_routes.dart' show fadeRoute;
import '../wallpaper/wallpaper_screen.dart';

/// Preview wallpaper Limited milik satu event, diambil dari pool Spin.
/// Pool cuma berisi item event selama event masih berjalan, jadi kartu event
/// yang sudah selesai otomatis balik ke tampilan biasa (tanpa gambar).
/// Disimpan per event (bukan autoDispose) supaya scroll chat tidak memicu
/// request berulang.
final wpEventPreviewProvider = FutureProvider.family<List<String>, int>((ref, eventId) async {
  final s = await ref.watch(wallpaperRepositoryProvider).getState();
  return s.pool.where((w) => w.eventId == eventId).map((w) => w.previewUrl).toList();
});

/// Kartu pengumuman Event Limited di chat global (dikirim server saat event
/// mulai / selesai). Tampil di tengah, tanpa avatar, tidak bisa dibalas.
/// Saat event berjalan, latar kartu memakai preview wallpaper Limited event.
class WpEventChatCard extends ConsumerWidget {
  const WpEventChatCard({super.key, required this.message});

  final ChatMessage message;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ended = message.isWpEventEnd;
    final eventId = message.wpEventId;
    final previews = (!ended && eventId != null)
        ? (ref.watch(wpEventPreviewProvider(eventId)).valueOrNull ?? const <String>[])
        : const <String>[];
    final hasImage = previews.isNotEmpty;

    const ink = Color(0xFF1C2230);
    // Di atas gambar teks dibuat putih (ada lapisan gelap), di atas
    // gradient perak tetap gelap seperti sebelumnya.
    final fg = ended || hasImage ? AppColors.textWhite : ink;
    final fgSoft = ended
        ? AppColors.textSecondary
        : hasImage
            ? Colors.white.withValues(alpha: 0.85)
            : ink;
    final time = message.time;
    String two(int v) => v.toString().padLeft(2, '0');

    final content = Padding(
      padding: EdgeInsets.fromLTRB(14, 12, 14, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(ended ? Icons.flag_rounded : Icons.auto_awesome, size: 16, color: fgSoft),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  ended ? 'EVENT LIMITED SELESAI' : 'EVENT LIMITED DIMULAI',
                  style: TextStyle(
                    color: fgSoft,
                    fontSize: 11,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.6,
                    shadows: hasImage ? const [Shadow(color: Colors.black54, blurRadius: 6)] : null,
                  ),
                ),
              ),
              if (time != null)
                Text(
                  '${two(time.hour)}:${two(time.minute)}',
                  style: TextStyle(
                    color: ended ? AppColors.textMuted : fgSoft.withValues(alpha: 0.7),
                    fontSize: 10,
                  ),
                ),
            ],
          ),
          SizedBox(height: hasImage ? 70 : 6),
          Text(
            message.message,
            style: TextStyle(
              color: fg,
              fontSize: 13.5,
              height: 1.35,
              fontWeight: FontWeight.w600,
              shadows: hasImage ? const [Shadow(color: Colors.black87, blurRadius: 8)] : null,
            ),
          ),
          if (!ended) ...[
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: hasImage ? Colors.white : ink,
                  foregroundColor: hasImage ? ink : Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  padding: const EdgeInsets.symmetric(vertical: 10),
                ),
                onPressed: () => Navigator.of(context).push<void>(fadeRoute(const WallpaperScreen())),
                icon: const Icon(Icons.casino_outlined, size: 18),
                label: const Text('Spin sekarang', style: TextStyle(fontWeight: FontWeight.w800)),
              ),
            ),
          ],
        ],
      ),
    );

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              gradient: ended
                  ? const LinearGradient(colors: [AppColors.surfaceVariantDark, AppColors.surfaceElevated])
                  : WallpaperRarity.limited.gradient,
              border: Border.all(
                color: ended ? const Color(0x22FFFFFF) : const Color(0xCCFFFFFF),
                width: hasImage ? 1.5 : 1,
              ),
              boxShadow: ended ? null : const [BoxShadow(color: Color(0x44E8ECF2), blurRadius: 16)],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(17),
              child: hasImage
                  ? Stack(
                      children: [
                        Positioned.fill(child: _PreviewBackground(urls: previews)),
                        // Gelapkan bawah (teks + tombol) dan sedikit atas (judul).
                        const Positioned.fill(
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                colors: [Color(0x99000000), Color(0x22000000), Color(0xCC0B0E14)],
                                stops: [0, 0.35, 0.8],
                              ),
                            ),
                          ),
                        ),
                        content,
                      ],
                    )
                  : content,
            ),
          ),
        ),
      ),
    );
  }
}

/// 1 wallpaper = satu gambar penuh. Lebih dari 1 = dibagi berdampingan
/// (maks 3) supaya semua hadiah event kelihatan.
class _PreviewBackground extends StatelessWidget {
  const _PreviewBackground({required this.urls});

  final List<String> urls;

  @override
  Widget build(BuildContext context) {
    Widget img(String u) => CachedNetworkImage(
          imageUrl: u,
          fit: BoxFit.cover,
          alignment: Alignment.topCenter,
          fadeInDuration: const Duration(milliseconds: 250),
          errorWidget: (_, __, ___) => const SizedBox.shrink(),
        );
    final shown = urls.take(3).toList();
    if (shown.length == 1) return img(shown.first);
    return Row(
      children: [
        for (var i = 0; i < shown.length; i++) ...[
          if (i > 0) const SizedBox(width: 1.5),
          Expanded(child: img(shown[i])),
        ],
      ],
    );
  }
}

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../data/local/entities.dart';
import '../../../providers.dart';
import '../../components/net_image.dart';
import 'download_actions.dart';

String _formatSize(int bytes) {
  final mb = bytes / (1024.0 * 1024.0);
  return mb >= 1024 ? '${(mb / 1024.0).toStringAsFixed(1)} GB' : '${mb.toStringAsFixed(0)} MB';
}

/// Tampilan Beranda saat gagal memuat (biasanya offline) DAN ada video yang
/// sudah didownload: pesan error + "Coba Lagi" kecil, lalu daftar video
/// download bergaya feed YouTube yang bisa langsung diputar. Port fallback
/// download di HomeScreen Zenime. Memutar file offline tidak butuh Premium.
class OfflineDownloadsView extends ConsumerWidget {
  const OfflineDownloadsView({
    super.key,
    required this.message,
    required this.onRetry,
    required this.onPlay,
  });

  final String message;
  final VoidCallback onRetry;
  final void Function(String movieId, String episodeId) onPlay;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final downloads = ref.watch(localStoreProvider.select((s) => s.downloads));
    return SafeArea(
      bottom: false,
      child: ListView(
        // Ruang untuk bottom bar melayang.
        padding: const EdgeInsets.only(top: 24, bottom: 135),
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Column(
              children: [
                Text(
                  message,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
                ),
                const SizedBox(height: 4),
                InkWell(
                  onTap: onRetry,
                  borderRadius: BorderRadius.circular(6),
                  child: const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    child: Text(
                      'Coba Lagi',
                      style: TextStyle(
                        color: AppColors.accentViolet,
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
              ],
            ),
          ),
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Text(
              'Video yang sudah didownload',
              style: TextStyle(
                color: AppColors.textWhite,
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          for (final d in downloads)
            Padding(
              key: ValueKey(d.episodeId),
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 14),
              child: _FeedDownloadCard(
                item: d,
                onTap: () => onPlay(d.animeId, d.episodeId),
                onDelete: () async {
                  final label = d.animeTitle.isEmpty ? null : d.animeTitle;
                  if (await confirmDeleteDownload(context, label: label) && context.mounted) {
                    await ref.read(episodeDownloadManagerProvider).deleteDownload(d.episodeId);
                  }
                },
              ),
            ),
        ],
      ),
    );
  }
}

/// Kartu video download gaya feed YouTube: thumbnail 16:9 penuh, chip
/// "TERSIMPAN" kiri atas, "EP n" kanan bawah, lalu avatar bulat + judul +
/// baris meta + menu hapus.
class _FeedDownloadCard extends StatelessWidget {
  const _FeedDownloadCard({
    required this.item,
    required this.onTap,
    required this.onDelete,
  });

  final DownloadedEpisodeEntity item;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  Widget _chip(String text) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
        decoration: BoxDecoration(
          color: const Color(0xBF000000),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(
          text,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 10,
            fontWeight: FontWeight.w700,
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final path = item.localFilePath;
    final fileOk =
        item.isCompleted && path != null && path.isNotEmpty && File(path).existsSync();
    final thumb = (item.episodeThumbnailUrl ?? '').isNotEmpty
        ? item.episodeThumbnailUrl!
        : (item.posterUrl ?? '');

    final title = (item.episodeTitle ?? '').isNotEmpty
        ? '${item.animeTitle} - ${item.episodeTitle}'
        : '${item.animeTitle} - Episode ${item.episodeIndex ?? ''}'.trim();

    final String meta;
    var metaColor = AppColors.textMuted;
    if (item.isCompleted) {
      if (fileOk) {
        meta = item.totalBytes > 0
            ? 'Siap ditonton offline • ${_formatSize(item.totalBytes)}'
            : 'Siap ditonton offline';
      } else {
        meta = 'File tidak ditemukan di perangkat';
        metaColor = const Color(0xFFE57373);
      }
    } else if (item.status == 'FAILED') {
      meta = 'Download gagal';
      metaColor = const Color(0xFFE57373);
    } else {
      meta = 'Mendownload...';
    }

    return InkWell(
      onTap: fileOk ? onTap : null,
      borderRadius: BorderRadius.circular(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AspectRatio(
            aspectRatio: 16 / 9,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  const ColoredBox(color: AppColors.surfaceVariantDark),
                  if (thumb.isNotEmpty) NetImage(thumb),
                  Positioned(top: 8, left: 8, child: _chip('TERSIMPAN')),
                  if ((item.episodeIndex ?? '').isNotEmpty)
                    Positioned(
                      right: 6,
                      bottom: 6,
                      child: _chip('EP ${item.episodeIndex}'),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Avatar bulat: pakai thumbnail episode (yang sudah ter-cache saat
              // ditonton), ikon film jadi fallback kalau gagal dimuat.
              Container(
                width: 36,
                height: 36,
                clipBehavior: Clip.antiAlias,
                decoration: const BoxDecoration(
                  color: AppColors.surfaceVariantDark,
                  shape: BoxShape.circle,
                ),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    const Center(
                      child: Icon(Icons.movie_outlined, size: 18, color: AppColors.textMuted),
                    ),
                    if (thumb.isNotEmpty) NetImage(thumb),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppColors.textWhite,
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      item.animeTitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: AppColors.textMuted, fontSize: 12),
                    ),
                    Text(
                      meta,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: metaColor, fontSize: 12),
                    ),
                  ],
                ),
              ),
              PopupMenuButton<int>(
                tooltip: 'Opsi lainnya',
                padding: EdgeInsets.zero,
                color: AppColors.surfaceCard,
                icon: const Icon(Icons.more_vert, color: AppColors.textMuted, size: 20),
                onSelected: (_) => onDelete(),
                itemBuilder: (_) => const [
                  PopupMenuItem<int>(
                    value: 0,
                    child: Row(
                      children: [
                        Icon(Icons.delete_outline, size: 18, color: AppColors.textWhite),
                        SizedBox(width: 10),
                        Text('Hapus dari download',
                            style: TextStyle(color: AppColors.textWhite)),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }
}

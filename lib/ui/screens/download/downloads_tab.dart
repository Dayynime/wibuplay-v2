import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../data/local/entities.dart';
import '../../../providers.dart';
import '../../components/net_image.dart';
import '../profile/profile_screen.dart';
import 'download_actions.dart';

String _formatBytes(int b) {
  if (b <= 0) return '0 MB';
  const mb = 1024 * 1024;
  if (b >= 1024 * mb) return '${(b / (1024 * mb)).toStringAsFixed(1)} GB';
  return '${(b / mb).toStringAsFixed(b >= 100 * mb ? 0 : 1)} MB';
}

/// Daftar episode offline lintas anime. Menonton hasil download TIDAK butuh
/// Premium; yang khusus Premium hanya memulai download baru.
class DownloadsTab extends ConsumerWidget {
  const DownloadsTab({super.key, required this.onPlay});

  /// Putar episode (movieId, episodeId) -- dipakai ulang dari alur Profil.
  final void Function(String movieId, String episodeId) onPlay;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final downloads = ref.watch(localStoreProvider.select((s) => s.downloads));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ProfileSectionHeader(
          icon: Icons.download_done,
          title: 'Download',
          trailing: downloads.isEmpty ? null : '${downloads.length} Episode',
        ),
        if (downloads.isEmpty)
          const ProfileEmptyBox(
            text: 'Belum ada download. Ketuk ikon download di daftar episode '
                'untuk menyimpan episode dan nonton offline (download khusus Premium).',
          )
        else
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Column(
              children: [
                for (final d in downloads)
                  _DownloadedEpisodeCard(
                    key: ValueKey(d.episodeId),
                    item: d,
                    onPlay: () => onPlay(d.animeId, d.episodeId),
                    onDelete: () async {
                      final label = '${d.animeTitle} · Episode ${d.episodeIndex ?? ''}'.trim();
                      if (await confirmDeleteDownload(context, label: label) &&
                          context.mounted) {
                        await ref.read(episodeDownloadManagerProvider).deleteDownload(d.episodeId);
                      }
                    },
                  ),
              ],
            ),
          ),
      ],
    );
  }
}

class _DownloadedEpisodeCard extends StatelessWidget {
  const _DownloadedEpisodeCard({
    super.key,
    required this.item,
    required this.onPlay,
    required this.onDelete,
  });

  final DownloadedEpisodeEntity item;
  final VoidCallback onPlay;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final path = item.localFilePath;
    final fileOk = item.isCompleted && path != null && path.isNotEmpty && File(path).existsSync();
    final thumb = (item.episodeThumbnailUrl ?? '').isNotEmpty
        ? item.episodeThumbnailUrl!
        : (item.posterUrl ?? '');
    final progress = item.totalBytes > 0
        ? (item.downloadedBytes / item.totalBytes).clamp(0.0, 1.0)
        : null;

    final String subtitle;
    Color subtitleColor = AppColors.textMuted;
    if (item.isActive) {
      subtitle = item.totalBytes > 0
          ? 'Mengunduh… ${_formatBytes(item.downloadedBytes)} / ${_formatBytes(item.totalBytes)}'
          : 'Mengunduh…';
    } else if (item.isCompleted) {
      if (fileOk) {
        subtitle = [
          if ((item.quality ?? '').isNotEmpty) item.quality!,
          if (item.totalBytes > 0) _formatBytes(item.totalBytes),
        ].join(' · ');
      } else {
        subtitle = 'File tidak ditemukan di perangkat';
        subtitleColor = AppColors.errorRed;
      }
    } else {
      subtitle = 'Download gagal';
      subtitleColor = AppColors.errorRed;
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Material(
        color: AppColors.surfaceCard,
        borderRadius: AppShapes.card,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: fileOk ? onPlay : null,
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Row(
              children: [
                SizedBox(
                  width: 88,
                  height: 56,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        if (thumb.isNotEmpty)
                          NetImage(thumb)
                        else
                          const ColoredBox(color: AppColors.surfaceVariantDark),
                        ColoredBox(
                          color: const Color(0x55000000),
                          child: Center(
                            child: Icon(
                              fileOk ? Icons.play_arrow : Icons.download,
                              color: AppColors.textWhite,
                              size: 20,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.animeTitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: AppColors.textWhite,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Text(
                        'Episode ${item.episodeIndex ?? ''}'.trim(),
                        style: const TextStyle(
                          color: AppColors.accentViolet,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: subtitleColor, fontSize: 11),
                      ),
                      if (item.isActive) ...[
                        const SizedBox(height: 6),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(2),
                          child: LinearProgressIndicator(
                            value: progress,
                            minHeight: 3,
                            color: AppColors.accentViolet,
                            backgroundColor: const Color(0x22FFFFFF),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                InkResponse(
                  onTap: onDelete,
                  radius: 22,
                  child: const Padding(
                    padding: EdgeInsets.all(8),
                    child: Icon(Icons.delete_outline, color: AppColors.textMuted, size: 20),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

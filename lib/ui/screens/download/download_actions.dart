import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/error_message.dart';
import '../../../core/theme/app_colors.dart';
import '../../../data/download/episode_download_manager.dart';
import '../../../data/local/entities.dart';
import '../../../data/models/anime_item.dart';
import '../../../data/models/episode_item.dart';
import '../../../data/models/stream_data.dart';
import '../../../providers.dart';
import '../../app_routes.dart';

/// Dialog "Download khusus Premium" untuk user non-premium.
Future<void> showDownloadPremiumDialog(BuildContext context) {
  return showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: AppColors.surfaceDark,
      surfaceTintColor: Colors.transparent,
      title: const Text('Download khusus Premium',
          style: TextStyle(color: AppColors.textWhite)),
      content: const Text(
        'Nonton offline lewat download episode hanya untuk pengguna Premium.',
        style: TextStyle(color: AppColors.textSecondary),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('Nanti', style: TextStyle(color: AppColors.textSecondary)),
        ),
        TextButton(
          onPressed: () {
            Navigator.pop(ctx);
            openPremium(context);
          },
          child: const Text('Lihat Premium', style: TextStyle(color: AppColors.accentViolet)),
        ),
      ],
    ),
  );
}

Future<bool> confirmDeleteDownload(BuildContext context, {String? label}) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: AppColors.surfaceDark,
      surfaceTintColor: Colors.transparent,
      title: const Text('Hapus download?', style: TextStyle(color: AppColors.textWhite)),
      content: Text(
        label == null
            ? 'File episode ini akan dihapus dari perangkat.'
            : '$label akan dihapus dari perangkat.',
        style: const TextStyle(color: AppColors.textSecondary),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('Batal', style: TextStyle(color: AppColors.textSecondary)),
        ),
        TextButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: const Text('Hapus', style: TextStyle(color: AppColors.errorRed)),
        ),
      ],
    ),
  );
  return ok == true;
}

void _snack(BuildContext context, String msg) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(msg)));
}

/// Aksi tombol download di satu episode (Detail): non-premium -> ajakan
/// Premium; sudah selesai -> hapus; sedang jalan -> info; belum/gagal -> pilih
/// kualitas lalu download. Port alur Detail Zenime.
Future<void> onEpisodeDownloadTap(
  BuildContext context,
  WidgetRef ref, {
  required String movieId,
  required AnimeItem? anime,
  required EpisodeItem episode,
}) async {
  final id = episode.id;
  if (id == null || id.isEmpty) return;

  final isPremium = ref.read(myPremiumProvider).valueOrNull ?? false;
  if (!isPremium) {
    await showDownloadPremiumDialog(context);
    return;
  }

  final manager = ref.read(episodeDownloadManagerProvider);
  final entry = ref.read(localStoreProvider).downloadFor(id);

  if (entry != null && entry.isCompleted) {
    final label = 'Episode ${episode.index ?? ''}'.trim();
    if (await confirmDeleteDownload(context, label: label) && context.mounted) {
      await manager.deleteDownload(id);
    }
    return;
  }
  if (entry != null && entry.isActive) {
    _snack(context, 'Episode ini sedang didownload');
    return;
  }

  final server = await showDialog<StreamServer>(
    context: context,
    builder: (_) => _QualityDialog(episodeId: id),
  );
  if (server == null || !context.mounted) return;

  final err = await manager.startDownload(
    episodeId: id,
    animeId: movieId,
    animeTitle: anime?.title ?? 'Anime',
    posterUrl: anime?.posterUrl,
    episodeTitle: episode.title,
    episodeIndex: episode.index,
    quality: server.quality,
    videoUrl: server.link ?? '',
    episodeThumbnailUrl: episode.imageUrl,
  );
  if (!context.mounted) return;
  _snack(context, err ?? 'Download dimulai');
}

/// Dialog pilih kualitas: stream di-fetch FRESH (link signed URL cepat
/// kedaluwarsa) dan link yang dipilih langsung dipakai download.
class _QualityDialog extends ConsumerStatefulWidget {
  const _QualityDialog({required this.episodeId});

  final String episodeId;

  @override
  ConsumerState<_QualityDialog> createState() => _QualityDialogState();
}

class _QualityDialogState extends ConsumerState<_QualityDialog> {
  List<StreamServer>? _options;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final data = await ref.read(repositoryProvider).getEpisodeStream(widget.episodeId);
      final opts = EpisodeDownloadManager.qualityOptions(data);
      if (!mounted) return;
      setState(() {
        if (opts.isEmpty) {
          _error = 'Tidak ada pilihan kualitas yang tersedia untuk episode ini';
        } else {
          _options = opts;
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = errorMessage(e, 'Gagal memuat pilihan kualitas'));
    }
  }

  @override
  Widget build(BuildContext context) {
    final Widget body;
    if (_error != null) {
      body = Text(_error!, style: const TextStyle(color: AppColors.errorRed));
    } else if (_options == null) {
      body = const Padding(
        padding: EdgeInsets.symmetric(vertical: 12),
        child: Center(
          child: SizedBox(
            width: 28,
            height: 28,
            child: CircularProgressIndicator(strokeWidth: 2.5, color: AppColors.accentViolet),
          ),
        ),
      );
    } else {
      body = Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < _options!.length; i++)
            InkWell(
              borderRadius: BorderRadius.circular(10),
              onTap: () => Navigator.pop(context, _options![i]),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
                child: Row(
                  children: [
                    const Icon(Icons.download_for_offline,
                        size: 20, color: AppColors.accentViolet),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        _options![i].quality ?? 'Kualitas ${i + 1}',
                        style: const TextStyle(color: AppColors.textWhite, fontSize: 15),
                      ),
                    ),
                    if (i == 0)
                      const Text('Terbaik',
                          style: TextStyle(color: AppColors.accentViolet, fontSize: 11)),
                  ],
                ),
              ),
            ),
        ],
      );
    }
    return AlertDialog(
      backgroundColor: AppColors.surfaceDark,
      surfaceTintColor: Colors.transparent,
      title: const Text('Pilih Kualitas Download',
          style: TextStyle(color: AppColors.textWhite, fontSize: 18)),
      content: body,
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Batal', style: TextStyle(color: AppColors.textSecondary)),
        ),
      ],
    );
  }
}

import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../app_routes.dart';
import 'downloads_tab.dart';
import '../../glass/glass.dart';

/// Halaman Download (dibuka dari Pengaturan): episode offline lintas anime.
/// Bisa dibuka semua user; yang khusus Premium hanya memulai download baru.
class DownloadsScreen extends StatelessWidget {
  const DownloadsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return GlassScaffold(
      backgroundColor: AppColors.backgroundDark,
      appBar: GlassAppBar(
        backgroundColor: AppColors.backgroundDark,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          onPressed: () => Navigator.of(context).maybePop(),
          tooltip: 'Kembali',
          icon: const Icon(Icons.arrow_back, color: AppColors.textWhite),
        ),
        title: const Text(
          'Download',
          style: TextStyle(
            color: AppColors.textWhite,
            fontSize: 18,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.only(bottom: 40),
        child: DownloadsTab(
          onPlay: (movieId, episodeId) => openPlayer(context, movieId, episodeId),
        ),
      ),
    );
  }
}

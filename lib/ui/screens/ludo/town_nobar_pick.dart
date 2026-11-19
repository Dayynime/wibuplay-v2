import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../app_routes.dart';
import '../explore/explore_screen.dart';

/// "Mulai Nobar" dari Panggung Zenime Town: pilih anime (layar Jelajah),
/// putar episode, lalu tekan tombol Nobar di player. Room yang dibuat
/// otomatis dipasang ke panggung Plaza (lihat TownStageLink).
class TownNobarPickScreen extends StatelessWidget {
  const TownNobarPickScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.backgroundDark,
      body: Column(
        children: [
          Expanded(child: ExploreScreen(onAnimeClick: (id) => openDetail(context, id))),
          SafeArea(
            top: false,
            child: Container(
              width: double.infinity,
              margin: const EdgeInsets.fromLTRB(12, 6, 12, 10),
              padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
              decoration: BoxDecoration(
                color: const Color(0xFF2B2466),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFF8B6FD6).withValues(alpha: .5)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.live_tv_rounded, color: Color(0xFFFFD84D), size: 22),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Text(
                      'Pilih anime, putar episodenya, lalu tekan tombol Nobar di player. '
                      'Tayanganmu langsung muncul di Panggung Nobar Town.',
                      style: TextStyle(color: Colors.white, fontSize: 12.5, fontWeight: FontWeight.w600, height: 1.35),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Kembali ke Town',
                    onPressed: () => Navigator.of(context).maybePop(),
                    icon: const Icon(Icons.close_rounded, color: Colors.white70),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../data/models/chat_models.dart';
import '../../../data/models/wallpaper_models.dart';
import '../../app_routes.dart' show fadeRoute;
import '../wallpaper/wallpaper_screen.dart';

/// Kartu pengumuman Event Limited di chat global (dikirim server saat event
/// mulai / selesai). Tampil di tengah, tanpa avatar, tidak bisa dibalas.
class WpEventChatCard extends StatelessWidget {
  const WpEventChatCard({super.key, required this.message});

  final ChatMessage message;

  @override
  Widget build(BuildContext context) {
    final ended = message.isWpEventEnd;
    const ink = Color(0xFF1C2230);
    final time = message.time;
    String two(int v) => v.toString().padLeft(2, '0');

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
              border: Border.all(color: ended ? const Color(0x22FFFFFF) : const Color(0xCCFFFFFF)),
              boxShadow: ended ? null : const [BoxShadow(color: Color(0x44E8ECF2), blurRadius: 16)],
            ),
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      ended ? Icons.flag_rounded : Icons.auto_awesome,
                      size: 16,
                      color: ended ? AppColors.textSecondary : ink,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        ended ? 'EVENT LIMITED SELESAI' : 'EVENT LIMITED DIMULAI',
                        style: TextStyle(
                          color: ended ? AppColors.textSecondary : ink,
                          fontSize: 11,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 0.6,
                        ),
                      ),
                    ),
                    if (time != null)
                      Text(
                        '${two(time.hour)}:${two(time.minute)}',
                        style: TextStyle(
                          color: ended ? AppColors.textMuted : ink.withValues(alpha: 0.6),
                          fontSize: 10,
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  message.message,
                  style: TextStyle(
                    color: ended ? AppColors.textWhite : ink,
                    fontSize: 13.5,
                    height: 1.35,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (!ended) ...[
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      style: FilledButton.styleFrom(
                        backgroundColor: ink,
                        foregroundColor: Colors.white,
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
          ),
        ),
      ),
    );
  }
}

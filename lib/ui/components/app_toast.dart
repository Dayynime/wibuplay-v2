import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';

/// Jenis toast: menentukan warna aksen & ikon bawaan.
enum ToastKind { success, info, warning, error }

extension on ToastKind {
  Color get color => switch (this) {
        ToastKind.success => AppColors.successGreen,
        ToastKind.info => const Color(0xFF60A5FA),
        ToastKind.warning => AppColors.warningAmber,
        ToastKind.error => AppColors.errorRed,
      };

  IconData get icon => switch (this) {
        ToastKind.success => Icons.check_circle_rounded,
        ToastKind.info => Icons.info_rounded,
        ToastKind.warning => Icons.error_rounded,
        ToastKind.error => Icons.error_rounded,
      };
}

/// Toast mengambang modern: kartu gelap kaca, ikon berwarna dalam lingkaran,
/// garis aksen tipis, teks putih jelas. Pengganti SnackBar polos.
void showAppToast(
  BuildContext context,
  String message, {
  ToastKind kind = ToastKind.info,
  IconData? icon,
  Duration duration = const Duration(milliseconds: 2600),
}) {
  final accent = kind.color;
  final messenger = ScaffoldMessenger.maybeOf(context);
  if (messenger == null) return;
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        backgroundColor: Colors.transparent,
        elevation: 0,
        padding: EdgeInsets.zero,
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 18),
        duration: duration,
        dismissDirection: DismissDirection.horizontal,
        content: _ToastCard(message: message, accent: accent, icon: icon ?? kind.icon),
      ),
    );
}

class _ToastCard extends StatelessWidget {
  const _ToastCard({required this.message, required this.accent, required this.icon});

  final String message;
  final Color accent;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      liveRegion: true,
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 11, 16, 11),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color.alphaBlend(accent.withValues(alpha: 0.14), const Color(0xF2202634)),
              const Color(0xF2171C27),
            ],
          ),
          border: Border.all(color: accent.withValues(alpha: 0.35)),
          boxShadow: [
            BoxShadow(color: Colors.black.withValues(alpha: 0.45), blurRadius: 24, offset: const Offset(0, 8)),
            BoxShadow(color: accent.withValues(alpha: 0.18), blurRadius: 18, spreadRadius: -6),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: accent.withValues(alpha: 0.18),
              ),
              alignment: Alignment.center,
              child: Icon(icon, color: accent, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                message,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: AppColors.textWhite,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  height: 1.3,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

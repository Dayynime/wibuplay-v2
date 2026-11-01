import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/build_flags.dart';
import '../../../core/theme/app_colors.dart';
import '../../glass/glass.dart';

/// Layar tunggal untuk APK versi GitHub: Zenime sekarang hanya di-update lewat
/// Play Store. Tidak ada tombol skip (lihat UpdateGate, [BuildFlags.migrateToPlay]).
class PlayMigrationScreen extends StatefulWidget {
  const PlayMigrationScreen({super.key});

  @override
  State<PlayMigrationScreen> createState() => _PlayMigrationScreenState();
}

class _PlayMigrationScreenState extends State<PlayMigrationScreen> {
  static final Uri _market = Uri.parse('market://details?id=${BuildFlags.playPackage}');
  static final Uri _web = Uri.parse('https://play.google.com/store/apps/details?id=${BuildFlags.playPackage}');

  String? _error;

  Future<void> _openPlay() async {
    setState(() => _error = null);
    var ok = false;
    try {
      ok = await launchUrl(_market, mode: LaunchMode.externalApplication);
    } catch (_) {}
    if (!ok) {
      try {
        ok = await launchUrl(_web, mode: LaunchMode.externalApplication);
      } catch (_) {}
    }
    if (!ok && mounted) {
      setState(() => _error = 'Play Store tidak bisa dibuka. Cari "Zenime" di Play Store.');
    }
  }

  @override
  Widget build(BuildContext context) {
    return GlassScaffold(
      backgroundColor: AppColors.backgroundDark,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(24),
                    child: Image.asset('assets/images/logo.jpg', width: 88, height: 88),
                  ),
                  const SizedBox(height: 22),
                  const Text(
                    'Zenime sekarang di Play Store',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: AppColors.textWhite, fontSize: 21, fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    'Versi ini tidak menerima update lagi. Semua update berikutnya hanya lewat '
                    'Google Play, jadi pasang Zenime dari Play Store untuk lanjut nonton.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: AppColors.textSecondary, fontSize: 14, height: 1.45),
                  ),
                  const SizedBox(height: 22),
                  const _Step(n: 1, text: 'Ketuk "Buka Play Store" di bawah.'),
                  const _Step(
                    n: 2,
                    text: 'Kalau tombolnya "Update", ketuk dan selesai. Kalau Play Store menolak '
                        '(tidak bisa dipasang / konflik), hapus dulu Zenime versi ini lalu pasang dari Play Store.',
                  ),
                  const _Step(n: 3, text: 'Login lagi dengan akun yang sama.'),
                  const SizedBox(height: 14),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFF34D399).withValues(alpha: 0.10),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: const Color(0xFF34D399).withValues(alpha: 0.35)),
                    ),
                    child: const Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.verified_user_rounded, color: Color(0xFF34D399), size: 20),
                        SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'ZCoin, Premium, clan, wallpaper, badge, dan teman tersimpan di akunmu, '
                            'jadi aman. Anime yang diunduh untuk offline perlu diunduh ulang.',
                            style: TextStyle(color: AppColors.textSecondary, fontSize: 12.5, height: 1.4),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 22),
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: FilledButton.icon(
                      onPressed: _openPlay,
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.accentViolet,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      ),
                      icon: const Icon(Icons.shop_rounded),
                      label: const Text('Buka Play Store', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
                    ),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 10),
                    Text(
                      _error!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: AppColors.warningAmber, fontSize: 12.5),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Step extends StatelessWidget {
  const _Step({required this.n, required this.text});

  final int n;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 22,
            height: 22,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: AppColors.accentViolet.withValues(alpha: 0.2),
              shape: BoxShape.circle,
            ),
            child: Text('$n',
                style: const TextStyle(color: AppColors.textWhite, fontSize: 12, fontWeight: FontWeight.w800)),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(text, style: const TextStyle(color: AppColors.textWhite, fontSize: 13.5, height: 1.4)),
          ),
        ],
      ),
    );
  }
}

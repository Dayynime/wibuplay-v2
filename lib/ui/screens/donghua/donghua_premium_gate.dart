import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../providers.dart';

/// Gate nonton donghua: BENERAN memblokir pemutar kalau non-premium.
/// Daftar & detail donghua (sinopsis, daftar episode) tetap terbuka untuk
/// semua orang; lock cuma saat masuk player. Port DonghuaPremiumGate.kt.
///
/// Belum login / cek status gagal = non-premium. Keputusan sebenarnya tetap
/// di SERVER (token premium), gate ini cuma untuk tampilan.
class DonghuaPremiumGate extends ConsumerWidget {
  const DonghuaPremiumGate({
    super.key,
    required this.onBackClick,
    required this.onUpgradeClick,
    required this.child,
  });

  final VoidCallback onBackClick;
  final VoidCallback onUpgradeClick;
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final premium = ref.watch(myPremiumProvider);
    if (premium.isLoading) {
      // Checking
      return const Scaffold(
        backgroundColor: Colors.black,
        body: Center(child: CircularProgressIndicator(color: AppColors.accentViolet)),
      );
    }
    if (premium.valueOrNull == true) return child;
    return _DonghuaLockedScreen(onBackClick: onBackClick, onUpgradeClick: onUpgradeClick);
  }
}

class _DonghuaLockedScreen extends StatelessWidget {
  const _DonghuaLockedScreen({required this.onBackClick, required this.onUpgradeClick});

  final VoidCallback onBackClick;
  final VoidCallback onUpgradeClick;

  static const List<String> _benefits = [
    'Nonton semua episode donghua',
    'Bebas iklan',
    'Kualitas HD',
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.backgroundDark,
      body: SafeArea(
        child: Stack(
          children: [
            Positioned(
              top: 4,
              left: 4,
              child: IconButton(
                onPressed: onBackClick,
                icon: const Icon(Icons.arrow_back, color: Colors.white),
              ),
            ),
            Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 28),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 84,
                      height: 84,
                      decoration: BoxDecoration(
                        color: AppColors.accentViolet.withValues(alpha: 0.16),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.lock_rounded,
                        size: 40,
                        color: AppColors.accentViolet,
                      ),
                    ),
                    const SizedBox(height: 22),
                    const Text(
                      'Donghua khusus member Premium',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Sinopsis dan daftar episode tetap bisa dibuka tanpa Premium.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 14,
                        height: 20 / 14,
                      ),
                    ),
                    const SizedBox(height: 22),
                    for (final b in _benefits)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 5),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.check_circle,
                              size: 20,
                              color: AppColors.successGreen,
                            ),
                            const SizedBox(width: 10),
                            Text(
                              b,
                              style: const TextStyle(color: Colors.white, fontSize: 14),
                            ),
                          ],
                        ),
                      ),
                    const SizedBox(height: 26),
                    SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: FilledButton(
                        onPressed: onUpgradeClick,
                        style: FilledButton.styleFrom(
                          backgroundColor: AppColors.accentViolet,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(100),
                          ),
                        ),
                        child: const Text(
                          'Upgrade ke Premium',
                          style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

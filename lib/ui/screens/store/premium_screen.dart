import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/supabase_config.dart';
import '../../../core/theme/app_colors.dart';
import '../../../data/models/account_models.dart';
import '../../../data/models/store_models.dart';
import '../../../providers.dart';
import '../../app_routes.dart';
import '../../components/common_components.dart';
import '../../components/shimmer.dart';
import '../auth/login_screen.dart';
import 'checkout_sheet.dart';
import 'store_widgets.dart';

/// Halaman beli Premium. Port PremiumScreen.kt dengan tampilan baru:
/// hero emas, kartu manfaat, pilih paket, dan bar bayar yang menempel.
class PremiumScreen extends ConsumerStatefulWidget {
  const PremiumScreen({super.key});

  @override
  ConsumerState<PremiumScreen> createState() => _PremiumScreenState();
}

class _PremiumScreenState extends ConsumerState<PremiumScreen>
    with WidgetsBindingObserver {
  String? _selectedId;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// Balik dari browser (setelah bayar) -> cek ulang status Premium.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    final uid = ref.read(authUserProvider).valueOrNull?.uid;
    if (uid != null) ref.invalidate(premiumStatusProvider(uid));
  }

  PremiumPackage? _selected(List<PremiumPackage> pkgs, Map<String, int> savings) {
    if (pkgs.isEmpty) return null;
    for (final p in pkgs) {
      if (p.id == _selectedId) return p;
    }
    for (final p in pkgs) {
      if (p.badge != null) return p;
    }
    PremiumPackage best = pkgs.first;
    var bestSave = savings[best.id] ?? 0;
    for (final p in pkgs) {
      final s = savings[p.id] ?? 0;
      if (s > bestSave) {
        best = p;
        bestSave = s;
      }
    }
    return best;
  }

  Future<void> _login() =>
      Navigator.of(context).push<bool>(fadeRoute(const LoginScreen())).then((_) {});

  Future<void> _checkout(User? user, PremiumPackage pkg) async {
    if (user == null) {
      await _login();
      return;
    }
    await showCheckoutSheet(
      context,
      uid: user.uid,
      title: 'Paket ${pkg.label}',
      priceText: 'Rp ${formatRupiah(pkg.price)}',
      packageId: pkg.id,
      qrisUrl: SupabaseConfig.premiumStorefrontUrl,
      manualUrl: SupabaseConfig.premiumManualStorefrontUrl,
      leading: Image.asset('assets/images/ic_premium_badge.png', width: 34, height: 34),
      gradient: kGoldGradient,
      onGradient: kPremiumOnGold,
      onLaunched: () => ref.invalidate(premiumStatusProvider(user.uid)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authUserProvider).valueOrNull;
    final status = user == null
        ? const PremiumStatus()
        : (ref.watch(premiumStatusProvider(user.uid)).valueOrNull ?? const PremiumStatus());
    final packages = ref.watch(premiumPackagesProvider);

    final pkgs = packages.valueOrNull ?? const <PremiumPackage>[];
    final savings = premiumSavingPercents(pkgs);
    final selected = _selected(pkgs, savings);

    return Scaffold(
      backgroundColor: AppColors.backgroundDark,
      body: Column(
        children: [
          Expanded(
            child: SafeArea(
              bottom: false,
              child: Column(
                children: [
                  const StoreTopBar(title: 'Premium'),
                  Expanded(
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
                      children: [
                        _Hero(status: status),
                        const SizedBox(height: 26),
                        const StoreSectionTitle(
                          title: 'Yang kamu dapat',
                          subtitle: 'Dibanding akun gratis.',
                        ),
                        const SizedBox(height: 12),
                        const _BenefitGrid(),
                        const SizedBox(height: 26),
                        StoreSectionTitle(
                          title: status.isPremium ? 'Perpanjang Premium' : 'Pilih paket',
                          subtitle: 'Makin lama, makin hemat.',
                        ),
                        const SizedBox(height: 12),
                        if (user == null) ...[
                          StoreLoginCard(
                            message: 'Masuk dulu supaya Premium tersambung ke akunmu.',
                            onLogin: _login,
                          ),
                          const SizedBox(height: 12),
                        ],
                        packages.when(
                          loading: () => Column(
                            children: [
                              for (var i = 0; i < 3; i++) ...[
                                ShimmerBox(
                                  height: 76,
                                  borderRadius: BorderRadius.circular(18),
                                ),
                                const SizedBox(height: 10),
                              ],
                            ],
                          ),
                          error: (_, _) => ErrorState(
                            message: 'Gagal memuat daftar paket Premium',
                            onRetry: () => ref.invalidate(premiumPackagesProvider),
                          ),
                          data: (list) => list.isEmpty
                              ? const EmptyState(
                                  title: 'Belum ada paket',
                                  subtitle: 'Paket Premium belum tersedia. Coba lagi nanti.',
                                  icon: Icons.workspace_premium_outlined,
                                )
                              : Column(
                                  children: [
                                    for (final p in list) ...[
                                      _PlanCard(
                                        pkg: p,
                                        savePercent: savings[p.id],
                                        selected: selected?.id == p.id,
                                        onTap: () => setState(() => _selectedId = p.id),
                                      ),
                                      const SizedBox(height: 10),
                                    ],
                                  ],
                                ),
                        ),
                        const SizedBox(height: 6),
                        const Text(
                          'Premium aktif di akun ini setelah pembayaran terverifikasi.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: AppColors.textMuted, fontSize: 11),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (selected != null)
            StoreCtaBar(
              summary: 'Paket ${selected.label}',
              priceText: 'Rp ${formatRupiah(selected.price)}',
              buttonText: user == null
                  ? 'Masuk'
                  : (status.isPremium ? 'Perpanjang' : 'Lanjut bayar'),
              onPressed: () => _checkout(user, selected),
              gradient: kGoldGradient,
              onGradient: kPremiumOnGold,
            ),
        ],
      ),
    );
  }
}

class _Hero extends StatelessWidget {
  const _Hero({required this.status});

  final PremiumStatus status;

  @override
  Widget build(BuildContext context) {
    final days = status.daysLeft;
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 26, 24, 24),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: kPremiumGold.withValues(alpha: 0.28)),
        gradient: const LinearGradient(
          colors: [Color(0xFF252C3A), AppColors.surfaceCard],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
      ),
      child: Column(
        children: [
          Stack(
            alignment: Alignment.center,
            children: [
              Container(
                width: 150,
                height: 150,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      kPremiumGold.withValues(alpha: 0.32),
                      kPremiumGold.withValues(alpha: 0),
                    ],
                  ),
                ),
              ),
              Image.asset('assets/images/ic_premium_badge.png', height: 88),
            ],
          ),
          const SizedBox(height: 4),
          const Text(
            'Zenime Premium',
            style: TextStyle(
              color: AppColors.textWhite,
              fontSize: 26,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.6,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Kualitas sampai 1080p, nol iklan, download offline, dan XP nonton dobel.',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.textSecondary, fontSize: 13, height: 1.4),
          ),
          if (status.isPremium) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
              decoration: BoxDecoration(
                color: kPremiumGold.withValues(alpha: 0.16),
                borderRadius: BorderRadius.circular(100),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.verified, size: 16, color: kPremiumGold),
                  const SizedBox(width: 6),
                  Text(
                    days != null ? 'Premium aktif, sisa $days hari' : 'Premium aktif',
                    style: const TextStyle(
                      color: kPremiumGold,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _Benefit {
  const _Benefit(this.icon, this.title, this.detail);
  final IconData icon;
  final String title;
  final String detail;
}

// Sebagian fitur (download offline, donghua, banner profil custom, tanpa
// iklan) menyusul di versi berikutnya; sudah dijanjikan di sini seperti Zenime.
const List<_Benefit> _benefits = [
  _Benefit(Icons.hd_outlined, 'Sampai 1080p', 'Gratis maksimal 480p'),
  _Benefit(Icons.lock_open_rounded, 'Episode terbaru', '3 episode terakhir terbuka'),
  _Benefit(Icons.block_rounded, 'Tanpa iklan', 'Nonton tanpa gangguan'),
  _Benefit(Icons.download_rounded, 'Download offline', 'Simpan episode, nonton tanpa internet'),
  _Benefit(Icons.movie_filter_outlined, 'Nonton donghua', 'Akses penuh katalog donghua'),
  _Benefit(Icons.bolt_rounded, 'XP nonton ×2', 'Gratis ×1'),
  _Benefit(Icons.image_outlined, 'Banner profil custom', 'Pasang banner sendiri'),
  _Benefit(Icons.verified_rounded, 'Badge Premium', 'Centang di profil dan chat'),
];

class _BenefitGrid extends StatelessWidget {
  const _BenefitGrid();

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        const gap = 10.0;
        final w = (c.maxWidth - gap) / 2;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (final b in _benefits)
              SizedBox(
                width: w,
                child: Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: AppColors.surfaceCard,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: AppColors.surfaceVariantDark),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: kPremiumGold.withValues(alpha: 0.14),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(b.icon, size: 20, color: kPremiumGold),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        b.title,
                        style: const TextStyle(
                          color: AppColors.textWhite,
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        b.detail,
                        style: const TextStyle(color: AppColors.textMuted, fontSize: 11),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _PlanCard extends StatelessWidget {
  const _PlanCard({
    required this.pkg,
    required this.savePercent,
    required this.selected,
    required this.onTap,
  });

  final PremiumPackage pkg;
  final int? savePercent;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final perMonth = pkg.perMonth;
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
        decoration: BoxDecoration(
          color: selected ? kPremiumGold.withValues(alpha: 0.09) : AppColors.surfaceCard,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected ? kPremiumGold : AppColors.surfaceVariantDark,
            width: selected ? 1.6 : 1,
          ),
        ),
        child: Row(
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              width: 22,
              height: 22,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: selected ? kPremiumGold : Colors.transparent,
                border: Border.all(
                  color: selected ? kPremiumGold : AppColors.surfaceElevated,
                  width: 1.6,
                ),
              ),
              child: selected
                  ? const Icon(Icons.check, size: 14, color: kPremiumOnGold)
                  : null,
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          pkg.label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: AppColors.textWhite,
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      if (pkg.badge != null) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            gradient: kGoldGradient,
                            borderRadius: BorderRadius.circular(100),
                          ),
                          child: Text(
                            pkg.badge!,
                            style: const TextStyle(
                              color: kPremiumOnGold,
                              fontSize: 10,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    perMonth != null
                        ? 'Rp ${formatRupiah(perMonth)} per bulan'
                        : pkg.durationText,
                    style: const TextStyle(color: AppColors.textMuted, fontSize: 12),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  'Rp ${formatRupiah(pkg.price)}',
                  style: const TextStyle(
                    color: AppColors.textWhite,
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                if (savePercent != null)
                  Text(
                    'Hemat $savePercent%',
                    style: const TextStyle(
                      color: AppColors.successGreen,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

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

/// Halaman top up ZCoin. Port CoinScreen.kt dengan tampilan baru:
/// kartu saldo, paket dua kolom, dan bar bayar yang menempel.
class CoinScreen extends ConsumerStatefulWidget {
  const CoinScreen({super.key});

  @override
  ConsumerState<CoinScreen> createState() => _CoinScreenState();
}

class _CoinScreenState extends ConsumerState<CoinScreen> with WidgetsBindingObserver {
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

  /// Balik dari browser (setelah bayar) -> muat ulang saldo.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    final uid = ref.read(authUserProvider).valueOrNull?.uid;
    if (uid != null) ref.invalidate(coinBalanceProvider(uid));
  }

  CoinPackage? _selected(List<CoinPackage> pkgs) {
    if (pkgs.isEmpty) return null;
    for (final p in pkgs) {
      if (p.id == _selectedId) return p;
    }
    return pkgs.first;
  }

  Future<void> _login() =>
      Navigator.of(context).push<bool>(fadeRoute(const LoginScreen())).then((_) {});

  Future<void> _checkout(User? user, CoinPackage pkg) async {
    if (user == null) {
      await _login();
      return;
    }
    await showCheckoutSheet(
      context,
      uid: user.uid,
      title: '${formatRupiah(pkg.totalCoin)} ZCoin',
      priceText: 'Rp ${formatRupiah(pkg.price)}',
      packageId: pkg.id,
      qrisUrl: SupabaseConfig.coinStorefrontUrl,
      manualUrl: SupabaseConfig.coinManualStorefrontUrl,
      leading: ClipOval(
        child: Image.asset('assets/images/ic_zcoin_badge.png', width: 34, height: 34),
      ),
      gradient: kVioletGradient,
      onGradient: Colors.white,
      onLaunched: () => ref.invalidate(coinBalanceProvider(user.uid)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authUserProvider).valueOrNull;
    final balance = user == null ? null : ref.watch(coinBalanceProvider(user.uid));
    final packages = ref.watch(coinPackagesProvider);

    final pkgs = packages.valueOrNull ?? const <CoinPackage>[];
    final selected = _selected(pkgs);

    // Paket dengan persen bonus terbesar diberi penanda.
    String? bestBonusId;
    var bestBonus = 0;
    for (final p in pkgs) {
      if (p.bonusPercent > bestBonus) {
        bestBonus = p.bonusPercent;
        bestBonusId = p.id;
      }
    }

    return Scaffold(
      backgroundColor: AppColors.backgroundDark,
      body: Column(
        children: [
          Expanded(
            child: SafeArea(
              bottom: false,
              child: Column(
                children: [
                  const StoreTopBar(title: 'ZCoin'),
                  Expanded(
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
                      children: [
                        _BalanceCard(
                          loggedIn: user != null,
                          balance: balance,
                          onRefresh: user == null
                              ? null
                              : () => ref.invalidate(coinBalanceProvider(user.uid)),
                          onLogin: _login,
                        ),
                        const SizedBox(height: 26),
                        const StoreSectionTitle(
                          title: 'Pilih paket top up',
                          subtitle: 'Paket besar dapat bonus ZCoin.',
                        ),
                        const SizedBox(height: 12),
                        packages.when(
                          loading: () => Wrap(
                            spacing: 10,
                            runSpacing: 10,
                            children: [
                              for (var i = 0; i < 4; i++)
                                LayoutBuilder(
                                  builder: (context, _) => ShimmerBox(
                                    width: (MediaQuery.of(context).size.width - 50) / 2,
                                    height: 140,
                                    borderRadius: BorderRadius.circular(20),
                                  ),
                                ),
                            ],
                          ),
                          error: (_, _) => ErrorState(
                            message: 'Gagal memuat daftar paket ZCoin',
                            onRetry: () => ref.invalidate(coinPackagesProvider),
                          ),
                          data: (list) => list.isEmpty
                              ? const EmptyState(
                                  title: 'Belum ada paket',
                                  subtitle: 'Paket ZCoin belum tersedia. Coba lagi nanti.',
                                  icon: Icons.monetization_on_outlined,
                                )
                              : LayoutBuilder(
                                  builder: (context, c) {
                                    const gap = 10.0;
                                    final w = (c.maxWidth - gap) / 2;
                                    return Wrap(
                                      spacing: gap,
                                      runSpacing: gap,
                                      children: [
                                        for (final p in list)
                                          SizedBox(
                                            width: w,
                                            child: _CoinCard(
                                              pkg: p,
                                              selected: selected?.id == p.id,
                                              isBestBonus: p.id == bestBonusId,
                                              onTap: () => setState(() => _selectedId = p.id),
                                            ),
                                          ),
                                      ],
                                    );
                                  },
                                ),
                        ),
                        const SizedBox(height: 14),
                        const Text(
                          'ZCoin masuk ke saldo setelah pembayaran terverifikasi.',
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
              summary: '${formatRupiah(selected.totalCoin)} ZCoin',
              priceText: 'Rp ${formatRupiah(selected.price)}',
              buttonText: user == null ? 'Masuk' : 'Top up',
              onPressed: () => _checkout(user, selected),
              gradient: kVioletGradient,
              onGradient: Colors.white,
            ),
        ],
      ),
    );
  }
}

class _BalanceCard extends StatelessWidget {
  const _BalanceCard({
    required this.loggedIn,
    required this.balance,
    required this.onRefresh,
    required this.onLogin,
  });

  final bool loggedIn;
  final AsyncValue<int>? balance;
  final VoidCallback? onRefresh;
  final VoidCallback onLogin;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(28),
      child: Container(
        decoration: const BoxDecoration(gradient: kVioletGradient),
        child: Stack(
          children: [
            // Lingkaran dekoratif di sudut kanan atas.
            Positioned(
              right: -40,
              top: -50,
              child: Container(
                width: 170,
                height: 170,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withValues(alpha: 0.08),
                ),
              ),
            ),
            Positioned(
              right: 30,
              bottom: -60,
              child: Container(
                width: 110,
                height: 110,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withValues(alpha: 0.06),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(22),
              child: Row(
                children: [
                  ClipOval(
                    child: Image.asset(
                      'assets/images/ic_zcoin_badge.png',
                      width: 52,
                      height: 52,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Saldo ZCoin',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.8),
                            fontSize: 12,
                          ),
                        ),
                        const SizedBox(height: 2),
                        _amount(),
                      ],
                    ),
                  ),
                  if (loggedIn)
                    IconButton(
                      tooltip: 'Muat ulang saldo',
                      onPressed: onRefresh,
                      icon: const Icon(Icons.refresh_rounded, color: Colors.white),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _amount() {
    if (!loggedIn) {
      return GestureDetector(
        onTap: onLogin,
        child: const Text(
          'Masuk untuk lihat saldo',
          style: TextStyle(
            color: Colors.white,
            fontSize: 17,
            fontWeight: FontWeight.w700,
            decoration: TextDecoration.underline,
            decorationColor: Colors.white,
          ),
        ),
      );
    }
    final b = balance;
    if (b == null || b.isLoading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 8),
        child: SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white),
        ),
      );
    }
    return Text(
      formatZCoin(b.valueOrNull ?? 0),
      style: const TextStyle(
        color: Colors.white,
        fontSize: 32,
        fontWeight: FontWeight.w800,
        letterSpacing: -0.8,
        height: 1.1,
      ),
    );
  }
}

class _CoinCard extends StatelessWidget {
  const _CoinCard({
    required this.pkg,
    required this.selected,
    required this.isBestBonus,
    required this.onTap,
  });

  final CoinPackage pkg;
  final bool selected;
  final bool isBestBonus;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: selected
              ? AppColors.accentViolet.withValues(alpha: 0.14)
              : AppColors.surfaceCard,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected ? AppColors.accentVioletLight : AppColors.surfaceVariantDark,
            width: selected ? 1.6 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                ClipOval(
                  child: Image.asset(
                    'assets/images/ic_zcoin_badge.png',
                    width: 28,
                    height: 28,
                  ),
                ),
                const Spacer(),
                if (pkg.bonusCoin > 0)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: AppColors.successGreen.withValues(alpha: 0.16),
                      borderRadius: BorderRadius.circular(100),
                    ),
                    child: Text(
                      pkg.bonusPercent > 0 ? 'Bonus ${pkg.bonusPercent}%' : 'Bonus',
                      style: const TextStyle(
                        color: AppColors.successGreen,
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 14),
            Text(
              formatRupiah(pkg.totalCoin),
              style: const TextStyle(
                color: AppColors.textWhite,
                fontSize: 22,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.4,
              ),
            ),
            Text(
              pkg.bonusCoin > 0
                  ? '${formatRupiah(pkg.coinAmount)} + ${formatRupiah(pkg.bonusCoin)} bonus'
                  : 'ZCoin',
              style: const TextStyle(color: AppColors.textMuted, fontSize: 11),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Rp ${formatRupiah(pkg.price)}',
                    style: TextStyle(
                      color: selected ? AppColors.accentVioletLight : AppColors.textSecondary,
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                if (isBestBonus)
                  const Icon(Icons.local_fire_department_rounded,
                      size: 16, color: AppColors.warningAmber),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

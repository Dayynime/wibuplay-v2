import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/theme/app_colors.dart';
import '../../../providers.dart';
import 'store_widgets.dart';

/// Bottom sheet checkout yang dipakai bareng halaman Premium dan ZCoin.
/// Port CheckoutSheet.kt: ringkasan pesanan, kode akun (bisa disalin), bayar
/// QRIS, dan opsi pembeli luar negeri (diverifikasi manual admin).
/// Pembayaran sendiri terjadi di halaman storefront (browser).
Future<void> showCheckoutSheet(
  BuildContext context, {
  required String uid,
  required String title,
  required String priceText,
  required String packageId,
  required String qrisUrl,
  required String manualUrl,
  required Widget leading,
  required Gradient gradient,
  required Color onGradient,
  VoidCallback? onLaunched,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: AppColors.surfaceDark,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
    ),
    builder: (_) => _CheckoutSheet(
      uid: uid,
      title: title,
      priceText: priceText,
      packageId: packageId,
      qrisUrl: qrisUrl,
      manualUrl: manualUrl,
      leading: leading,
      gradient: gradient,
      onGradient: onGradient,
      onLaunched: onLaunched,
    ),
  );
}

class _CheckoutSheet extends ConsumerStatefulWidget {
  const _CheckoutSheet({
    required this.uid,
    required this.title,
    required this.priceText,
    required this.packageId,
    required this.qrisUrl,
    required this.manualUrl,
    required this.leading,
    required this.gradient,
    required this.onGradient,
    this.onLaunched,
  });

  final String uid;
  final String title;
  final String priceText;
  final String packageId;
  final String qrisUrl;
  final String manualUrl;
  final Widget leading;
  final Gradient gradient;
  final Color onGradient;
  final VoidCallback? onLaunched;

  @override
  ConsumerState<_CheckoutSheet> createState() => _CheckoutSheetState();
}

class _CheckoutSheetState extends ConsumerState<_CheckoutSheet> {
  bool _copied = false;

  Future<void> _copy(String code) async {
    await Clipboard.setData(ClipboardData(text: code));
    if (mounted) setState(() => _copied = true);
  }

  Future<void> _open(String base, String code) async {
    final uri = Uri.parse(base);
    final target = uri.replace(
      queryParameters: {
        ...uri.queryParameters,
        'code': code,
        'package_id': widget.packageId,
      },
    );
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final ok = await launchUrl(target, mode: LaunchMode.externalApplication);
    if (!ok) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Tidak ada browser untuk membuka halaman pembayaran')),
      );
      return;
    }
    widget.onLaunched?.call();
    if (navigator.mounted) navigator.pop();
  }

  @override
  Widget build(BuildContext context) {
    final identity = ref.watch(profileIdentityProvider(widget.uid));
    final bottom = MediaQuery.of(context).padding.bottom;

    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(20, 10, 20, 20 + bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 38,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.surfaceElevated,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: AppColors.surfaceVariantDark,
                  borderRadius: BorderRadius.circular(16),
                ),
                alignment: Alignment.center,
                child: widget.leading,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Ringkasan pesanan',
                      style: TextStyle(color: AppColors.textMuted, fontSize: 11),
                    ),
                    Text(
                      widget.title,
                      style: const TextStyle(
                        color: AppColors.textWhite,
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              Text(
                widget.priceText,
                style: const TextStyle(
                  color: AppColors.textWhite,
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          identity.when(
            loading: () => const Padding(
              padding: EdgeInsets.symmetric(vertical: 36),
              child: Center(
                child: SizedBox(
                  width: 26,
                  height: 26,
                  child: CircularProgressIndicator(strokeWidth: 3),
                ),
              ),
            ),
            error: (_, _) => _codeError(),
            data: (id) {
              final code = id.zenimeCode;
              if (code == null || code.isEmpty) return _codeError();
              return _payment(code);
            },
          ),
        ],
      ),
    );
  }

  Widget _codeError() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.errorRed.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Gagal mengambil kode akun. Cek koneksi lalu coba lagi.',
            style: TextStyle(color: AppColors.errorRed, fontSize: 13),
          ),
          const SizedBox(height: 10),
          OutlinedButton(
            onPressed: () => ref.invalidate(profileIdentityProvider(widget.uid)),
            child: const Text('Coba Lagi'),
          ),
        ],
      ),
    );
  }

  Widget _payment(String code) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Kode akun kamu',
          style: TextStyle(color: AppColors.textMuted, fontSize: 11),
        ),
        const SizedBox(height: 6),
        Container(
          padding: const EdgeInsets.only(left: 16, right: 6),
          decoration: BoxDecoration(
            color: AppColors.surfaceVariantDark,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  code,
                  style: const TextStyle(
                    color: AppColors.accentVioletLight,
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1,
                  ),
                ),
              ),
              IconButton(
                tooltip: _copied ? 'Kode tersalin' : 'Salin kode',
                onPressed: () => _copy(code),
                icon: Icon(
                  _copied ? Icons.check : Icons.copy_rounded,
                  size: 18,
                  color: _copied ? AppColors.successGreen : AppColors.textSecondary,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 6),
        const Text(
          'Kode ikut terkirim ke halaman pembayaran. Salin kalau perlu diisi manual.',
          style: TextStyle(color: AppColors.textMuted, fontSize: 11),
        ),
        const SizedBox(height: 20),
        Material(
          color: Colors.transparent,
          child: Ink(
            decoration: BoxDecoration(
              gradient: widget.gradient,
              borderRadius: BorderRadius.circular(16),
            ),
            child: InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: () => _open(widget.qrisUrl, code),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.qr_code_2_rounded, size: 22, color: widget.onGradient),
                    const SizedBox(width: 10),
                    Text(
                      'Bayar dengan QRIS',
                      style: TextStyle(
                        color: widget.onGradient,
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 6),
        const Center(
          child: Text(
            'Aktif otomatis setelah pembayaran berhasil.',
            style: TextStyle(color: AppColors.textMuted, fontSize: 11),
          ),
        ),
        const SizedBox(height: 14),
        OutlinedButton(
          onPressed: () => _open(widget.manualUrl, code),
          style: OutlinedButton.styleFrom(
            side: const BorderSide(color: AppColors.surfaceElevated),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          ),
          child: const Row(
            children: [
              Icon(Icons.public, size: 18, color: AppColors.textSecondary),
              SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Bayar dari luar negeri',
                      style: TextStyle(
                        color: AppColors.textWhite,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      'QRIS lain, diverifikasi manual oleh admin',
                      style: TextStyle(color: AppColors.textMuted, fontSize: 11),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        const Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.lock_outline, size: 12, color: AppColors.textMuted),
            SizedBox(width: 6),
            Text(
              'Pembayaran diproses lewat Zenime Store',
              style: TextStyle(color: AppColors.textMuted, fontSize: 11),
            ),
          ],
        ),
      ],
    );
  }
}

import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';

/// Emas untuk semua penanda Premium.
const Color kPremiumGold = Color(0xFFF2C46D);
const Color kPremiumGoldDeep = Color(0xFFE0A93B);
const Color kPremiumOnGold = Color(0xFF3A2A05);

const LinearGradient kGoldGradient = LinearGradient(
  colors: [Color(0xFFF7D78B), kPremiumGoldDeep],
  begin: Alignment.topLeft,
  end: Alignment.bottomRight,
);

const LinearGradient kVioletGradient = LinearGradient(
  colors: [AppColors.accentVioletLight, AppColors.accentVioletDark],
  begin: Alignment.topLeft,
  end: Alignment.bottomRight,
);

/// Bar atas sederhana: tombol kembali bulat + judul.
class StoreTopBar extends StatelessWidget {
  const StoreTopBar({super.key, required this.title, this.trailing});

  final String title;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: Row(
        children: [
          Material(
            color: AppColors.surfaceCard,
            shape: const CircleBorder(),
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: () => Navigator.of(context).maybePop(),
              child: const SizedBox(
                width: 40,
                height: 40,
                child: Icon(
                  Icons.arrow_back_ios_new_rounded,
                  size: 16,
                  color: AppColors.textWhite,
                ),
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Text(
              title,
              style: const TextStyle(
                color: AppColors.textWhite,
                fontSize: 20,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.3,
              ),
            ),
          ),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}

/// Judul bagian + keterangan singkat.
class StoreSectionTitle extends StatelessWidget {
  const StoreSectionTitle({super.key, required this.title, this.subtitle});

  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            color: AppColors.textWhite,
            fontSize: 16,
            fontWeight: FontWeight.w700,
          ),
        ),
        if (subtitle != null) ...[
          const SizedBox(height: 2),
          Text(
            subtitle!,
            style: const TextStyle(color: AppColors.textMuted, fontSize: 12),
          ),
        ],
      ],
    );
  }
}

/// Bar bawah yang menempel: ringkasan pilihan + tombol utama.
class StoreCtaBar extends StatelessWidget {
  const StoreCtaBar({
    super.key,
    required this.summary,
    required this.priceText,
    required this.buttonText,
    required this.onPressed,
    required this.gradient,
    required this.onGradient,
  });

  final String summary;
  final String priceText;
  final String buttonText;
  final VoidCallback? onPressed;
  final Gradient gradient;
  final Color onGradient;

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).padding.bottom;
    final enabled = onPressed != null;
    return Container(
      padding: EdgeInsets.fromLTRB(20, 14, 20, 14 + bottom),
      decoration: BoxDecoration(
        color: AppColors.backgroundDarkSecondary,
        border: const Border(top: BorderSide(color: AppColors.surfaceVariantDark)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.35),
            blurRadius: 24,
            offset: const Offset(0, -6),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  summary,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: AppColors.textMuted, fontSize: 11),
                ),
                const SizedBox(height: 2),
                Text(
                  priceText,
                  style: const TextStyle(
                    color: AppColors.textWhite,
                    fontSize: 19,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 14),
          Opacity(
            opacity: enabled ? 1 : 0.5,
            child: Material(
              color: Colors.transparent,
              child: Ink(
                decoration: BoxDecoration(
                  gradient: gradient,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: InkWell(
                  borderRadius: BorderRadius.circular(16),
                  onTap: onPressed,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 15),
                    child: Text(
                      buttonText,
                      style: TextStyle(
                        color: onGradient,
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Kartu ajakan masuk untuk pengguna yang belum login.
class StoreLoginCard extends StatelessWidget {
  const StoreLoginCard({super.key, required this.message, required this.onLogin});

  final String message;
  final VoidCallback onLogin;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surfaceCard,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.surfaceVariantDark),
      ),
      child: Row(
        children: [
          const Icon(Icons.lock_outline, color: AppColors.accentVioletLight, size: 22),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
            ),
          ),
          const SizedBox(width: 8),
          FilledButton(
            onPressed: onLogin,
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.accentViolet,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: const Text('Masuk'),
          ),
        ],
      ),
    );
  }
}

import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../data/models/clan_models.dart';
import '../../components/hero_slides.dart' show heroGold;
import '../../components/net_image.dart';

/// Warna role clan (sama dengan Zenime).
Color clanRoleColor(String role) {
  switch (role) {
    case ClanRoles.leader:
      return const Color(0xFFFFC107);
    case ClanRoles.viceLeader:
      return const Color(0xFF9F7AEA);
    case ClanRoles.admiral:
      return const Color(0xFFE0912F);
    case ClanRoles.officer:
      return const Color(0xFF26A69A);
    default:
      return const Color(0xFF607D8B);
  }
}

const Color clanGemBlue = Color(0xFF4FC3F7);
const Color clanSurface = Color(0xFF171E36);
const Color clanBorder = Color(0x14FFFFFF);

/// 1.2K / 3.4M / 5.6B, dibulatkan satu desimal dan ".0" dibuang.
String formatCompact(int v) {
  String fmt(double x, String suffix) {
    final t = x.toStringAsFixed(1);
    return '${t.endsWith('.0') ? t.substring(0, t.length - 2) : t}$suffix';
  }

  final n = v.abs().toDouble();
  final sign = v < 0 ? '-' : '';
  if (n >= 1e9) return '$sign${fmt(n / 1e9, 'B')}';
  if (n >= 1e6) return '$sign${fmt(n / 1e6, 'M')}';
  if (n >= 1e3) return '$sign${fmt(n / 1e3, 'K')}';
  return '$v';
}

/// Tanggal ISO -> "12 Mar 26"; gagal parse = string kosong.
String formatJoinShort(String iso) {
  final d = DateTime.tryParse(iso)?.toLocal();
  if (d == null) return '';
  const m = ['Jan', 'Feb', 'Mar', 'Apr', 'Mei', 'Jun', 'Jul', 'Agu', 'Sep', 'Okt', 'Nov', 'Des'];
  return '${d.day} ${m[d.month - 1]} ${(d.year % 100).toString().padLeft(2, '0')}';
}

/// Avatar clan: kotak membulat dengan foto, atau inisial tag kalau tidak ada foto.
class ClanAvatar extends StatelessWidget {
  const ClanAvatar({super.key, required this.tag, this.url, this.size = 52});

  final String tag;
  final String? url;
  final double size;

  @override
  Widget build(BuildContext context) {
    final has = url != null && url!.isNotEmpty;
    final radius = BorderRadius.circular(size * 0.3);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: radius,
        border: Border.all(color: const Color(0x26FFFFFF)),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF5A1B26), Color(0xFF3A1219)],
        ),
      ),
      clipBehavior: Clip.antiAlias,
      alignment: Alignment.center,
      child: has
          ? SizedBox.expand(child: NetImage(url!))
          : Text(
              tag.isEmpty ? '?' : tag.substring(0, tag.length < 2 ? tag.length : 2).toUpperCase(),
              style: TextStyle(
                color: Colors.white,
                fontSize: size * 0.34,
                fontWeight: FontWeight.w800,
              ),
            ),
    );
  }
}

/// Pil role kecil berwarna.
class ClanRoleChip extends StatelessWidget {
  const ClanRoleChip({super.key, required this.role});

  final String role;

  @override
  Widget build(BuildContext context) {
    final color = clanRoleColor(role);
    final dark = role == ClanRoles.leader || role == ClanRoles.admiral;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(50)),
      child: Text(
        ClanRoles.label(role),
        maxLines: 1,
        style: TextStyle(
          color: dark ? const Color(0xFF2B1600) : Colors.white,
          fontSize: 8,
          fontWeight: FontWeight.w800,
          height: 1.2,
          letterSpacing: 0.3,
        ),
      ),
    );
  }
}

/// Pil kontribusi/donasi dengan ikon permata.
class GemPill extends StatelessWidget {
  const GemPill({super.key, required this.amount});

  final int amount;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minWidth: 72),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: clanGemBlue.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(50),
        border: Border.all(color: clanGemBlue.withValues(alpha: 0.28)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.diamond_rounded, size: 14, color: clanGemBlue),
          const SizedBox(width: 5),
          Text(
            formatCompact(amount),
            maxLines: 1,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

/// Tombol utama bergradien violet; [loading] menampilkan spinner dan
/// menonaktifkan tap.
class ClanGradientButton extends StatelessWidget {
  const ClanGradientButton({
    super.key,
    required this.text,
    required this.icon,
    required this.onTap,
    this.loading = false,
  });

  final String text;
  final IconData icon;
  final VoidCallback? onTap;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null && !loading;
    return Opacity(
      opacity: enabled || loading ? 1 : 0.5,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: enabled ? onTap : null,
          child: Ink(
            height: 50,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              gradient: const LinearGradient(
                colors: [AppColors.accentViolet, Color(0xFFFF6B4A)],
              ),
              boxShadow: [
                BoxShadow(
                  color: AppColors.accentViolet.withValues(alpha: 0.35),
                  blurRadius: 14,
                  offset: const Offset(0, 5),
                ),
              ],
            ),
            child: Center(
              child: loading
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white),
                    )
                  : Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(icon, size: 18, color: Colors.white),
                        const SizedBox(width: 8),
                        Text(
                          text,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Warna medali peringkat 1-3 (null = tanpa medali).
Color? clanMedal(int rank) {
  switch (rank) {
    case 1:
      return heroGold;
    case 2:
      return const Color(0xFFB0BEC5);
    case 3:
      return const Color(0xFFCD7F32);
    default:
      return null;
  }
}

/// Glow bulat lembut buat latar kartu header.
class ClanGlow extends StatelessWidget {
  const ClanGlow({super.key, required this.color, required this.size});

  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(
            colors: [color.withValues(alpha: 0.16), color.withValues(alpha: 0)],
          ),
        ),
      ),
    );
  }
}

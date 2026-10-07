import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/firebase_config.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../data/models/chat_models.dart';
import '../../../providers.dart';
import '../../app_routes.dart';
import '../auth/login_screen.dart';
import '../chat/chat_screen.dart';
import '../download/downloads_screen.dart';

/// Halaman Pengaturan sendiri (dibuka dari ikon gear di pojok kanan atas
/// Profil). Isinya dulu tab "Pengaturan" di Profil, ditambah menu Download.
class ProfileSettingsScreen extends ConsumerStatefulWidget {
  const ProfileSettingsScreen({super.key});

  @override
  ConsumerState<ProfileSettingsScreen> createState() => _ProfileSettingsScreenState();
}

class _ProfileSettingsScreenState extends ConsumerState<ProfileSettingsScreen> {
  Future<bool> _openLogin() async {
    final ok = await Navigator.of(context).push<bool>(fadeRoute(const LoginScreen()));
    return ok == true;
  }

  Future<void> _openChat() async {
    if (!FirebaseConfig.ready) {
      await _openLogin();
      return;
    }
    if (ref.read(authRepositoryProvider).currentUser == null) {
      final ok = await _openLogin();
      if (!ok || !mounted) return;
    }
    if (!mounted) return;
    await Navigator.of(context).push<void>(fadeRoute(const ChatScreen()));
  }

  Future<void> _confirmSignOut() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surfaceDark,
        title: const Text('Keluar?', style: TextStyle(color: AppColors.textWhite)),
        content: const Text(
          'Kamu perlu masuk lagi untuk memakai Chat.',
          style: TextStyle(color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Batal')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Keluar')),
        ],
      ),
    );
    if (confirmed == true) await ref.read(authRepositoryProvider).signOut();
  }

  /// Cache gambar di memori benar-benar dikosongkan (cache disk cover tidak disentuh).
  void _clearCache() {
    final cache = PaintingBinding.instance.imageCache;
    cache.clear();
    cache.clearLiveImages();
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        const SnackBar(
          content: Text('Cache berhasil dibersihkan'),
          duration: Duration(seconds: 2),
          behavior: SnackBarBehavior.floating,
        ),
      );
  }

  String _displayName(User? user) {
    final name = user?.displayName;
    if (name != null && name.trim().isNotEmpty) return name.trim();
    final email = user?.email;
    if (email != null && email.contains('@')) return email.substring(0, email.indexOf('@'));
    return user == null ? 'Wibu Sejati' : 'Pengguna';
  }

  String _resolvedName(User? user, ChatProfile? profile, bool loading) {
    final zenime = profile?.username.trim() ?? '';
    if (zenime.isNotEmpty) return zenime;
    if (loading) return 'Pengguna Zenime';
    return _displayName(user);
  }

  @override
  Widget build(BuildContext context) {
    const sectionStyle = TextStyle(
      color: AppColors.accentViolet,
      fontSize: 12,
      fontWeight: FontWeight.w700,
    );
    final authUser = ref.watch(authUserProvider).valueOrNull;
    final user = (authUser != null && FirebaseConfig.ready) ? authUser : null;
    ChatProfile? profile;
    var profileLoading = false;
    if (user != null) {
      final async = ref.watch(chatProfileProvider(user.uid));
      profile = async.valueOrNull;
      profileLoading = async.isLoading;
    }
    final downloadCount = ref.watch(localStoreProvider.select((s) => s.downloads.length));

    return Scaffold(
      backgroundColor: AppColors.backgroundDark,
      appBar: AppBar(
        backgroundColor: AppColors.backgroundDark,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          onPressed: () => Navigator.of(context).maybePop(),
          tooltip: 'Kembali',
          icon: const Icon(Icons.arrow_back, color: AppColors.textWhite),
        ),
        title: const Text(
          'Pengaturan',
          style: TextStyle(
            color: AppColors.textWhite,
            fontSize: 18,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Akun Zenime', style: sectionStyle),
            const SizedBox(height: 10),
            if (user == null)
              SettingsItem(
                icon: Icons.login,
                title: 'Masuk',
                subtitle: 'Pakai akun Zenime yang sama untuk chat dan data lain',
                onTap: _openLogin,
              )
            else ...[
              SettingsItem(
                icon: Icons.forum_outlined,
                title: 'Chat Global',
                subtitle: 'Ngobrol bareng sesama pengguna Zenime',
                onTap: _openChat,
              ),
              const SizedBox(height: 10),
              SettingsItem(
                icon: Icons.workspace_premium_outlined,
                title: 'Premium',
                subtitle: '1080p, tanpa iklan, download offline, XP ×2',
                onTap: () => openPremium(context),
              ),
              const SizedBox(height: 10),
              SettingsItem(
                icon: Icons.monetization_on_outlined,
                title: 'ZCoin',
                subtitle: 'Cek saldo dan top up',
                onTap: () => openCoin(context),
              ),
              const SizedBox(height: 10),
              SettingsItem(
                icon: Icons.logout,
                title: 'Keluar',
                subtitle: _resolvedName(user, profile, profileLoading),
                onTap: _confirmSignOut,
              ),
            ],
            const SizedBox(height: 20),
            const Text('Download', style: sectionStyle),
            const SizedBox(height: 10),
            SettingsItem(
              icon: Icons.download_done,
              title: 'Download',
              subtitle: downloadCount == 0
                  ? 'Nonton offline, khusus Premium'
                  : '$downloadCount episode · nonton offline, khusus Premium',
              onTap: () =>
                  Navigator.of(context).push<void>(fadeRoute(const DownloadsScreen())),
            ),
            const SizedBox(height: 20),
            const Text('Penyimpanan & Cache', style: sectionStyle),
            const SizedBox(height: 10),
            SettingsItem(
              icon: Icons.cleaning_services_outlined,
              title: 'Bersihkan Cache Memori',
              subtitle: 'Mengosongkan cache cover dan metadata',
              onTap: _clearCache,
            ),
            const SizedBox(height: 20),
            const Text('Tentang Aplikasi', style: sectionStyle),
            const SizedBox(height: 10),
            const SettingsItem(
              icon: Icons.info_outline,
              title: 'Zenime v1.0',
              subtitle: 'Aplikasi streaming anime modern & Cuplix',
            ),
          ],
        ),
      ),
    );
  }
}

/// Port SettingsItem.
class SettingsItem extends StatelessWidget {
  const SettingsItem({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surfaceCard,
      borderRadius: AppShapes.card,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap ?? () {},
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: const BoxDecoration(
                  color: AppColors.surfaceDark,
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: AppColors.accentViolet, size: 20),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        color: AppColors.textWhite,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      subtitle,
                      style: const TextStyle(color: AppColors.textMuted, fontSize: 12),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

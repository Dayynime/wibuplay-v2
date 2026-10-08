import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../../core/firebase_config.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../data/models/account_models.dart';
import '../../../data/models/chat_models.dart';
import '../../../providers.dart';
import '../../app_routes.dart';
import '../../components/role_badges.dart';
import '../admin/admin_screen.dart';
import '../auth/login_screen.dart';
import '../chat/chat_screen.dart';
import '../download/downloads_screen.dart';
import 'profile_screen.dart' show ProfileAvatar;

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

  static const List<String> _qualities = ['1080p', '720p', '480p', '360p'];
  static const List<String> _bulan = [
    'Jan', 'Feb', 'Mar', 'Apr', 'Mei', 'Jun', 'Jul', 'Agu', 'Sep', 'Okt', 'Nov', 'Des',
  ];

  /// Port formatPremiumRemaining (SettingsViewModel.kt).
  String _premiumRemaining(String? expiresAtIso) {
    final at = DateTime.tryParse(expiresAtIso ?? '')?.toLocal();
    if (at == null) return 'Premium aktif';
    final daysLeft = at.difference(DateTime.now()).inDays;
    final date = '${at.day} ${_bulan[at.month - 1]} ${at.year}';
    if (at.isBefore(DateTime.now())) return 'Sudah berakhir';
    if (daysLeft == 0) return 'Aktif hingga $date (berakhir hari ini)';
    return 'Aktif hingga $date (sisa $daysLeft hari)';
  }

  @override
  Widget build(BuildContext context) {
    final authUser = ref.watch(authUserProvider).valueOrNull;
    final user = (authUser != null && FirebaseConfig.ready) ? authUser : null;
    ChatProfile? profile;
    var profileLoading = false;
    PremiumStatus? premium;
    if (user != null) {
      final async = ref.watch(chatProfileProvider(user.uid));
      profile = async.valueOrNull;
      profileLoading = async.isLoading;
      premium = ref.watch(premiumStatusProvider(user.uid)).valueOrNull;
    }
    // Punya role (developer/admin/moderator)? Cuma buat memunculkan tombol Panel
    // Admin; role dicek ulang di server saat panelnya dibuka.
    final isStaff =
        user != null && ref.watch(roleInfoProvider(user.uid)).valueOrNull != null;
    final downloadCount = ref.watch(localStoreProvider.select((s) => s.downloads.length));
    final store = ref.watch(localStoreProvider);

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
            // ------------------------------------------------------------ Akun
            const _GroupLabel('Akun'),
            if (user == null)
              _GroupCard(
                children: [
                  Padding(
                    padding: const EdgeInsets.all(18),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Row(
                          children: [
                            _IconChip(icon: Icons.account_circle_outlined),
                            SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Belum Masuk',
                                    style: TextStyle(
                                      color: AppColors.textWhite,
                                      fontSize: 15,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  Text(
                                    'Pakai akun Zenime yang sama untuk chat dan data lain',
                                    style: TextStyle(color: AppColors.textMuted, fontSize: 12),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),
                        SizedBox(
                          width: double.infinity,
                          height: 46,
                          child: FilledButton.icon(
                            onPressed: _openLogin,
                            style: FilledButton.styleFrom(
                              backgroundColor: AppColors.accentViolet,
                              shape: const StadiumBorder(),
                            ),
                            icon: const Icon(Icons.login, size: 18),
                            label: const Text('Masuk',
                                style: TextStyle(fontWeight: FontWeight.w700)),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              )
            else
              _GroupCard(
                children: [
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      children: [
                        ProfileAvatar(
                          url: (profile?.avatarUrl ?? '').isNotEmpty
                              ? profile!.avatarUrl
                              : user.photoURL,
                          seed: user.uid,
                          label: _resolvedName(user, profile, profileLoading),
                          size: 52,
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _resolvedName(user, profile, profileLoading),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: AppColors.textWhite,
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              Text(
                                user.email ?? '',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: AppColors.textMuted,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Material(
                          color: AppColors.surfaceDark,
                          borderRadius: BorderRadius.circular(11),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(11),
                            onTap: _confirmSignOut,
                            child: const Padding(
                              padding: EdgeInsets.all(10),
                              child: Icon(Icons.logout, color: AppColors.textMuted, size: 18),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const _RowDivider(),
                  _SettingsRow(
                    leading: const _IconChip(icon: Icons.star_outline),
                    title: 'Premium',
                    titleBadge: _StatusChip(active: premium?.isPremium == true),
                    subtitle: premium?.isPremium == true
                        ? _premiumRemaining(premium?.expiresAt)
                        : 'Lihat paket & aktifkan Premium',
                    trailing: const Icon(Icons.chevron_right, color: AppColors.textMuted),
                    onTap: () => openPremium(context),
                  ),
                  const _RowDivider(),
                  _SettingsRow(
                    leading: ClipRRect(
                      borderRadius: BorderRadius.circular(11),
                      child: Image.asset(
                        'assets/images/ic_zcoin_badge.png',
                        width: 36,
                        height: 36,
                        errorBuilder: (_, __, ___) =>
                            const _IconChip(icon: Icons.monetization_on_outlined),
                      ),
                    ),
                    title: 'ZCoin',
                    subtitle: 'Top up & lihat saldo ZCoin',
                    trailing: const Icon(Icons.chevron_right, color: AppColors.textMuted),
                    onTap: () => openCoin(context),
                  ),
                  const _RowDivider(),
                  _SettingsRow(
                    leading: const _IconChip(icon: Icons.forum_outlined),
                    title: 'Chat Global',
                    subtitle: 'Ngobrol bareng sesama pengguna Zenime',
                    trailing: const Icon(Icons.chevron_right, color: AppColors.textMuted),
                    onTap: _openChat,
                  ),
                  if (isStaff) ...[
                    const _RowDivider(),
                    _SettingsRow(
                      leading: const _IconChip(icon: Icons.shield_outlined),
                      title: 'Panel Admin',
                      subtitle: 'Kelola role, ban, dan moderasi',
                      trailing: const Icon(Icons.chevron_right, color: AppColors.textMuted),
                      onTap: () => Navigator.of(context)
                          .push<void>(fadeRoute(const AdminScreen())),
                    ),
                  ],
                ],
              ),

            // ------------------------------------------------------- Pemutaran
            const SizedBox(height: 22),
            const _GroupLabel('Pemutaran Video'),
            _GroupCard(
              children: [
                _SettingsRow(
                  leading: const _IconChip(icon: Icons.high_quality_outlined),
                  title: 'Kualitas Video Default',
                  subtitle: 'Kualitas utama saat memuat episode',
                  trailing: PopupMenuButton<String>(
                    tooltip: 'Kualitas video default',
                    color: AppColors.surfaceCard,
                    onSelected: (q) => ref.read(localStoreProvider).setDefaultQuality(q),
                    itemBuilder: (_) => [
                      for (final q in _qualities)
                        PopupMenuItem<String>(
                          value: q,
                          child: Text(
                            q,
                            style: TextStyle(
                              color: AppColors.textWhite,
                              fontWeight: q == store.defaultQuality
                                  ? FontWeight.w800
                                  : FontWeight.w400,
                            ),
                          ),
                        ),
                    ],
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: AppColors.surfaceDark,
                        borderRadius: BorderRadius.circular(9),
                        border: Border.all(color: const Color(0x1FFFFFFF)),
                      ),
                      child: Text(
                        store.defaultQuality,
                        style: const TextStyle(
                          color: AppColors.accentViolet,
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                ),
                const _RowDivider(),
                _SettingsRow(
                  leading: const _IconChip(icon: Icons.fast_forward),
                  title: 'Lewati Intro Otomatis',
                  subtitle: 'Lompat ke detik 90 pas episode dibuka dari awal',
                  trailing: _Toggle(
                    value: store.autoSkipIntro,
                    onChanged: (v) => ref.read(localStoreProvider).setAutoSkipIntro(v),
                  ),
                ),
                const _RowDivider(),
                _SettingsRow(
                  leading: const _IconChip(icon: Icons.skip_next),
                  title: 'Auto-Lanjut Episode (Outro)',
                  subtitle: 'Lanjut ke episode berikutnya otomatis pas mepet abis',
                  trailing: _Toggle(
                    value: store.autoSkipOutro,
                    onChanged: (v) => ref.read(localStoreProvider).setAutoSkipOutro(v),
                  ),
                ),
              ],
            ),

            // --------------------------------------------------------- Download
            const SizedBox(height: 22),
            const _GroupLabel('Download'),
            SettingsItem(
              icon: Icons.download_done,
              title: 'Download',
              subtitle: downloadCount == 0
                  ? 'Nonton offline, download khusus Premium'
                  : '$downloadCount episode · nonton offline, download khusus Premium',
              onTap: () =>
                  Navigator.of(context).push<void>(fadeRoute(const DownloadsScreen())),
            ),

            // ------------------------------------------------------------ Cache
            const SizedBox(height: 22),
            const _GroupLabel('Penyimpanan & Cache'),
            SettingsItem(
              icon: Icons.cleaning_services_outlined,
              title: 'Bersihkan Cache Memori',
              subtitle: 'Mengosongkan cache cover dan metadata',
              onTap: _clearCache,
            ),

            // ----------------------------------------------------------- Tentang
            const SizedBox(height: 22),
            const _GroupLabel('Tentang Aplikasi'),
            _GroupCard(
              children: [
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(16),
                        child: Image.asset(
                          'assets/images/logo.jpg',
                          width: 56,
                          height: 56,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => const SizedBox(
                            width: 56,
                            height: 56,
                            child: _IconChip(icon: Icons.play_circle_outline),
                          ),
                        ),
                      ),
                      const SizedBox(width: 14),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Zenime',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: AppColors.textWhite,
                                fontSize: 16,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            SizedBox(height: 2),
                            Text(
                              'Nonton Anime, Tenang & Modern',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(color: AppColors.textMuted, fontSize: 12),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 10),
                      FutureBuilder<PackageInfo>(
                        future: PackageInfo.fromPlatform(),
                        builder: (context, snap) => Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                          decoration: BoxDecoration(
                            color: AppColors.accentViolet.withValues(alpha: 0.14),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            'v${snap.data?.version ?? '2.3'}',
                            style: const TextStyle(
                              color: AppColors.accentViolet,
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const _RowDivider(),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _DotLine(
                        text: 'Flutter · Material 3 · video_player',
                        color: AppColors.textMuted,
                      ),
                      SizedBox(height: 6),
                      _DotLine(
                        text: 'Powered by Dayynime v5 API & Direct MP4 Streaming',
                        color: AppColors.accentViolet,
                      ),
                    ],
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

class _GroupLabel extends StatelessWidget {
  const _GroupLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Text(
          text,
          style: const TextStyle(
            color: AppColors.accentViolet,
            fontSize: 12,
            fontWeight: FontWeight.w700,
          ),
        ),
      );
}

class _GroupCard extends StatelessWidget {
  const _GroupCard({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Material(
        color: AppColors.surfaceCard,
        borderRadius: AppShapes.card,
        clipBehavior: Clip.antiAlias,
        child: Column(children: children),
      );
}

class _RowDivider extends StatelessWidget {
  const _RowDivider();

  @override
  Widget build(BuildContext context) =>
      Container(height: 1, margin: const EdgeInsets.symmetric(horizontal: 16), color: const Color(0x14FFFFFF));
}

class _IconChip extends StatelessWidget {
  const _IconChip({required this.icon});

  final IconData icon;

  @override
  Widget build(BuildContext context) => Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: AppColors.surfaceDark,
          borderRadius: BorderRadius.circular(11),
        ),
        child: Icon(icon, color: AppColors.accentViolet, size: 19),
      );
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.active});

  final bool active;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(
          color: active
              ? AppColors.accentViolet.withValues(alpha: 0.18)
              : AppColors.surfaceDark,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          active ? 'AKTIF' : 'BELUM AKTIF',
          style: TextStyle(
            color: active ? AppColors.accentViolet : AppColors.textMuted,
            fontSize: 10,
            fontWeight: FontWeight.w800,
          ),
        ),
      );
}

class _Toggle extends StatelessWidget {
  const _Toggle({required this.value, required this.onChanged});

  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) => Switch(
        value: value,
        onChanged: onChanged,
        activeThumbColor: Colors.white,
        activeTrackColor: AppColors.accentViolet,
      );
}

class _DotLine extends StatelessWidget {
  const _DotLine({required this.text, required this.color});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) => Row(
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.7),
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(text, style: TextStyle(color: color, fontSize: 11)),
          ),
        ],
      );
}

/// Satu baris pengaturan di dalam kartu grup: ikon kiri, judul (+ badge
/// opsional) dan subjudul, lalu widget kanan (switch, menu, chevron).
class _SettingsRow extends StatelessWidget {
  const _SettingsRow({
    required this.leading,
    required this.title,
    required this.subtitle,
    this.titleBadge,
    this.trailing,
    this.onTap,
  });

  final Widget leading;
  final String title;
  final String subtitle;
  final Widget? titleBadge;
  final Widget? trailing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            leading,
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: AppColors.textWhite,
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      if (titleBadge != null) ...[
                        const SizedBox(width: 8),
                        titleBadge!,
                      ],
                    ],
                  ),
                  Text(
                    subtitle,
                    style: const TextStyle(color: AppColors.textMuted, fontSize: 12),
                  ),
                ],
              ),
            ),
            if (trailing != null) ...[
              const SizedBox(width: 8),
              trailing!,
            ],
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

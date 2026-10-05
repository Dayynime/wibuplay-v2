import 'dart:math' as math;

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../data/local/entities.dart';
import '../../../data/models/chat_models.dart';
import '../../../core/firebase_config.dart';
import '../../../providers.dart';
import '../../app_routes.dart';
import '../../components/cards.dart';
import '../../components/common_components.dart';
import '../../components/game_badges.dart';
import '../../components/net_image.dart';
import '../auth/login_screen.dart';
import '../chat/chat_screen.dart';
import 'my_xp_card.dart';
import 'profile_controller.dart';

/// Port ProfileScreen.kt: header pengguna + tab Favorit / Riwayat / Pengaturan.
class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({
    super.key,
    required this.onAnimeClick,
    required this.onWatchEpisode,
  });

  final ValueChanged<String> onAnimeClick;
  final void Function(String movieId, String episodeId) onWatchEpisode;

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  static const List<String> _tabs = ['Favorit', 'Riwayat', 'Pengaturan'];
  static const double _hGap = 10;
  static const double _vGap = 14;
  static const double _minCell = 105;

  int _selectedTab = 0;

  ProfileController get _controller => ref.read(profileControllerProvider);

  @override
  Widget build(BuildContext context) {
    final favorites = ref.watch(profileFavoritesProvider);
    final history = ref.watch(profileHistoryProvider);
    final user = ref.watch(authUserProvider).valueOrNull;

    // Material (bukan ColoredBox) supaya efek ripple InkWell tab terlihat.
    return Material(
      color: AppColors.backgroundDark,
      child: SafeArea(
        bottom: false,
        child: Column(
          children: [
            _buildHeader(favorites.length, history.length, user),
            if (user != null && FirebaseConfig.ready) ...[
              MyXpCard(firebaseUid: user.uid),
              const SizedBox(height: 14),
            ],
            _buildTabs(),
            const SizedBox(height: 12),
            Expanded(child: _buildTabContent(favorites, history)),
          ],
        ),
      ),
    );
  }

  // ----------------------------------------------------------------- header

  Widget _buildHeader(int favoriteCount, int historyCount, User? user) {
    // Badge Premium asli dari server (bukan teks tetap seperti sebelumnya).
    final premium = user != null &&
        FirebaseConfig.ready &&
        (ref.watch(premiumProvider(user.uid)).valueOrNull ?? false);
    // Nama + foto dari profil Zenime (chat_profiles), sama dengan Beranda dan
    // Chat. Data Google hanya cadangan kalau profil Zenime belum ada; selama
    // masih dimuat tidak ditampilkan supaya nama Google tidak sempat berkedip.
    final profile = _zenimeProfile(user);
    final name = _resolvedName(user, profile.data, profile.loading);
    final avatarUrl = _resolvedAvatar(user, profile.data, profile.loading);
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Row(
        children: [
          Container(
            width: 62,
            height: 62,
            decoration: const BoxDecoration(
              color: AppColors.accentViolet,
              shape: BoxShape.circle,
            ),
            clipBehavior: Clip.antiAlias,
            child: avatarUrl != null
                ? NetImage(avatarUrl)
                : const Icon(Icons.person_outline, color: AppColors.textWhite, size: 34),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppColors.textWhite,
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 3),
                Row(
                  children: [
                    if (premium) ...[
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: AppColors.surfaceDark,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            PremiumCheckBadge(size: 11),
                            SizedBox(width: 3),
                            Text(
                              'Premium',
                              style: TextStyle(
                                color: Color(0xFF3897F0),
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                    ],
                    Flexible(
                      child: Text(
                        '$favoriteCount Favorit • $historyCount Ditonton',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: AppColors.textMuted, fontSize: 11),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // -------------------------------------------------------------------- tab

  /// Port TabRow: 3 tab sama lebar, indikator 3dp berwarna aksen, tanpa divider.
  Widget _buildTabs() {
    return SizedBox(
      height: 48,
      child: Stack(
        children: [
          Row(
            children: [
              for (var i = 0; i < _tabs.length; i++)
                Expanded(
                  child: InkWell(
                    onTap: () => setState(() => _selectedTab = i),
                    child: Center(
                      child: Text(
                        _tabs[i],
                        style: TextStyle(
                          color: _selectedTab == i
                              ? AppColors.textWhite
                              : AppColors.textMuted,
                          fontSize: 14,
                          fontWeight:
                              _selectedTab == i ? FontWeight.w700 : FontWeight.w500,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
          Positioned.fill(
            child: IgnorePointer(
              child: AnimatedAlign(
                alignment: Alignment(_selectedTab - 1.0, 1),
                duration: const Duration(milliseconds: 250),
                curve: Curves.easeOut,
                child: FractionallySizedBox(
                  widthFactor: 1 / _tabs.length,
                  child: const SizedBox(
                    height: 3,
                    child: ColoredBox(color: AppColors.accentViolet),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTabContent(List<FavoriteEntity> favorites, List<WatchHistoryEntity> history) {
    switch (_selectedTab) {
      case 0:
        return _buildFavorites(favorites);
      case 1:
        return _buildHistory(history);
      default:
        return _buildSettings();
    }
  }

  // ---------------------------------------------------------------- favorit

  Widget _buildFavorites(List<FavoriteEntity> favorites) {
    if (favorites.isEmpty) {
      return const Center(
        child: EmptyState(
          title: 'Belum Ada Favorit',
          subtitle: "Tekan tombol '+' pada anime yang kamu sukai untuk menyimpannya di sini",
          icon: Icons.favorite_border,
        ),
      );
    }
    return LayoutBuilder(
      builder: (context, c) {
        // Setara GridCells.Adaptive(minSize = 105.dp)
        final avail = c.maxWidth - 32;
        final count = math.max(1, ((avail + _hGap) / (_minCell + _hGap)).floor());
        final cell = (avail - _hGap * (count - 1)) / count;
        final extent = cell * 1.5 + 62;
        return GridView.builder(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 135),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: count,
            mainAxisSpacing: _vGap,
            crossAxisSpacing: _hGap,
            mainAxisExtent: extent,
          ),
          itemCount: favorites.length,
          itemBuilder: (context, i) {
            final fav = favorites[i];
            return Stack(
              key: ValueKey(fav.id),
              children: [
                AnimePosterCard(
                  anime: fav.toAnimeItem(),
                  width: cell,
                  onTap: () => widget.onAnimeClick(fav.id),
                ),
                // Tombol hapus favorit (kiri atas poster; badge status ada di kanan atas).
                Positioned(
                  top: 6,
                  left: 6,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => _confirmRemoveFavorite(fav),
                    child: Container(
                      width: 28,
                      height: 28,
                      decoration: const BoxDecoration(
                        color: Color(0xB31E1B2E),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.delete_outline,
                        color: AppColors.errorRed,
                        size: 17,
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _confirmRemoveFavorite(FavoriteEntity fav) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surfaceDark,
        surfaceTintColor: Colors.transparent,
        title: const Text(
          'Hapus dari Favorit?',
          style: TextStyle(color: AppColors.textWhite),
        ),
        content: Text(
          '"${fav.title}" akan dihapus dari daftar favoritmu.',
          style: const TextStyle(color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Batal', style: TextStyle(color: AppColors.textSecondary)),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: FilledButton.styleFrom(backgroundColor: AppColors.errorRed),
            child: const Text('Hapus', style: TextStyle(color: AppColors.textWhite)),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await _controller.removeFavorite(fav.id);
    }
  }

  // --------------------------------------------------------------- riwayat

  Widget _buildHistory(List<WatchHistoryEntity> history) {
    if (history.isEmpty) {
      return const Center(
        child: EmptyState(
          title: 'Riwayat Masih Kosong',
          subtitle:
              'Anime yang kamu tonton akan otomatis tercatat dan tersimpan progresnya di sini',
          icon: Icons.history,
        ),
      );
    }
    final user = ref.watch(authUserProvider).valueOrNull;
    final profile = _zenimeProfile(user);
    final name = _resolvedName(user, profile.data, profile.loading);
    final avatarUrl = _resolvedAvatar(user, profile.data, profile.loading);
    final premium = user != null &&
        FirebaseConfig.ready &&
        (ref.watch(premiumProvider(user.uid)).valueOrNull ?? false);

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 8, 8),
          child: Row(
            children: [
              const Icon(Icons.history, color: AppColors.accentViolet, size: 20),
              const SizedBox(width: 8),
              const Text(
                'Riwayat Tontonan',
                style: TextStyle(
                  color: AppColors.textWhite,
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '${history.length}',
                style: const TextStyle(color: AppColors.textMuted, fontSize: 12),
              ),
              const Spacer(),
              IconButton(
                onPressed: _confirmClearHistory,
                tooltip: 'Hapus Semua Riwayat',
                icon: const Icon(Icons.delete_sweep, color: AppColors.accentViolet),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 6, 16, 135),
            itemCount: history.length,
            separatorBuilder: (context, i) => const SizedBox(height: 22),
            itemBuilder: (context, i) {
              final h = history[i];
              return _WatchHistoryRow(
                key: ValueKey(h.id),
                history: h,
                username: name,
                avatarUrl: avatarUrl,
                isPremium: premium,
                onPlay: () => widget.onWatchEpisode(h.movieId, h.episodeId),
                onDelete: () => _controller.deleteHistory(h.id),
              );
            },
          ),
        ),
      ],
    );
  }

  Future<void> _confirmClearHistory() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surfaceDark,
        surfaceTintColor: Colors.transparent,
        title: const Text(
          'Hapus Semua Riwayat?',
          style: TextStyle(color: AppColors.textWhite),
        ),
        content: const Text(
          'Semua riwayat tontonan dan posisi pemutaran akan dihapus dari perangkat.',
          style: TextStyle(color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Batal', style: TextStyle(color: AppColors.textSecondary)),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: FilledButton.styleFrom(backgroundColor: AppColors.errorRed),
            child: const Text('Hapus', style: TextStyle(color: AppColors.textWhite)),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await _controller.clearAllHistory();
    }
  }

  // ------------------------------------------------------------ pengaturan

  Widget _buildSettings() {
    const sectionStyle = TextStyle(
      color: AppColors.accentViolet,
      fontSize: 12,
      fontWeight: FontWeight.w700,
    );
    final user = ref.watch(authUserProvider).valueOrNull;
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      children: [
        const Text('Akun Zenime', style: sectionStyle),
        const SizedBox(height: 10),
        if (user == null)
          _SettingsItem(
            icon: Icons.login,
            title: 'Masuk',
            subtitle: 'Pakai akun Zenime yang sama untuk chat dan data lain',
            onTap: _openLogin,
          )
        else ...[
          _SettingsItem(
            icon: Icons.forum_outlined,
            title: 'Chat Global',
            subtitle: 'Ngobrol bareng sesama pengguna Zenime',
            onTap: _openChat,
          ),
          const SizedBox(height: 10),
          _SettingsItem(
            icon: Icons.workspace_premium_outlined,
            title: 'Premium',
            subtitle: '1080p, tanpa iklan, download offline, XP ×2',
            onTap: () => openPremium(context),
          ),
          const SizedBox(height: 10),
          _SettingsItem(
            icon: Icons.monetization_on_outlined,
            title: 'ZCoin',
            subtitle: 'Cek saldo dan top up',
            onTap: () => openCoin(context),
          ),
          const SizedBox(height: 10),
          _SettingsItem(
            icon: Icons.logout,
            title: 'Keluar',
            subtitle: _resolvedName(
              user,
              _zenimeProfile(user).data,
              _zenimeProfile(user).loading,
            ),
            onTap: _confirmSignOut,
          ),
        ],
        const SizedBox(height: 20),
        const Text('Penyimpanan & Cache', style: sectionStyle),
        const SizedBox(height: 10),
        _SettingsItem(
          icon: Icons.cleaning_services_outlined,
          title: 'Bersihkan Cache Memori',
          subtitle: 'Mengosongkan cache cover dan metadata',
          onTap: _clearCache,
        ),
        const SizedBox(height: 20),
        const Text('Tentang Aplikasi', style: sectionStyle),
        const SizedBox(height: 10),
        const _SettingsItem(
          icon: Icons.info_outline,
          title: 'Zenime v1.0',
          subtitle: 'Aplikasi streaming anime modern & Cuplix',
        ),
      ],
    );
  }

  /// Profil Zenime (chat_profiles) user yang login; loading = masih dimuat.
  ({ChatProfile? data, bool loading}) _zenimeProfile(User? user) {
    if (user == null || !FirebaseConfig.ready) return (data: null, loading: false);
    final async = ref.watch(chatProfileProvider(user.uid));
    return (data: async.valueOrNull, loading: async.isLoading);
  }

  String _resolvedName(User? user, ChatProfile? profile, bool loading) {
    final zenime = profile?.username.trim() ?? '';
    if (zenime.isNotEmpty) return zenime;
    if (loading) return 'Pengguna Zenime';
    return _displayName(user);
  }

  String? _resolvedAvatar(User? user, ChatProfile? profile, bool loading) {
    final zenime = profile?.avatarUrl ?? '';
    if (zenime.isNotEmpty) return zenime;
    if (loading) return null;
    final google = user?.photoURL ?? '';
    return google.isNotEmpty ? google : null;
  }

  String _displayName(User? user) {
    final name = user?.displayName;
    if (name != null && name.trim().isNotEmpty) return name.trim();
    final email = user?.email;
    if (email != null && email.contains('@')) return email.substring(0, email.indexOf('@'));
    return user == null ? 'Wibu Sejati' : 'Pengguna';
  }

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

  /// Di Kotlin tombol ini hanya menampilkan Toast. Di sini cache gambar di
  /// memori benar-benar dikosongkan (cache disk cover tidak disentuh).
  void _clearCache() {
    final cache = PaintingBinding.instance.imageCache;
    cache.clear();
    cache.clearLiveImages();
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger == null) return;
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: const Text('Cache berhasil dibersihkan'),
          duration: const Duration(seconds: 2),
          behavior: SnackBarBehavior.floating,
          margin: EdgeInsets.fromLTRB(
            20,
            0,
            20,
            100 + MediaQuery.paddingOf(context).bottom,
          ),
        ),
      );
  }
}

/// Baris riwayat flat ala feed Zenime: avatar mini + nama + waktu relatif di
/// atas, thumbnail + judul/episode, lalu ikon play + progress bar + label waktu.
class _WatchHistoryRow extends StatelessWidget {
  const _WatchHistoryRow({
    super.key,
    required this.history,
    required this.username,
    required this.avatarUrl,
    required this.isPremium,
    required this.onPlay,
    required this.onDelete,
  });

  final WatchHistoryEntity history;
  final String username;
  final String? avatarUrl;
  final bool isPremium;
  final VoidCallback onPlay;
  final VoidCallback onDelete;

  static String _duration(int ms) {
    if (ms <= 0) return '00:00';
    final total = ms ~/ 1000;
    final h = total ~/ 3600;
    final m = (total % 3600) ~/ 60;
    final sec = total % 60;
    String two(int n) => n.toString().padLeft(2, '0');
    return h > 0 ? '$h:${two(m)}:${two(sec)}' : '${two(m)}:${two(sec)}';
  }

  static String _relative(int ms) {
    final diff = DateTime.now().millisecondsSinceEpoch - ms;
    final d = diff < 0 ? 0 : diff;
    final minutes = d ~/ 60000;
    final hours = d ~/ 3600000;
    final days = d ~/ 86400000;
    if (minutes < 1) return 'Baru saja';
    if (minutes < 60) return '$minutes menit lalu';
    if (hours < 24) return '$hours jam lalu';
    if (days < 30) return '$days hari lalu';
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'Mei', 'Jun',
      'Jul', 'Agu', 'Sep', 'Okt', 'Nov', 'Des',
    ];
    final dt = DateTime.fromMillisecondsSinceEpoch(ms);
    return '${dt.day} ${months[dt.month - 1]} ${dt.year}';
  }

  @override
  Widget build(BuildContext context) {
    final title = history.episodeTitle.toLowerCase();
    final epLabel = history.episodeTitle.trim().isEmpty
        ? 'Episode ${history.episodeIndex}'
        : (title.contains('episode') || title.contains('ep'))
            ? history.episodeTitle
            : 'Episode ${history.episodeIndex}';

    return InkWell(
      onTap: onPlay,
      borderRadius: BorderRadius.circular(8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Baris atas: avatar mini + nama + badge premium, waktu di kanan.
          Row(
            children: [
              UserAvatar(username: username, url: avatarUrl, size: 28),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  username,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppColors.textWhite,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              if (isPremium) ...[
                const SizedBox(width: 4),
                const PremiumCheckBadge(size: 14),
              ],
              const Spacer(),
              Text(
                _relative(history.lastWatchedTime),
                style: const TextStyle(color: Color(0x73FFFFFF), fontSize: 11),
              ),
              const SizedBox(width: 4),
              InkWell(
                onTap: onDelete,
                customBorder: const CircleBorder(),
                child: const Padding(
                  padding: EdgeInsets.all(4),
                  child: Icon(Icons.delete_outline, color: AppColors.textMuted, size: 18),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          // Thumbnail + judul/episode.
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: SizedBox(
                  width: 72,
                  height: 72,
                  child: ColoredBox(
                    color: AppColors.surfaceDark,
                    child: NetImage(history.moviePoster),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        history.movieTitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: AppColors.textWhite,
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        epLabel,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Color(0x99FFFFFF),
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          // Ikon play + progress bar + label waktu.
          Row(
            children: [
              Container(
                width: 26,
                height: 26,
                decoration: const BoxDecoration(
                  color: Color(0x14FFFFFF),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.play_arrow, color: AppColors.textWhite, size: 15),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(2),
                  child: SizedBox(
                    height: 3,
                    child: LinearProgressIndicator(
                      value: history.progressFraction,
                      color: AppColors.accentViolet,
                      backgroundColor: const Color(0x26FFFFFF),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Text(
                '${_duration(history.playbackPositionMs)} / ${_duration(history.durationMs)}',
                maxLines: 1,
                style: const TextStyle(color: Color(0x80FFFFFF), fontSize: 10),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Port SettingsItem.
class _SettingsItem extends StatelessWidget {
  const _SettingsItem({
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

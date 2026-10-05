import 'dart:math' as math;

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../data/local/entities.dart';
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
            child: (user?.photoURL != null && user!.photoURL!.isNotEmpty)
                ? NetImage(user.photoURL!)
                : const Icon(Icons.person_outline, color: AppColors.textWhite, size: 34),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _displayName(user),
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
            return AnimePosterCard(
              key: ValueKey(fav.id),
              anime: fav.toAnimeItem(),
              width: cell,
              onTap: () => widget.onAnimeClick(fav.id),
            );
          },
        );
      },
    );
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
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '${history.length} Riwayat Tontonan',
                style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
              ),
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: _confirmClearHistory,
                child: const Padding(
                  padding: EdgeInsets.all(4),
                  child: Text(
                    'Hapus Semua',
                    style: TextStyle(
                      color: AppColors.errorRed,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 6, 16, 135),
            itemCount: history.length,
            separatorBuilder: (context, i) => const SizedBox(height: 10),
            itemBuilder: (context, i) {
              final h = history[i];
              return _WatchHistoryRow(
                key: ValueKey(h.id),
                history: h,
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
            icon: Icons.logout,
            title: 'Keluar',
            subtitle: _displayName(user),
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

/// Port WatchHistoryRowItem.
class _WatchHistoryRow extends StatelessWidget {
  const _WatchHistoryRow({
    super.key,
    required this.history,
    required this.onPlay,
    required this.onDelete,
  });

  final WatchHistoryEntity history;
  final VoidCallback onPlay;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final title = history.episodeTitle.toLowerCase();
    final epLabel = (title.contains('episode') || title.contains('ep'))
        ? history.episodeTitle
        : 'Episode ${history.episodeIndex}';
    final percent = (history.progressFraction * 100).toInt();
    final progressLabel = percent > 0 ? '$epLabel • $percent%' : epLabel;

    return Material(
      color: AppColors.surfaceCard,
      borderRadius: AppShapes.card,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onPlay,
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Row(
            children: [
              // Thumbnail + bar progres
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: SizedBox(
                  width: 90,
                  height: 60,
                  child: ColoredBox(
                    color: AppColors.surfaceDark,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        NetImage(history.moviePoster),
                        Positioned(
                          left: 0,
                          right: 0,
                          bottom: 0,
                          height: 3,
                          child: ColoredBox(
                            color: AppColors.surfaceElevated,
                            child: Align(
                              alignment: Alignment.centerLeft,
                              child: FractionallySizedBox(
                                widthFactor: history.progressFraction,
                                heightFactor: 1,
                                child: const ColoredBox(color: AppColors.accentViolet),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      history.movieTitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppColors.textWhite,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      progressLabel,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppColors.accentViolet,
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                onPressed: onDelete,
                tooltip: 'Hapus',
                icon: const Icon(Icons.delete_outline, color: AppColors.textMuted, size: 20),
              ),
            ],
          ),
        ),
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

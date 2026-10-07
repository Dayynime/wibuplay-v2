import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/error_message.dart';
import '../../../core/firebase_config.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../data/local/entities.dart';
import '../../../data/models/chat_models.dart';
import '../../../data/models/comment_models.dart';
import '../../../data/repository/profile_image_uploader.dart';
import '../../../providers.dart';
import '../../app_routes.dart';
import '../../components/cards.dart';
import '../../components/common_components.dart';
import '../../components/game_badges.dart';
import '../../components/net_image.dart';
import '../../components/role_badges.dart';
import '../auth/login_screen.dart';
import '../clan/clan_browse_screen.dart';
import 'settings_screen.dart';
import '../comic/comic_profile_section.dart';
import '../friends/friends_screen.dart';
import '../xp/xp_leaderboard_screen.dart';
import 'my_xp_card.dart';
import 'profile_controller.dart';

/// Profil Saya ala Zenime: banner full-bleed menyatu dengan avatar, identitas
/// + badge (level, clan, role) di bawah avatar, stat row 4 kolom, tombol pill
/// Clan / Leaderboard, CTA Edit Profil, lalu tab Semua / Favorit / Komentar /
/// Riwayat / Pengaturan.
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
  static const List<String> _tabs = [
    'Semua',
    'Favorit',
    'Komentar',
    'Riwayat',
  ];

  int _selectedTab = 0;

  ProfileController get _controller => ref.read(profileControllerProvider);

  @override
  Widget build(BuildContext context) {
    final favorites = ref.watch(profileFavoritesProvider);
    final history = ref.watch(profileHistoryProvider);
    final authUser = ref.watch(authUserProvider).valueOrNull;
    final user = (authUser != null && FirebaseConfig.ready) ? authUser : null;

    final premium =
        user != null && (ref.watch(premiumProvider(user.uid)).valueOrNull ?? false);
    final profile = _zenimeProfile(user);
    final name = _resolvedName(user, profile.data, profile.loading);
    final avatarUrl = _resolvedAvatar(user, profile.data, profile.loading);

    // Material (bukan ColoredBox) supaya efek ripple InkWell tab terlihat.
    return Material(
      color: AppColors.backgroundDark,
      child: SingleChildScrollView(
        padding: const EdgeInsets.only(bottom: 135),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildHero(
              user: user,
              profile: profile.data,
              name: name,
              avatarUrl: avatarUrl,
              premium: premium,
              favorites: favorites,
              history: history,
            ),
            const SizedBox(height: 8),
            _buildTabs(),
            const SizedBox(height: 16),
            _buildTabContent(favorites, history, user, premium, name, avatarUrl),
          ],
        ),
      ),
    );
  }

  // ------------------------------------------------------------------- hero

  static bool _has(String? s) => s != null && s.isNotEmpty;

  /// Banner full-bleed + avatar + identitas + stat + tombol, satu kesatuan.
  /// Gambar banner otomatis mengikuti tinggi isi (Positioned.fill di Stack).
  Widget _buildHero({
    required User? user,
    required ChatProfile? profile,
    required String name,
    required String? avatarUrl,
    required bool premium,
    required List<FavoriteEntity> favorites,
    required List<WatchHistoryEntity> history,
  }) {
    final uid = user?.uid ?? '';

    // Banner: foto custom (khusus Premium) -> poster favorit pertama ->
    // poster riwayat pertama -> warna solid.
    String? backdrop;
    if (premium && _has(profile?.bannerUrl)) {
      backdrop = profile!.bannerUrl;
    } else if (favorites.isNotEmpty && _has(favorites.first.posterUrl)) {
      backdrop = favorites.first.posterUrl;
    } else if (history.isNotEmpty && _has(history.first.moviePoster)) {
      backdrop = history.first.moviePoster;
    }

    final level = uid.isEmpty ? 1 : (ref.watch(myXpProvider(uid)).valueOrNull?.level ?? 1);
    final clanTag = uid.isEmpty ? null : ref.watch(userClanTagProvider(uid)).valueOrNull;
    final commentCount =
        uid.isEmpty ? 0 : (ref.watch(myCommentCountProvider(uid)).valueOrNull ?? 0);
    final uniqueAnime = history.map((h) => h.movieId).toSet().length;
    final topPad = MediaQuery.paddingOf(context).top;
    final incomingRequests =
        uid.isEmpty ? 0 : (ref.watch(incomingFriendRequestsProvider).valueOrNull ?? 0);

    return Stack(
      children: [
        Positioned.fill(
          child: _has(backdrop)
              ? NetImage(backdrop!)
              : const ColoredBox(color: AppColors.surfaceVariantDark),
        ),
        const Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Color(0x26000000),
                  Color(0x73000000),
                  AppColors.backgroundDark,
                ],
              ),
            ),
          ),
        ),
        Padding(
          padding: EdgeInsets.only(top: topPad + 28, bottom: 20),
          child: Column(
            children: [
              // Avatar polos, tanpa border/ring.
              ProfileAvatar(url: avatarUrl, seed: uid.isEmpty ? name : uid, label: name, size: 120),
              const SizedBox(height: 14),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Flexible(
                      child: Text(
                        name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: AppColors.textWhite,
                          fontSize: 22,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    if (profile?.userNumber != null) ...[
                      const SizedBox(width: 6),
                      Padding(
                        padding: const EdgeInsets.only(bottom: 3),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              'ID #${profile!.userNumber}',
                              style: const TextStyle(color: Color(0xB3FFFFFF), fontSize: 11),
                            ),
                            const SizedBox(width: 4),
                            UserCheckBadge(firebaseUid: uid, isPremium: premium, size: 13),
                          ],
                        ),
                      ),
                    ] else if (uid.isNotEmpty) ...[
                      const SizedBox(width: 4),
                      Padding(
                        padding: const EdgeInsets.only(bottom: 3),
                        child: UserCheckBadge(firebaseUid: uid, isPremium: premium, size: 13),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 10),
              Wrap(
                alignment: WrapAlignment.center,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 8,
                runSpacing: 6,
                children: [
                  if (uid.isNotEmpty) LevelBadge(level: level, height: 20),
                  if (_has(clanTag)) ClanRainbowBadge(text: clanTag!, height: 20),
                  if (uid.isNotEmpty) RoleBadge(firebaseUid: uid, height: 20),
                ],
              ),
              const SizedBox(height: 18),
              // Stat row flat: angka besar, label kecil, garis pemisah tipis.
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Row(
                  children: [
                    _stat(favorites.length, 'Favorit'),
                    _statDivider(),
                    _stat(uniqueAnime, 'Anime Ditonton'),
                    _statDivider(),
                    _stat(history.length, 'Episode'),
                    _statDivider(),
                    _stat(commentCount, 'Komentar'),
                  ],
                ),
              ),
              const SizedBox(height: 18),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    Expanded(
                      child: ProfilePillButton(
                        icon: Icons.groups,
                        label: 'Clan',
                        color: Colors.white,
                        borderColor: const Color(0x59FFFFFF),
                        onTap: () => Navigator.of(context)
                            .push<void>(fadeRoute(const ClanBrowseScreen())),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: ProfilePillButton(
                        icon: Icons.leaderboard,
                        label: 'Leaderboard',
                        color: AppColors.accentViolet,
                        borderColor: AppColors.accentViolet.withValues(alpha: 0.6),
                        onTap: () => Navigator.of(context)
                            .push<void>(fadeRoute(const XpLeaderboardScreen())),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: FilledButton.icon(
                    onPressed: user == null
                        ? _openLogin
                        : () => _openEditSheet(
                              user: user,
                              profile: profile,
                              fallbackName: name,
                              fallbackAvatar: avatarUrl,
                              premium: premium,
                            ),
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.accentViolet,
                      shape: const StadiumBorder(),
                    ),
                    icon: Icon(user == null ? Icons.login : Icons.edit, size: 18),
                    label: Text(
                      user == null ? 'Masuk' : 'Edit Profil',
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                ),
              ),
              if (user != null) ...[
                const SizedBox(height: 10),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: OutlinedButton.icon(
                      onPressed: () => Navigator.of(context)
                          .push<void>(fadeRoute(const FriendsScreen())),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white,
                        side: const BorderSide(color: Color(0x59FFFFFF)),
                        shape: const StadiumBorder(),
                      ),
                      icon: const Icon(Icons.people_alt_outlined, size: 18),
                      label: Text(
                        incomingRequests > 0 ? 'Teman ($incomingRequests permintaan)' : 'Teman',
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
        Positioned(
          top: topPad + 8,
          right: 12,
          child: Material(
            color: const Color(0x59000000),
            shape: const CircleBorder(),
            child: IconButton(
              onPressed: () => Navigator.of(context)
                  .push<void>(fadeRoute(const ProfileSettingsScreen())),
              tooltip: 'Pengaturan',
              icon: const Icon(Icons.settings_outlined, color: Colors.white),
            ),
          ),
        ),
      ],
    );
  }

  Widget _stat(int value, String label) {
    return Expanded(
      child: Column(
        children: [
          TweenAnimationBuilder<int>(
            tween: IntTween(begin: 0, end: value),
            duration: const Duration(milliseconds: 1200),
            builder: (context, v, _) => Text(
              '$v',
              style: const TextStyle(
                color: AppColors.textWhite,
                fontSize: 19,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Color(0xB3FFFFFF), fontSize: 11),
          ),
        ],
      ),
    );
  }

  Widget _statDivider() => Container(width: 1, height: 26, color: const Color(0x40FFFFFF));

  Future<void> _openEditSheet({
    required User user,
    required ChatProfile? profile,
    required String fallbackName,
    required String? fallbackAvatar,
    required bool premium,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      // Root navigator: sheet menutupi bottom-nav floating milik shell.
      useRootNavigator: true,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: AppColors.surfaceDark,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => _EditProfileSheet(
        uid: user.uid,
        premium: premium,
        fallbackName: fallbackName,
        fallbackAvatar: fallbackAvatar,
        initialProfile: profile,
      ),
    );
  }

  // -------------------------------------------------------------------- tab

  /// Tab 5 sama lebar; indikator pendek 28dp di bawah label terpilih, plus
  /// garis tipis di dasar (sama seperti tab Zenime).
  Widget _buildTabs() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Row(
            children: [
              for (var i = 0; i < _tabs.length; i++)
                Expanded(
                  child: InkWell(
                    onTap: () => setState(() => _selectedTab = i),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      child: Column(
                        children: [
                          FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text(
                              _tabs[i],
                              style: TextStyle(
                                color: _selectedTab == i
                                    ? AppColors.textWhite
                                    : const Color(0x80FFFFFF),
                                fontSize: 13.5,
                                fontWeight:
                                    _selectedTab == i ? FontWeight.w700 : FontWeight.w400,
                              ),
                            ),
                          ),
                          const SizedBox(height: 6),
                          AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            height: 3,
                            width: _selectedTab == i ? 28 : 0,
                            decoration: BoxDecoration(
                              color: AppColors.accentViolet,
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
        Container(height: 1, color: const Color(0x14FFFFFF)),
      ],
    );
  }

  Widget _buildTabContent(
    List<FavoriteEntity> favorites,
    List<WatchHistoryEntity> history,
    User? user,
    bool premium,
    String name,
    String? avatarUrl,
  ) {
    switch (_selectedTab) {
      case 0:
        return _buildAll(user, premium);
      case 1:
        return _buildFavorites(favorites);
      case 2:
        return _buildComments(user, premium, name, avatarUrl);
      default:
        return _buildHistory(history, user, premium, name, avatarUrl);
    }
  }

  // ------------------------------------------------------------------ semua

  Widget _buildAll(User? user, bool premium) {
    return Column(
      children: [
        if (user != null) ...[
          MyXpCard(firebaseUid: user.uid),
          const SizedBox(height: 8),
        ] else ...[
          ProfileInfoCard(
            text: 'Masuk pakai akun Zenime buat dapat Level, Clan, dan Chat Global',
            action: 'Masuk',
            onTap: _openLogin,
          ),
          const SizedBox(height: 8),
        ],
        ProfileInfoCard(
          text: 'Gabung atau bikin Clan bareng sesama penonton',
          action: 'Lihat',
          onTap: () =>
              Navigator.of(context).push<void>(fadeRoute(const ClanBrowseScreen())),
        ),
        const SizedBox(height: 8),
        if (user != null && !premium) ...[
          ProfileInfoCard(
            text: 'Upgrade Premium buat upload banner profil sendiri',
            action: 'Lihat',
            outlined: true,
            onTap: () => openPremium(context),
          ),
          const SizedBox(height: 8),
        ],
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.surfaceDark,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0x14FFFFFF)),
            ),
            child: const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.info, color: AppColors.accentViolet),
                    SizedBox(width: 8),
                    Text(
                      'Tentang Zenime',
                      style: TextStyle(
                        color: AppColors.textWhite,
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
                SizedBox(height: 8),
                Text(
                  'Zenime adalah aplikasi streaming anime buat nonton ribuan judul favoritmu langsung dari HP, lengkap dengan Chat Global & Clan.',
                  style: TextStyle(color: Color(0xB3FFFFFF), fontSize: 14, height: 1.45),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // ---------------------------------------------------------------- favorit

  Widget _buildFavorites(List<FavoriteEntity> favorites) {
    const double cardW = 120;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ProfileSectionHeader(
          icon: Icons.favorite,
          title: 'Favorite Shows',
          trailing: favorites.isEmpty ? null : '${favorites.length} Anime',
        ),
        if (favorites.isEmpty)
          const ProfileEmptyBox(text: 'Belum ada anime favorit.')
        else
          SizedBox(
            height: cardW * 1.5 + 62,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: favorites.length,
              separatorBuilder: (_, __) => const SizedBox(width: 12),
              itemBuilder: (context, i) {
                final fav = favorites[i];
                return SizedBox(
                  width: cardW,
                  child: Stack(
                    key: ValueKey(fav.id),
                    children: [
                      AnimePosterCard(
                        anime: fav.toAnimeItem(),
                        width: cardW,
                        onTap: () => widget.onAnimeClick(fav.id),
                      ),
                      // Tombol hapus favorit (kiri atas poster).
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
                              color: Color(0xB30B0E14),
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
                  ),
                );
              },
            ),
          ),
        const ComicFavoritesBlock(),
      ],
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

  // --------------------------------------------------------------- komentar

  Widget _buildComments(User? user, bool premium, String name, String? avatarUrl) {
    Widget body;
    if (user == null) {
      body = const ProfileEmptyBox(text: 'Masuk untuk melihat komentarmu.');
    } else {
      final async = ref.watch(myCommentsProvider(user.uid));
      body = async.when(
        loading: () => const SizedBox(
          height: 130,
          child: Center(
            child: SizedBox(
              width: 28,
              height: 28,
              child: CircularProgressIndicator(
                strokeWidth: 3,
                color: AppColors.accentViolet,
              ),
            ),
          ),
        ),
        error: (e, _) => ProfileEmptyBox(text: errorMessage(e, 'Gagal memuat komentar')),
        data: (list) => list.isEmpty
            ? const ProfileEmptyBox(text: 'Belum pernah komentar di episode manapun.')
            : Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Column(
                  children: [
                    for (var i = 0; i < list.length; i++) ...[
                      ProfileCommentFeedRow(
                        item: list[i],
                        firebaseUid: user.uid,
                        username: name,
                        avatarUrl: avatarUrl,
                        isPremium: premium,
                        onTap: () => widget.onAnimeClick(list[i].animeId),
                      ),
                      if (i != list.length - 1) const SizedBox(height: 22),
                    ],
                  ],
                ),
              ),
      );
    }
    final count = user == null
        ? 0
        : (ref.watch(myCommentsProvider(user.uid)).valueOrNull?.length ?? 0);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ProfileSectionHeader(
          icon: Icons.chat,
          title: 'Komentar',
          trailing: count == 0 ? null : '$count Komentar',
        ),
        body,
      ],
    );
  }

  // --------------------------------------------------------------- riwayat

  Widget _buildHistory(
    List<WatchHistoryEntity> history,
    User? user,
    bool premium,
    String name,
    String? avatarUrl,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 8, 4),
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
              const Spacer(),
              if (history.isNotEmpty)
                IconButton(
                  onPressed: _confirmClearHistory,
                  tooltip: 'Hapus Semua Riwayat',
                  icon: const Icon(Icons.delete_sweep, color: AppColors.accentViolet),
                ),
            ],
          ),
        ),
        if (history.isEmpty)
          const ProfileEmptyBox(text: 'Belum ada riwayat tontonan.')
        else
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Column(
              children: [
                for (var i = 0; i < history.length; i++) ...[
                  ProfileWatchHistoryRow(
                    key: ValueKey(history[i].id),
                    history: history[i],
                    firebaseUid: user?.uid ?? '',
                    username: name,
                    avatarUrl: avatarUrl,
                    isPremium: premium,
                    onPlay: () =>
                        widget.onWatchEpisode(history[i].movieId, history[i].episodeId),
                    onDelete: () => _controller.deleteHistory(history[i].id),
                  ),
                  if (i != history.length - 1) const SizedBox(height: 22),
                ],
              ],
            ),
          ),
        const ComicProgressBlock(),
      ],
    );
  }

  // ------------------------------------------------------------ pengaturan

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

}

// ====================================================== widget pendukung

/// Avatar bulat: foto kalau ada, kalau tidak avatar otomatis (warna + inisial).
class ProfileAvatar extends StatelessWidget {
  const ProfileAvatar({
    required this.url,
    required this.seed,
    required this.label,
    required this.size,
  });

  final String? url;
  final String seed;
  final String label;
  final double size;

  @override
  Widget build(BuildContext context) {
    final has = url != null && url!.isNotEmpty;
    return Container(
      width: size,
      height: size,
      clipBehavior: Clip.antiAlias,
      decoration: const BoxDecoration(
        color: AppColors.surfaceDark,
        shape: BoxShape.circle,
      ),
      child: has
          ? NetImage(url!)
          : GeneratedAvatar(seed: seed, label: label, size: size),
    );
  }
}

class ProfilePillButton extends StatelessWidget {
  const ProfilePillButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.borderColor,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final Color color;
  final Color borderColor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: onTap,
      style: OutlinedButton.styleFrom(
        foregroundColor: color,
        side: BorderSide(color: borderColor),
        shape: const StadiumBorder(),
        minimumSize: const Size.fromHeight(44),
      ),
      icon: Icon(icon, size: 16),
      label: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
    );
  }
}

class ProfileSectionHeader extends StatelessWidget {
  const ProfileSectionHeader({required this.icon, required this.title, this.trailing});

  final IconData icon;
  final String title;
  final String? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: Row(
        children: [
          Icon(icon, color: AppColors.accentViolet, size: 20),
          const SizedBox(width: 8),
          Text(
            title,
            style: const TextStyle(
              color: AppColors.textWhite,
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
          ),
          const Spacer(),
          if (trailing != null)
            Text(trailing!, style: const TextStyle(color: Color(0x80FFFFFF), fontSize: 11)),
        ],
      ),
    );
  }
}

class ProfileEmptyBox extends StatelessWidget {
  const ProfileEmptyBox({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Container(
        height: 110,
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        decoration: BoxDecoration(
          color: AppColors.surfaceDark,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Text(
          text,
          textAlign: TextAlign.center,
          style: const TextStyle(color: AppColors.textMuted, fontSize: 13),
        ),
      ),
    );
  }
}

class ProfileInfoCard extends StatelessWidget {
  const ProfileInfoCard({
    required this.text,
    required this.action,
    required this.onTap,
    this.outlined = false,
  });

  final String text;
  final String action;
  final VoidCallback onTap;
  final bool outlined;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Material(
        color: AppColors.surfaceDark,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: outlined
              ? BorderSide(color: AppColors.accentViolet.withValues(alpha: 0.4))
              : BorderSide.none,
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    text,
                    style: const TextStyle(color: Color(0xD9FFFFFF), fontSize: 12.5),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  action,
                  style: const TextStyle(
                    color: AppColors.accentViolet,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Baris komentar flat ala feed: avatar mini + nama + waktu, thumbnail anime
/// + judul + episode, isi komentar, jumlah balasan.
class ProfileCommentFeedRow extends StatelessWidget {
  const ProfileCommentFeedRow({
    required this.item,
    required this.firebaseUid,
    required this.username,
    required this.avatarUrl,
    required this.isPremium,
    required this.onTap,
  });

  final EpisodeComment item;
  final String firebaseUid;
  final String username;
  final String? avatarUrl;
  final bool isPremium;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final created = item.time?.millisecondsSinceEpoch ?? 0;
    final poster = item.animePosterUrl ?? '';
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              ProfileAvatar(url: avatarUrl, seed: firebaseUid, label: username, size: 28),
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
              const SizedBox(width: 4),
              UserCheckBadge(firebaseUid: firebaseUid, isPremium: isPremium, size: 14),
              const Spacer(),
              Text(
                ProfileWatchHistoryRow._relative(created),
                style: const TextStyle(color: Color(0x73FFFFFF), fontSize: 11),
              ),
            ],
          ),
          const SizedBox(height: 10),
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
                    child: poster.isEmpty ? null : NetImage(poster),
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
                        item.animeTitle ?? 'Anime',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: AppColors.textWhite,
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      if ((item.episodeIndex ?? '').isNotEmpty)
                        Text(
                          'Episode ${item.episodeIndex}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: Color(0x99FFFFFF), fontSize: 11),
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if ((item.replyToUsername ?? '').isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 2),
              child: Text(
                'Balasan untuk @${item.replyToUsername}',
                style: const TextStyle(
                  color: AppColors.accentViolet,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          Text(
            item.comment,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: Color(0xD9FFFFFF), fontSize: 14, height: 1.35),
          ),
          if (item.parentId == null && item.replyCount > 0) ...[
            const SizedBox(height: 6),
            Text(
              '${item.replyCount} Balasan',
              style: const TextStyle(
                color: Color(0x80FFFFFF),
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Bottom sheet Edit Profil: foto profil (semua user), banner (khusus
/// Premium), username, dan toggle privasi Favorit / Riwayat. Semua perubahan
/// disimpan ke `chat_profiles`, yang sama dengan Zenime.
class _EditProfileSheet extends ConsumerStatefulWidget {
  const _EditProfileSheet({
    required this.uid,
    required this.premium,
    required this.fallbackName,
    required this.fallbackAvatar,
    required this.initialProfile,
  });

  final String uid;
  final bool premium;
  final String fallbackName;
  final String? fallbackAvatar;
  final ChatProfile? initialProfile;

  @override
  ConsumerState<_EditProfileSheet> createState() => _EditProfileSheetState();
}

class _EditProfileSheetState extends ConsumerState<_EditProfileSheet> {
  static const int _maxUsername = 24;

  final _picker = ImagePicker();
  late final TextEditingController _nameCtrl;

  late String _username;
  String? _avatarUrl;
  String? _bannerUrl;
  String? _usernameColor;
  bool _favPublic = false;
  bool _histPublic = false;

  bool _savingName = false;
  bool _uploadingAvatar = false;
  bool _uploadingBanner = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final p = widget.initialProfile;
    _username = (p?.username.trim().isNotEmpty ?? false) ? p!.username : widget.fallbackName;
    _avatarUrl = (p?.avatarUrl?.isNotEmpty ?? false) ? p!.avatarUrl : widget.fallbackAvatar;
    _bannerUrl = p?.bannerUrl;
    _usernameColor = p?.usernameColor;
    _favPublic = p?.favoritesPublic ?? false;
    _histPublic = p?.historyPublic ?? false;
    _nameCtrl = TextEditingController(text: _username);
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  /// Upsert menimpa SEMUA kolom, jadi nilai yang tidak diubah ikut dikirim.
  Future<void> _persist({
    String? username,
    String? avatar,
    String? banner,
    bool? fav,
    bool? hist,
  }) async {
    await ref.read(chatRepositoryProvider).saveProfile(
          firebaseUid: widget.uid,
          username: username ?? _username,
          avatarUrl: avatar ?? _avatarUrl,
          bannerUrl: banner ?? _bannerUrl,
          usernameColor: _usernameColor,
          favoritesPublic: fav ?? _favPublic,
          historyPublic: hist ?? _histPublic,
        );
    ref.invalidate(chatProfileProvider(widget.uid));
  }

  Future<void> _saveName() async {
    final trimmed = _nameCtrl.text.trim();
    final next = trimmed.length > _maxUsername ? trimmed.substring(0, _maxUsername) : trimmed;
    if (next.isEmpty) {
      setState(() => _error = 'Username gak boleh kosong');
      return;
    }
    setState(() {
      _savingName = true;
      _error = null;
    });
    try {
      await _persist(username: next);
      if (!mounted) return;
      setState(() {
        _username = next;
        _savingName = false;
      });
      FocusScope.of(context).unfocus();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _savingName = false;
        _error = errorMessage(e, 'Gagal menyimpan username');
      });
    }
  }

  Future<void> _pickAvatar() async {
    final x = await _picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 512,
      maxHeight: 512,
      imageQuality: 82,
    );
    if (x == null || !mounted) return;
    setState(() {
      _uploadingAvatar = true;
      _error = null;
    });
    try {
      final url = await ProfileImageUploader.uploadAvatar(x.path, widget.uid);
      await _persist(avatar: url);
      if (!mounted) return;
      setState(() {
        _avatarUrl = url;
        _uploadingAvatar = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _uploadingAvatar = false;
        _error = errorMessage(e, 'Gagal upload foto profil');
      });
    }
  }

  Future<void> _pickBanner() async {
    if (!widget.premium) {
      setState(() => _error = 'Upload banner profil khusus buat member Premium');
      return;
    }
    final x = await _picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 1280,
      maxHeight: 1280,
      imageQuality: 82,
    );
    if (x == null || !mounted) return;
    setState(() {
      _uploadingBanner = true;
      _error = null;
    });
    try {
      final url = await ProfileImageUploader.uploadBanner(x.path, widget.uid);
      await _persist(banner: url);
      if (!mounted) return;
      setState(() {
        _bannerUrl = url;
        _uploadingBanner = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _uploadingBanner = false;
        _error = errorMessage(e, 'Gagal upload banner');
      });
    }
  }

  Future<void> _togglePrivacy({bool? fav, bool? hist}) async {
    final prevFav = _favPublic;
    final prevHist = _histPublic;
    setState(() {
      if (fav != null) _favPublic = fav;
      if (hist != null) _histPublic = hist;
      _error = null;
    });
    try {
      await _persist(fav: fav, hist: hist);
    } catch (e) {
      // Gagal simpan: balikin toggle supaya UI tidak bohong soal privasi.
      if (!mounted) return;
      setState(() {
        _favPublic = prevFav;
        _histPublic = prevHist;
        _error = errorMessage(e, 'Gagal menyimpan pengaturan privasi');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
    final hasBanner = _bannerUrl != null && _bannerUrl!.isNotEmpty;
    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: SingleChildScrollView(
        // Bawah dikasih ruang ekstra setinggi tombol navigasi sistem supaya
        // toggle terakhir (Riwayat publik) tidak ketutup.
        padding: EdgeInsets.fromLTRB(
          20,
          12,
          20,
          24 + MediaQuery.viewPaddingOf(context).bottom,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'Edit Profil',
              style: TextStyle(
                color: AppColors.textWhite,
                fontSize: 18,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 16),
            // Banner + avatar menimpa di kiri bawah.
            SizedBox(
              height: 150,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Positioned(
                    left: 0,
                    right: 0,
                    top: 0,
                    height: 110,
                    child: GestureDetector(
                      onTap: _uploadingBanner ? null : _pickBanner,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(14),
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            hasBanner
                                ? NetImage(_bannerUrl!)
                                : const ColoredBox(color: AppColors.surfaceVariantDark),
                            Container(
                              color: Colors.black38,
                              alignment: Alignment.center,
                              child: _uploadingBanner
                                  ? const SizedBox(
                                      width: 24,
                                      height: 24,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 3,
                                        color: Colors.white,
                                      ),
                                    )
                                  : Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(
                                          widget.premium ? Icons.photo_camera : Icons.lock,
                                          color: Colors.white,
                                          size: 18,
                                        ),
                                        const SizedBox(width: 6),
                                        Text(
                                          widget.premium ? 'Ganti banner' : 'Banner (Premium)',
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 12,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ],
                                    ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    left: 16,
                    bottom: 0,
                    child: GestureDetector(
                      onTap: _uploadingAvatar ? null : _pickAvatar,
                      child: Stack(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(3),
                            decoration: const BoxDecoration(
                              color: AppColors.surfaceDark,
                              shape: BoxShape.circle,
                            ),
                            child: ProfileAvatar(
                              url: _avatarUrl,
                              seed: widget.uid,
                              label: _username,
                              size: 80,
                            ),
                          ),
                          Positioned.fill(
                            child: Container(
                              margin: const EdgeInsets.all(3),
                              decoration: const BoxDecoration(
                                color: Colors.black38,
                                shape: BoxShape.circle,
                              ),
                              alignment: Alignment.center,
                              child: _uploadingAvatar
                                  ? const SizedBox(
                                      width: 22,
                                      height: 22,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 3,
                                        color: Colors.white,
                                      ),
                                    )
                                  : const Icon(Icons.photo_camera, color: Colors.white, size: 22),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _nameCtrl,
              maxLength: _maxUsername,
              style: const TextStyle(color: AppColors.textWhite),
              cursorColor: AppColors.accentViolet,
              decoration: InputDecoration(
                labelText: 'Username',
                labelStyle: const TextStyle(color: AppColors.textSecondary),
                counterStyle: const TextStyle(color: AppColors.textMuted),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: Color(0x33FFFFFF)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: AppColors.accentViolet),
                ),
              ),
            ),
            SizedBox(
              height: 48,
              child: FilledButton(
                onPressed: _savingName ? null : _saveName,
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.accentViolet,
                  shape: const StadiumBorder(),
                ),
                child: _savingName
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white),
                      )
                    : const Text('Simpan Username', style: TextStyle(fontWeight: FontWeight.w700)),
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 10),
              Text(
                _error!,
                style: const TextStyle(color: AppColors.errorRed, fontSize: 12.5),
              ),
            ],
            const SizedBox(height: 16),
            const Text(
              'Privasi',
              style: TextStyle(
                color: AppColors.accentViolet,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              activeThumbColor: AppColors.accentViolet,
              title: const Text('Favorit publik', style: TextStyle(color: AppColors.textWhite)),
              subtitle: const Text(
                'Pengguna lain bisa lihat daftar favoritmu',
                style: TextStyle(color: AppColors.textMuted, fontSize: 12),
              ),
              value: _favPublic,
              onChanged: (v) => _togglePrivacy(fav: v),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              activeThumbColor: AppColors.accentViolet,
              title: const Text('Riwayat publik', style: TextStyle(color: AppColors.textWhite)),
              subtitle: const Text(
                'Pengguna lain bisa lihat riwayat tontonanmu',
                style: TextStyle(color: AppColors.textMuted, fontSize: 12),
              ),
              value: _histPublic,
              onChanged: (v) => _togglePrivacy(hist: v),
            ),
          ],
        ),
      ),
    );
  }
}


/// Baris riwayat flat ala feed Zenime: avatar mini + nama + waktu relatif di
/// atas, thumbnail + judul/episode, lalu ikon play + progress bar + label waktu.
class ProfileWatchHistoryRow extends StatelessWidget {
  const ProfileWatchHistoryRow({
    super.key,
    required this.history,
    required this.firebaseUid,
    required this.username,
    required this.avatarUrl,
    required this.isPremium,
    required this.onPlay,
    this.onDelete,
  });

  final WatchHistoryEntity history;
  final String firebaseUid;
  final String username;
  final String? avatarUrl;
  final bool isPremium;
  final VoidCallback onPlay;

  /// null = tidak ada tombol hapus (dipakai di profil publik orang lain).
  final VoidCallback? onDelete;

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
              ProfileAvatar(url: avatarUrl, seed: firebaseUid, label: username, size: 28),
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
              const SizedBox(width: 4),
              UserCheckBadge(firebaseUid: firebaseUid, isPremium: isPremium, size: 14),
              const Spacer(),
              Text(
                _relative(history.lastWatchedTime),
                style: const TextStyle(color: Color(0x73FFFFFF), fontSize: 11),
              ),
              if (onDelete != null) ...[
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


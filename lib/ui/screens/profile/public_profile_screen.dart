import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/error_message.dart';
import '../../../core/theme/app_colors.dart';
import '../../../data/local/entities.dart';
import '../../../data/models/chat_models.dart';
import '../../../data/models/friend_models.dart';
import '../../../providers.dart';
import '../../app_routes.dart';
import '../../components/cards.dart';
import '../../components/game_badges.dart';
import '../../components/net_image.dart';
import '../../components/role_badges.dart';
import '../clan/clan_browse_screen.dart';
import '../xp/xp_leaderboard_screen.dart';
import 'my_xp_card.dart';
import 'profile_controller.dart';
import 'profile_screen.dart';

/// Buka profil publik user lain (dari Chat Global, Chat Teman, layar Teman).
/// Port rute `profile/{targetUid}` di Zenime.
Future<void> openPublicProfile(BuildContext context, String uid) {
  return Navigator.of(context, rootNavigator: true)
      .push<void>(fadeRoute(PublicProfileScreen(uid: uid)));
}

/// Profil publik: komponen & tampilan sama dengan Profil Saya, tapi tanpa
/// Edit Profil / Pengaturan, dengan tombol Teman, dan Favorit/Riwayat hanya
/// tampil kalau pemiliknya menyalakan toggle privasi.
class PublicProfileScreen extends ConsumerStatefulWidget {
  const PublicProfileScreen({super.key, required this.uid});

  final String uid;

  @override
  ConsumerState<PublicProfileScreen> createState() => _PublicProfileScreenState();
}

class _PublicProfileScreenState extends ConsumerState<PublicProfileScreen> {
  static const List<String> _tabs = ['Semua', 'Favorit', 'Komentar', 'Riwayat'];

  int _selectedTab = 0;

  FriendRelation? _relation;
  bool _relationFailed = false;
  bool _busy = false;
  String? _error;

  String get _myUid => ref.read(authRepositoryProvider).currentUser?.uid ?? '';
  bool get _isMe => _myUid.isNotEmpty && _myUid == widget.uid;

  static bool _has(String? s) => s != null && s.isNotEmpty;

  @override
  void initState() {
    super.initState();
    if (!_isMe && _myUid.isNotEmpty) _loadRelation();
  }

  Future<void> _loadRelation() async {
    try {
      final r = await ref.read(friendRepositoryProvider).getRelation(_myUid, widget.uid);
      if (!mounted) return;
      setState(() {
        _relation = r;
        _relationFailed = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _relationFailed = true);
    }
  }

  /// Jalankan aksi lalu muat ulang hubungan (juga kalau gagal, mis. dia kirim
  /// permintaan barengan sehingga barisnya sudah ada).
  Future<void> _act(Future<void> Function() action, String fallback) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    String? err;
    try {
      await action();
    } catch (e) {
      err = errorMessage(e, fallback);
    }
    ref.invalidate(incomingFriendRequestsProvider);
    await _loadRelation();
    if (!mounted) return;
    setState(() {
      _busy = false;
      _error = err;
    });
  }

  @override
  Widget build(BuildContext context) {
    final uid = widget.uid;
    final profile = ref.watch(chatProfileProvider(uid)).valueOrNull;
    final premium = ref.watch(premiumProvider(uid)).valueOrNull ?? false;
    final name = _has(profile?.username) ? profile!.username : 'Pengguna Zenime';
    final avatarUrl = profile?.avatarUrl;

    // Profil sendiri: pakai data lokal (selalu lengkap). Orang lain: hasil
    // fetch publik, null = privat.
    List<FavoriteEntity>? favorites;
    List<WatchHistoryEntity>? history;
    if (_isMe) {
      favorites = ref.watch(profileFavoritesProvider);
      history = ref.watch(profileHistoryProvider);
    } else {
      final content = ref.watch(publicProfileContentProvider(uid)).valueOrNull;
      favorites = content?.favorites?.map((r) => r.toEntity()).toList();
      history = content?.history?.map((r) => r.toEntity()).toList();
    }
    final contentLoading =
        !_isMe && ref.watch(publicProfileContentProvider(uid)).isLoading;
    final contentFailed =
        !_isMe && ref.watch(publicProfileContentProvider(uid)).hasError;

    return Scaffold(
      backgroundColor: AppColors.backgroundDark,
      body: Stack(
        children: [
          SingleChildScrollView(
            padding: const EdgeInsets.only(bottom: 40),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildHero(
                  profile: profile,
                  name: name,
                  avatarUrl: avatarUrl,
                  premium: premium,
                  favorites: favorites ?? const [],
                  history: history ?? const [],
                ),
                const SizedBox(height: 8),
                _buildTabs(),
                const SizedBox(height: 16),
                _buildTabContent(
                  favorites: favorites,
                  history: history,
                  loading: contentLoading,
                  failed: contentFailed,
                  name: name,
                  avatarUrl: avatarUrl,
                  premium: premium,
                ),
              ],
            ),
          ),
          Positioned(
            top: MediaQuery.paddingOf(context).top + 8,
            left: 8,
            child: Material(
              color: const Color(0x59000000),
              shape: const CircleBorder(),
              child: IconButton(
                onPressed: () => Navigator.of(context).maybePop(),
                tooltip: 'Kembali',
                icon: const Icon(Icons.arrow_back, color: Colors.white),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ------------------------------------------------------------------- hero

  Widget _buildHero({
    required ChatProfile? profile,
    required String name,
    required String? avatarUrl,
    required bool premium,
    required List<FavoriteEntity> favorites,
    required List<WatchHistoryEntity> history,
  }) {
    final uid = widget.uid;

    // Banner: foto custom (khusus Premium) -> poster favorit pertama ->
    // poster riwayat pertama -> warna solid. Sama dengan Profil Saya.
    String? backdrop;
    if (premium && _has(profile?.bannerUrl)) {
      backdrop = profile!.bannerUrl;
    } else if (favorites.isNotEmpty && _has(favorites.first.posterUrl)) {
      backdrop = favorites.first.posterUrl;
    } else if (history.isNotEmpty && _has(history.first.moviePoster)) {
      backdrop = history.first.moviePoster;
    }

    final level = ref.watch(myXpProvider(uid)).valueOrNull?.level ?? 1;
    final clanTag = ref.watch(userClanTagProvider(uid)).valueOrNull;
    final commentCount = ref.watch(myCommentCountProvider(uid)).valueOrNull ?? 0;
    final uniqueAnime = history.map((h) => h.movieId).toSet().length;
    final topPad = MediaQuery.paddingOf(context).top;

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
              ProfileAvatar(url: avatarUrl, seed: uid, label: name, size: 120),
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
                    const SizedBox(width: 6),
                    Padding(
                      padding: const EdgeInsets.only(bottom: 3),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (profile?.userNumber != null) ...[
                            Text(
                              'ID #${profile!.userNumber}',
                              style: const TextStyle(color: Color(0xB3FFFFFF), fontSize: 11),
                            ),
                            const SizedBox(width: 4),
                          ],
                          UserCheckBadge(firebaseUid: uid, isPremium: premium, size: 13),
                        ],
                      ),
                    ),
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
                  LevelBadge(level: level, height: 20),
                  if (_has(clanTag)) ClanRainbowBadge(text: clanTag!, height: 20),
                  RoleBadge(firebaseUid: uid, height: 20),
                ],
              ),
              const SizedBox(height: 18),
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
              if (!_isMe) ...[
                const SizedBox(height: 14),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: _buildFriendActions(),
                ),
              ],
              if (_error != null) ...[
                const SizedBox(height: 10),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Text(
                    _error!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: AppColors.errorRed, fontSize: 12.5),
                  ),
                ),
              ],
            ],
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

  // ------------------------------------------------------------- tombol teman

  Widget _buildFriendActions() {
    if (_myUid.isEmpty) {
      return const Text(
        'Masuk dulu untuk menambah teman.',
        textAlign: TextAlign.center,
        style: TextStyle(color: AppColors.textMuted, fontSize: 13),
      );
    }
    if (_relationFailed) {
      return TextButton(
        onPressed: _loadRelation,
        child: const Text(
          'Gagal memuat status teman. Coba lagi',
          style: TextStyle(color: AppColors.accentViolet),
        ),
      );
    }
    final relation = _relation;
    if (relation == null) {
      return const SizedBox(
        height: 52,
        child: Center(
          child: SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(strokeWidth: 2.5, color: AppColors.accentViolet),
          ),
        ),
      );
    }
    final repo = ref.read(friendRepositoryProvider);

    Widget filled(IconData icon, String label, VoidCallback? onTap) => SizedBox(
          width: double.infinity,
          height: 52,
          child: FilledButton.icon(
            onPressed: _busy ? null : onTap,
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.accentViolet,
              shape: const StadiumBorder(),
            ),
            icon: Icon(icon, size: 18),
            label: Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
          ),
        );

    Widget outlined(IconData icon, String label, VoidCallback? onTap,
            {Color color = Colors.white}) =>
        SizedBox(
          width: double.infinity,
          height: 52,
          child: OutlinedButton.icon(
            onPressed: _busy ? null : onTap,
            style: OutlinedButton.styleFrom(
              foregroundColor: color,
              side: BorderSide(color: color.withValues(alpha: 0.4)),
              shape: const StadiumBorder(),
            ),
            icon: Icon(icon, size: 18),
            label: Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
          ),
        );

    return switch (relation) {
      FriendRelationNone() => filled(
          Icons.person_add,
          'Tambah Teman',
          () => _act(() => repo.sendRequest(_myUid, widget.uid), 'Gagal mengirim permintaan'),
        ),
      FriendRelationOutgoing(:final friendshipId) => outlined(
          Icons.hourglass_top,
          'Permintaan Terkirim · Batalkan',
          () => _act(() => repo.remove(friendshipId), 'Gagal membatalkan permintaan'),
        ),
      FriendRelationIncoming(:final friendshipId) => Row(
          children: [
            Expanded(
              child: filled(
                Icons.check,
                'Terima',
                () => _act(() => repo.accept(friendshipId), 'Gagal menerima permintaan'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: outlined(
                Icons.close,
                'Tolak',
                () => _act(() => repo.remove(friendshipId), 'Gagal menolak permintaan'),
              ),
            ),
          ],
        ),
      FriendRelationFriends(:final friendshipId) => outlined(
          Icons.check,
          'Berteman',
          () => _confirmRemove(friendshipId),
          color: AppColors.accentViolet,
        ),
    };
  }

  Future<void> _confirmRemove(String friendshipId) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surfaceDark,
        surfaceTintColor: Colors.transparent,
        title: const Text('Hapus teman?', style: TextStyle(color: AppColors.textWhite)),
        content: const Text(
          'Kalian nggak bisa saling chat private lagi sampai berteman lagi.',
          style: TextStyle(color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Batal', style: TextStyle(color: AppColors.textSecondary)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Hapus', style: TextStyle(color: AppColors.errorRed)),
          ),
        ],
      ),
    );
    if (ok == true) {
      await _act(
        () => ref.read(friendRepositoryProvider).remove(friendshipId),
        'Gagal menghapus teman',
      );
    }
  }

  // ------------------------------------------------------------------- tab

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

  Widget _buildTabContent({
    required List<FavoriteEntity>? favorites,
    required List<WatchHistoryEntity>? history,
    required bool loading,
    required bool failed,
    required String name,
    required String? avatarUrl,
    required bool premium,
  }) {
    switch (_selectedTab) {
      case 0:
        return _buildAll();
      case 1:
        return _buildFavorites(favorites, loading, failed);
      case 2:
        return _buildComments(name, avatarUrl, premium);
      default:
        return _buildHistory(history, loading, failed, name, avatarUrl, premium);
    }
  }

  Widget _buildAll() {
    return Column(
      children: [
        MyXpCard(firebaseUid: widget.uid),
        const SizedBox(height: 8),
        ProfileInfoCard(
          text: 'Gabung atau bikin Clan bareng sesama penonton',
          action: 'Lihat',
          onTap: () =>
              Navigator.of(context).push<void>(fadeRoute(const ClanBrowseScreen())),
        ),
      ],
    );
  }

  Widget _loadingBox() => const SizedBox(
        height: 130,
        child: Center(
          child: SizedBox(
            width: 28,
            height: 28,
            child: CircularProgressIndicator(strokeWidth: 3, color: AppColors.accentViolet),
          ),
        ),
      );

  Widget _buildFavorites(List<FavoriteEntity>? favorites, bool loading, bool failed) {
    const double cardW = 120;
    final Widget body;
    if (loading) {
      body = _loadingBox();
    } else if (failed) {
      body = const ProfileEmptyBox(text: 'Gagal memuat favorit. Coba lagi nanti.');
    } else if (favorites == null) {
      body = const ProfileEmptyBox(text: 'Pengguna ini menyembunyikan daftar favoritnya.');
    } else if (favorites.isEmpty) {
      body = const ProfileEmptyBox(text: 'Belum ada anime favorit.');
    } else {
      body = SizedBox(
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
              child: AnimePosterCard(
                key: ValueKey(fav.id),
                anime: fav.toAnimeItem(),
                width: cardW,
                onTap: () => openDetail(context, fav.id),
              ),
            );
          },
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ProfileSectionHeader(
          icon: Icons.favorite,
          title: 'Favorite Shows',
          trailing: (favorites == null || favorites.isEmpty) ? null : '${favorites.length} Anime',
        ),
        body,
      ],
    );
  }

  Widget _buildComments(String name, String? avatarUrl, bool premium) {
    final async = ref.watch(myCommentsProvider(widget.uid));
    final Widget body = async.when(
      loading: _loadingBox,
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
                      firebaseUid: widget.uid,
                      username: name,
                      avatarUrl: avatarUrl,
                      isPremium: premium,
                      onTap: () => openDetail(context, list[i].animeId),
                    ),
                    if (i != list.length - 1) const SizedBox(height: 22),
                  ],
                ],
              ),
            ),
    );
    final count = async.valueOrNull?.length ?? 0;
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

  Widget _buildHistory(
    List<WatchHistoryEntity>? history,
    bool loading,
    bool failed,
    String name,
    String? avatarUrl,
    bool premium,
  ) {
    final Widget body;
    if (loading) {
      body = _loadingBox();
    } else if (failed) {
      body = const ProfileEmptyBox(text: 'Gagal memuat riwayat. Coba lagi nanti.');
    } else if (history == null) {
      body = const ProfileEmptyBox(text: 'Pengguna ini menyembunyikan riwayat tontonannya.');
    } else if (history.isEmpty) {
      body = const ProfileEmptyBox(text: 'Belum ada riwayat tontonan.');
    } else {
      body = Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
        child: Column(
          children: [
            for (var i = 0; i < history.length; i++) ...[
              ProfileWatchHistoryRow(
                key: ValueKey(history[i].id),
                history: history[i],
                firebaseUid: widget.uid,
                username: name,
                avatarUrl: avatarUrl,
                isPremium: premium,
                onPlay: () =>
                    openPlayer(context, history[i].movieId, history[i].episodeId),
              ),
              if (i != history.length - 1) const SizedBox(height: 22),
            ],
          ],
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const ProfileSectionHeader(icon: Icons.history, title: 'Riwayat Tontonan'),
        body,
      ],
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../components/rarity_chip.dart';
import '../../../data/repository/safety_repository.dart' show ReportChannel;
import '../safety/safety_actions.dart';
import '../../../core/error_message.dart';
import '../../../core/theme/app_colors.dart';
import '../../../data/local/entities.dart';
import '../../../data/models/chat_models.dart';
import '../../../data/models/comment_models.dart';
import '../../../data/models/friend_models.dart';
import '../../../providers.dart';
import '../../components/activity_status.dart';
import '../../app_routes.dart';
import '../../components/cards.dart';
import '../../components/profile_badges.dart';
import '../../components/net_image.dart';
import '../../components/role_badges.dart';
import '../../components/join_date_stat.dart';
import '../clan/clan_browse_screen.dart';
import '../tree/tree_screen.dart';
import '../../components/app_toast.dart';
import '../comments/comments_section.dart' show openCommentThreadFromProfile;
import '../xp/xp_leaderboard_screen.dart';
import 'profile_controller.dart';
import 'profile_screen_seed.dart';
import 'profile_screen.dart';
import 'profile_card.dart';
import '../../glass/glass.dart';
import '../../components/clan_tag_badge.dart';
import '../../components/common_components.dart';
import '../../redesign/z_kit.dart';

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
    _loadScreenData();
  }

  /// Semua data profil lewat SATU request (screen-data). Bagian yang gagal
  /// otomatis diambil lewat jalur lama oleh provider masing-masing.
  Future<void> _loadScreenData() async {
    final relation = await loadProfileScreenSeed(ref, widget.uid);
    if (!mounted || _isMe || _myUid.isEmpty) return;
    if (relation != null) {
      setState(() {
        _relation = relation;
        _relationFailed = false;
      });
    } else {
      _loadRelation();
    }
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

    return GlassScaffold(
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
          // Laporkan / blokir profil orang lain.
          if (!_isMe && _myUid.isNotEmpty)
            Positioned(
              top: MediaQuery.paddingOf(context).top + 8,
              right: 8,
              child: Material(
                color: const Color(0x59000000),
                shape: const CircleBorder(),
                child: PopupMenuButton<String>(
                  tooltip: 'Lainnya',
                  color: AppColors.surfaceDark,
                  icon: const Icon(Icons.more_vert, color: Colors.white),
                  onSelected: (v) {
                    if (v == 'report') {
                      showReportSheet(
                        context,
                        ref,
                        targetUid: uid,
                        targetName: name,
                        channel: ReportChannel.profile,
                      );
                    } else if (v == 'block') {
                      confirmBlockUser(context, ref, uid: uid, name: name);
                    } else if (v == 'card') {
                      showProfileCard(
                        context,
                        uid: uid,
                        favorites: favorites ?? const [],
                        animeCount: history?.map((h) => h.movieId).toSet().length ?? 0,
                        episodeCount: history?.length ?? 0,
                      );
                    }
                  },
                  itemBuilder: (_) => const [
                    PopupMenuItem(
                      value: 'card',
                      child: Text('Kartu profil', style: TextStyle(color: AppColors.textWhite)),
                    ),
                    PopupMenuItem(
                      value: 'report',
                      child: Text('Laporkan profil', style: TextStyle(color: AppColors.textWhite)),
                    ),
                    PopupMenuItem(
                      value: 'block',
                      child: Text('Blokir pengguna', style: TextStyle(color: AppColors.errorRed)),
                    ),
                  ],
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

    // Banner: wallpaper banner -> foto custom (khusus Premium) -> poster
    // favorit pertama -> poster riwayat pertama -> warna solid. Sama dengan Profil Saya.
    final wpBanner = ref.watch(bannerWallpaperProvider(uid)).valueOrNull;
    String? backdrop = resolveProfileBanner(wallpaper: wpBanner, premium: premium, customUrl: profile?.bannerUrl);
    if (backdrop != null) {
      // sudah dipilih
    } else if (favorites.isNotEmpty && _has(favorites.first.posterUrl)) {
      backdrop = favorites.first.posterUrl;
    } else if (history.isNotEmpty && _has(history.first.moviePoster)) {
      backdrop = history.first.moviePoster;
    }

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
                // Gelap bertahap: banner tetap kelihatan di atas, teks jelas di bawah.
                stops: [0, 0.3, 0.62, 1],
                colors: [
                  Color(0x33000000),
                  Color(0x40000000),
                  Color(0xCC0B0E14),
                  AppColors.backgroundDark,
                ],
              ),
            ),
          ),
        ),
        // Badge rarity kalau banner berasal dari wallpaper komentar
        // (kiri atas, di sebelah tombol kembali; tidak menutupi avatar).
        if (wpBanner != null)
          Positioned(
            top: topPad + 23,
            left: 64,
            child: BannerRarityBadge(rarity: wpBanner.rarity),
          ),
        Padding(
          padding: EdgeInsets.only(top: topPad + 28, bottom: 20),
          child: Column(
            children: [
              ProfileHeroAvatar(
                uid: uid,
                url: avatarUrl,
                seed: uid,
                label: name,
                showXpRing: true,
                leading: ProfileAchievementBadges.topXpChip(ref, uid),
                trailing: ProfileAchievementBadges.topGiverChip(ref, uid),
              ),
              const SizedBox(height: 10),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    if (_has(clanTag)) ...[
                      Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: ClanTagBadge(text: clanTag!, nameTag: true, height: 20),
                      ),
                      const SizedBox(width: 6),
                    ],
                    Flexible(
                      child: premium
                          // Premium: nama bergradien emas.
                          ? ShaderMask(
                              blendMode: BlendMode.srcIn,
                              shaderCallback: (r) => const LinearGradient(
                                colors: [Color(0xFFFFE08A), Color(0xFFF6BE4F), Color(0xFFFF9F6B)],
                              ).createShader(r),
                              child: Text(
                                name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: ZFont.display(size: 24, height: 1.1),
                              ),
                            )
                          : Text(
                              name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: ZFont.display(size: 24, height: 1.1),
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
              const SizedBox(height: 6),
              ActivityStatus(uid: uid),
              const SizedBox(height: 10),
              // Nama clan + role. Top XP / Top Giver ada di samping pin level.
              Wrap(
                alignment: WrapAlignment.center,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 8,
                runSpacing: 8,
                children: [
                  ProfileClanPill(uid: uid),
                  RoleBadge(firebaseUid: uid, height: 22, rounded: true),
                ],
              ),
              const SizedBox(height: 18),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Row(
                  children: [
                    JoinDateStat(firebaseUid: uid),
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
                    const SizedBox(width: 8),
                    Expanded(
                      child: ProfilePillButton(
                        icon: Icons.park_rounded,
                        label: 'Pohon',
                        color: const Color(0xFF4ADE80),
                        borderColor: const Color(0x994ADE80),
                        onTap: () => _openTree(name, avatarUrl),
                      ),
                    ),
                    const SizedBox(width: 8),
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
            builder: (context, v, _) => Text('$v', style: ZFont.display(size: 20, height: 1.1)),
          ),
          const SizedBox(height: 3),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppColors.textMuted, fontSize: 11, fontWeight: FontWeight.w500),
          ),
        ],
      ),
    );
  }

  Widget _statDivider() => Container(width: 1, height: 28, color: const Color(0x14FFFFFF));

  /// Pohon: profil sendiri -> pohonku; teman -> mampir ke pohonnya.
  void _openTree(String name, String? avatarUrl) {
    final nav = Navigator.of(context);
    if (_isMe) {
      nav.push<void>(fadeRoute(const TreeScreen()));
      return;
    }
    if (_relation is FriendRelationFriends) {
      nav.push<void>(fadeRoute(TreeVisitScreen(friendUid: widget.uid, username: name, avatarUrl: avatarUrl)));
      return;
    }
    showAppToast(
      context,
      _myUid.isEmpty ? 'Masuk dulu untuk mampir ke pohon teman' : 'Berteman dulu biar bisa mampir ke pohonnya',
      icon: Icons.park_rounded,
    );
  }

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
          height: 46,
          child: FilledButton.icon(
            onPressed: _busy ? null : onTap,
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.accentViolet,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
            icon: Icon(icon, size: 18),
            label: Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
          ),
        );

    Widget outlined(IconData icon, String label, VoidCallback? onTap,
            {Color color = Colors.white}) =>
        SizedBox(
          width: double.infinity,
          height: 46,
          child: OutlinedButton.icon(
            onPressed: _busy ? null : onTap,
            style: OutlinedButton.styleFrom(
              foregroundColor: color,
              backgroundColor: color.withValues(alpha: 0.10),
              side: BorderSide(color: color.withValues(alpha: 0.35)),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
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
    final n = _tabs.length;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Container(
        height: 44,
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: AppColors.surfaceDark,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0x12FFFFFF)),
        ),
        child: LayoutBuilder(
          builder: (context, c) {
            final w = c.maxWidth / n;
            return Stack(
              children: [
                AnimatedPositioned(
                  duration: const Duration(milliseconds: 260),
                  curve: Curves.easeOutQuint,
                  left: _selectedTab * w,
                  top: 0,
                  bottom: 0,
                  width: w,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: AppColors.surfaceElevated,
                      borderRadius: BorderRadius.circular(11),
                    ),
                  ),
                ),
                Row(
                  children: [
                    for (var i = 0; i < n; i++)
                      Expanded(
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: () => setState(() => _selectedTab = i),
                          child: Center(
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 4),
                                child: Text(
                                  _tabs[i],
                                  style: TextStyle(
                                    color: _selectedTab == i ? AppColors.textWhite : AppColors.textMuted,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            );
          },
        ),
      ),
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
        return _buildAll(history, loading, name, avatarUrl, premium);
      case 1:
        return _buildFavorites(favorites, loading, failed);
      case 2:
        return _buildComments(name, avatarUrl, premium);
      default:
        return _buildHistory(history, loading, failed, name, avatarUrl, premium);
    }
  }

  /// Tab Semua: gabungan komentar + riwayat tontonan (kalau riwayatnya
  /// publik), urut dari yang terbaru. Sama seperti tab Semua di profil sendiri.
  Widget _buildAll(
    List<WatchHistoryEntity>? history,
    bool loading,
    String name,
    String? avatarUrl,
    bool premium,
  ) {
    final commentsAsync = ref.watch(myCommentsProvider(widget.uid));
    final comments = commentsAsync.valueOrNull ?? const <EpisodeComment>[];

    final entries = <(DateTime, Widget)>[];
    for (final h in history ?? const <WatchHistoryEntity>[]) {
      entries.add((
        DateTime.fromMillisecondsSinceEpoch(h.lastWatchedTime),
        ProfileWatchHistoryRow(
          key: ValueKey('h-${h.id}'),
          history: h,
          firebaseUid: widget.uid,
          username: name,
          avatarUrl: avatarUrl,
          isPremium: premium,
          onPlay: () => openPlayer(context, h.movieId, h.episodeId),
        ),
      ));
    }
    for (final c in comments) {
      entries.add((
        c.time ?? DateTime.fromMillisecondsSinceEpoch(0),
        ProfileCommentFeedRow(
          key: ValueKey('c-${c.id}'),
          item: c,
          firebaseUid: widget.uid,
          username: name,
          avatarUrl: avatarUrl,
          isPremium: premium,
          onTap: () => openCommentThreadFromProfile(context, c),
        ),
      ));
    }
    entries.sort((x, y) => y.$1.compareTo(x.$1));
    final shown = entries.take(40).toList();
    final stillLoading = (loading || commentsAsync.isLoading) && shown.isEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const ProfileSectionHeader(icon: Icons.dynamic_feed, title: 'Aktivitas Terbaru'),
        if (stillLoading)
          _loadingBox()
        else if (shown.isEmpty)
          const ProfileEmptyBox(text: 'Belum ada aktivitas.')
        else
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Column(
              children: [
                for (var i = 0; i < shown.length; i++) ...[
                  shown[i].$2,
                  if (i != shown.length - 1) const SizedBox(height: 22),
                ],
              ],
            ),
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
    final Widget body;
    if (loading) {
      body = _loadingBox();
    } else if (failed) {
      body = const ProfileEmptyBox(text: 'Gagal memuat favorit. Coba lagi nanti.');
    } else if (favorites == null) {
      body = const ProfileEmptyBox(text: 'Pengguna ini menyembunyikan daftar favoritnya.');
    } else {
      final anime = favorites.where((f) => !f.isDonghua).toList();
      final donghua = favorites.where((f) => f.isDonghua).toList();
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ProfileSectionHeader(
            icon: Icons.favorite,
            title: 'Anime Favorit',
            trailing: anime.isEmpty ? null : '${anime.length} Anime',
          ),
          if (anime.isEmpty) const ProfileEmptyBox(text: 'Belum ada anime favorit.') else _favoriteRow(anime),
          if (donghua.isNotEmpty) ...[
            const SizedBox(height: 8),
            ProfileSectionHeader(
              icon: Icons.movie_filter_rounded,
              title: 'Donghua Favorit',
              trailing: '${donghua.length} Donghua',
            ),
            _favoriteRow(donghua),
          ],
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const ProfileSectionHeader(icon: Icons.favorite, title: 'Anime Favorit'),
        body,
      ],
    );
  }

  Widget _favoriteRow(List<FavoriteEntity> list) {
    const double cardW = 120;
    return SizedBox(
      height: cardW * 1.5 + 62,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: list.length,
        separatorBuilder: (_, __) => const SizedBox(width: 12),
        itemBuilder: (context, i) {
          final fav = list[i];
          return SizedBox(
            width: cardW,
            child: AnimePosterCard(
              key: ValueKey(fav.id),
              anime: fav.toAnimeItem(),
              width: cardW,
              onTap: () => fav.isDonghua ? openDonghuaDetail(context, fav.id) : openDetail(context, fav.id),
            ),
          );
        },
      ),
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
                      onTap: () => openCommentThreadFromProfile(context, list[i]),
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

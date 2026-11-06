import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/theme/app_colors.dart';
import '../../../data/repository/feed_repository.dart';
import '../../../providers.dart';
import '../../app_routes.dart';
import '../../components/app_toast.dart';
import '../../components/friend_avatar.dart';
import '../../components/net_image.dart';
import '../../components/shimmer.dart';
import '../chat/chat_mute.dart' show canChatMuteProvider;
import '../profile/public_profile_screen.dart';

final feedRepositoryProvider = Provider<FeedRepository>(
  (ref) => FeedRepository(ref.watch(supabaseDioProvider)),
);

String _ago(DateTime t) {
  final d = DateTime.now().difference(t);
  if (d.inMinutes < 1) return 'baru saja';
  if (d.inMinutes < 60) return '${d.inMinutes}m';
  if (d.inHours < 24) return '${d.inHours}j';
  if (d.inDays < 7) return '${d.inDays}h';
  String two(int v) => v.toString().padLeft(2, '0');
  return '${two(t.day)}/${two(t.month)}/${t.year % 100}';
}

String _count(int n) {
  if (n < 1000) return '$n';
  if (n < 1000000) return '${(n / 1000).toStringAsFixed(n < 10000 ? 1 : 0).replaceAll('.0', '')}rb';
  return '${(n / 1000000).toStringAsFixed(1).replaceAll('.0', '')}jt';
}

Color? _hex(String? hex) {
  if (hex == null) return null;
  final h = hex.replaceFirst('#', '');
  if (h.length != 6) return null;
  final v = int.tryParse(h, radix: 16);
  return v == null ? null : Color(0xFF000000 | v);
}

String _err(Object e, String fallback) => e is FeedException ? e.message : fallback;

const Color _likeRed = Color(0xFFFF4D6A);

/// Buka tulis postingan (cek login & Premium dulu). Return postingan baru.
Future<FeedPost?> _openCompose(BuildContext context, WidgetRef ref) async {
  final uid = ref.read(authUserProvider).valueOrNull?.uid;
  if (uid == null || uid.isEmpty) {
    showAppToast(context, 'Login dulu untuk posting', kind: ToastKind.warning);
    return null;
  }
  if (ref.read(myPremiumProvider).valueOrNull != true) {
    showAppToast(context, 'Bikin postingan khusus Premium', kind: ToastKind.warning, icon: Icons.workspace_premium);
    openPremium(context);
    return null;
  }
  return Navigator.of(context).push<FeedPost>(fadeRoute(const FeedComposeScreen()));
}

// =================================================================== layar

/// Feed: postingan user (Premium), tab Untukmu & Teman.
class FeedScreen extends ConsumerStatefulWidget {
  const FeedScreen({super.key});

  @override
  ConsumerState<FeedScreen> createState() => _FeedScreenState();
}

class _FeedScreenState extends ConsumerState<FeedScreen> {
  final _allKey = GlobalKey<_FeedTabState>();
  final _friendsKey = GlobalKey<_FeedTabState>();

  Future<void> _compose() async {
    final post = await _openCompose(context, ref);
    if (post == null || !mounted) return;
    _allKey.currentState?.insert(post);
    _friendsKey.currentState?.insert(post);
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        backgroundColor: AppColors.backgroundDark,
        body: SafeArea(
          bottom: false,
          child: Column(
            children: [
              // ------------------------------------------------ kepala
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 6, 16, 6),
                child: Row(
                  children: [
                    IconButton(
                      onPressed: () => Navigator.of(context).maybePop(),
                      icon: const Icon(Icons.arrow_back_rounded, color: AppColors.textWhite),
                    ),
                    const Text(
                      'Feed',
                      style: TextStyle(color: AppColors.textWhite, fontSize: 24, fontWeight: FontWeight.w900),
                    ),
                    const Spacer(),
                    Container(
                      height: 38,
                      padding: const EdgeInsets.all(3),
                      decoration: BoxDecoration(
                        color: AppColors.surfaceCard,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: TabBar(
                        isScrollable: true,
                        tabAlignment: TabAlignment.start,
                        dividerColor: Colors.transparent,
                        indicatorSize: TabBarIndicatorSize.tab,
                        indicator: BoxDecoration(
                          color: AppColors.accentViolet,
                          borderRadius: BorderRadius.circular(17),
                        ),
                        labelColor: Colors.white,
                        unselectedLabelColor: AppColors.textMuted,
                        labelPadding: const EdgeInsets.symmetric(horizontal: 14),
                        labelStyle: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
                        splashBorderRadius: BorderRadius.circular(17),
                        tabs: const [Tab(text: 'Untukmu'), Tab(text: 'Teman')],
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: TabBarView(
                  children: [
                    _FeedTab(key: _allKey, tab: 'all', onCompose: _compose),
                    _FeedTab(key: _friendsKey, tab: 'friends', onCompose: _compose),
                  ],
                ),
              ),
            ],
          ),
        ),
        floatingActionButton: DecoratedBox(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: const LinearGradient(
              colors: [AppColors.accentVioletLight, AppColors.accentViolet],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            boxShadow: [BoxShadow(color: AppColors.accentViolet.withValues(alpha: 0.45), blurRadius: 18, offset: const Offset(0, 6))],
          ),
          child: FloatingActionButton(
            backgroundColor: Colors.transparent,
            elevation: 0,
            onPressed: _compose,
            child: const Icon(Icons.add_rounded, color: Colors.white, size: 30),
          ),
        ),
      ),
    );
  }
}

class _FeedTab extends ConsumerStatefulWidget {
  const _FeedTab({super.key, required this.tab, required this.onCompose});

  final String tab;
  final VoidCallback onCompose;

  @override
  ConsumerState<_FeedTab> createState() => _FeedTabState();
}

class _FeedTabState extends ConsumerState<_FeedTab> with AutomaticKeepAliveClientMixin {
  final _scroll = ScrollController();
  List<FeedPost> _posts = const [];
  bool _loading = true;
  bool _loadingMore = false;
  bool _hasMore = true;
  String? _error;

  FeedRepository get _repo => ref.read(feedRepositoryProvider);

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(() {
      if (_scroll.position.pixels > _scroll.position.maxScrollExtent - 800) _loadMore();
    });
    _load();
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final list = await _repo.list(widget.tab);
      if (!mounted) return;
      setState(() {
        _posts = list;
        _hasMore = list.length >= 20;
        _loading = false;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = _err(e, 'Gagal memuat feed');
      });
    }
  }

  Future<void> _loadMore() async {
    if (_loadingMore || !_hasMore || _loading || _posts.isEmpty) return;
    setState(() => _loadingMore = true);
    try {
      final more = await _repo.list(widget.tab, before: _posts.last.id);
      if (!mounted) return;
      final known = _posts.map((p) => p.id).toSet();
      setState(() {
        _posts = [..._posts, ...more.where((p) => !known.contains(p.id))];
        _hasMore = more.length >= 20;
        _loadingMore = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  void insert(FeedPost p) {
    if (_posts.any((x) => x.id == p.id)) return;
    setState(() => _posts = [p, ..._posts]);
    if (_scroll.hasClients) {
      _scroll.animateTo(0, duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
    }
  }

  void _replace(FeedPost p) => setState(() => _posts = [for (final x in _posts) x.id == p.id ? p : x]);

  void _remove(int id) => setState(() => _posts = _posts.where((x) => x.id != id).toList());

  @override
  Widget build(BuildContext context) {
    super.build(context);
    if (_loading) {
      return ListView(
        physics: const NeverScrollableScrollPhysics(),
        children: const [_ComposerPrompt(onTap: null), _PostSkeleton(), _PostSkeleton(), _PostSkeleton()],
      );
    }
    if (_error != null && _posts.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.wifi_off_rounded, color: AppColors.textMuted, size: 40),
            const SizedBox(height: 10),
            Text(_error!, style: const TextStyle(color: AppColors.textSecondary)),
            const SizedBox(height: 8),
            FilledButton.tonal(
              onPressed: () {
                setState(() => _loading = true);
                _load();
              },
              child: const Text('Coba lagi'),
            ),
          ],
        ),
      );
    }
    return RefreshIndicator(
      color: AppColors.accentViolet,
      backgroundColor: AppColors.surfaceDark,
      onRefresh: _load,
      child: ListView.builder(
        controller: _scroll,
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.only(bottom: 110),
        itemCount: 1 + (_posts.isEmpty ? 1 : _posts.length) + (_loadingMore ? 1 : 0),
        itemBuilder: (context, i) {
          if (i == 0) return _ComposerPrompt(onTap: widget.onCompose);
          if (_posts.isEmpty) {
            return Padding(
              padding: const EdgeInsets.fromLTRB(32, 80, 32, 0),
              child: Column(
                children: [
                  Icon(
                    widget.tab == 'friends' ? Icons.people_outline_rounded : Icons.dynamic_feed_rounded,
                    color: AppColors.textMuted,
                    size: 52,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    widget.tab == 'friends' ? 'Teman-temanmu belum posting apa pun' : 'Belum ada postingan',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: AppColors.textWhite, fontWeight: FontWeight.w700, fontSize: 15),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Jadi yang pertama berbagi cerita nonton!',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: AppColors.textMuted, fontSize: 13),
                  ),
                ],
              ),
            );
          }
          final idx = i - 1;
          if (idx >= _posts.length) {
            return const Padding(
              padding: EdgeInsets.all(20),
              child: Center(child: CircularProgressIndicator(color: AppColors.accentViolet, strokeWidth: 2.5)),
            );
          }
          final p = _posts[idx];
          return FeedPostCard(
            key: ValueKey(p.id),
            post: p,
            onChanged: _replace,
            onDeleted: _remove,
            onOpen: () => Navigator.of(context).push<void>(fadeRoute(FeedPostScreen(
                  postId: p.id,
                  initial: p,
                  onChanged: _replace,
                  onDeleted: _remove,
                ))),
          );
        },
      ),
    );
  }
}

/// Baris "Apa yang lagi kamu tonton?" di atas feed (seperti aplikasi sosmed).
class _ComposerPrompt extends ConsumerWidget {
  const _ComposerPrompt({required this.onTap});

  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final uid = ref.watch(authUserProvider).valueOrNull?.uid ?? '';
    final me = uid.isEmpty ? null : ref.watch(chatProfileProvider(uid)).valueOrNull;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 8, 12, 14),
      decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: Color(0x14FFFFFF)))),
      child: Row(
        children: [
          FriendAvatar(url: me?.avatarUrl, seed: uid.isEmpty ? 'guest' : uid, label: me?.username ?? '?', size: 40),
          const SizedBox(width: 12),
          Expanded(
            child: InkWell(
              onTap: onTap,
              borderRadius: BorderRadius.circular(22),
              child: Container(
                height: 42,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                alignment: Alignment.centerLeft,
                decoration: BoxDecoration(
                  color: AppColors.surfaceCard,
                  borderRadius: BorderRadius.circular(22),
                  border: Border.all(color: const Color(0x14FFFFFF)),
                ),
                child: const Text(
                  'Apa yang lagi kamu tonton?',
                  style: TextStyle(color: AppColors.textMuted, fontSize: 14),
                ),
              ),
            ),
          ),
          IconButton(
            onPressed: onTap,
            icon: const Icon(Icons.image_outlined, color: AppColors.accentVioletLight),
          ),
        ],
      ),
    );
  }
}

class _PostSkeleton extends StatelessWidget {
  const _PostSkeleton();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.fromLTRB(16, 16, 16, 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ShimmerBox(width: 42, height: 42, borderRadius: BorderRadius.all(Radius.circular(21))),
          SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ShimmerBox(width: 140, height: 13),
                SizedBox(height: 10),
                ShimmerBox(height: 12),
                SizedBox(height: 6),
                ShimmerBox(width: 200, height: 12),
                SizedBox(height: 12),
                ShimmerBox(height: 190, borderRadius: BorderRadius.all(Radius.circular(16))),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// =================================================================== kartu

/// Satu postingan gaya sosmed: avatar di kiri, nama · waktu, teks yang bisa
/// dibuka penuh, gambar (ketuk dua kali = suka, ketuk = layar penuh),
/// serta tombol suka / komentar / bagikan.
class FeedPostCard extends ConsumerStatefulWidget {
  const FeedPostCard({
    super.key,
    required this.post,
    required this.onChanged,
    required this.onDeleted,
    this.onOpen,
  });

  final FeedPost post;
  final ValueChanged<FeedPost> onChanged;
  final ValueChanged<int> onDeleted;

  /// null = sudah di halaman detail (teks tampil penuh, kartu tidak di-tap).
  final VoidCallback? onOpen;

  @override
  ConsumerState<FeedPostCard> createState() => _FeedPostCardState();
}

class _FeedPostCardState extends ConsumerState<FeedPostCard> {
  bool _liking = false;
  bool _expanded = false;
  int _burst = 0;
  int _pop = 0;

  static const int _collapseAt = 260;

  Future<void> _toggleLike({bool onlyLike = false}) async {
    final uid = ref.read(authUserProvider).valueOrNull?.uid;
    if (uid == null || uid.isEmpty) {
      showAppToast(context, 'Login dulu untuk menyukai', kind: ToastKind.warning);
      return;
    }
    final p = widget.post;
    if (onlyLike && p.liked) return;
    if (_liking) return;
    _liking = true;
    HapticFeedback.lightImpact();
    final on = !p.liked;
    setState(() => _pop++);
    widget.onChanged(p.copyWith(liked: on, likeCount: (p.likeCount + (on ? 1 : -1)).clamp(0, 1 << 30)));
    try {
      final n = await ref.read(feedRepositoryProvider).like(p.id, on);
      if (mounted) widget.onChanged(p.copyWith(liked: on, likeCount: n));
    } catch (e) {
      widget.onChanged(p);
      if (mounted) showAppToast(context, _err(e, 'Gagal menyukai postingan'), kind: ToastKind.error);
    } finally {
      _liking = false;
    }
  }

  void _doubleTapLike() {
    setState(() => _burst++);
    _toggleLike(onlyLike: true);
  }

  Future<void> _share() async {
    final p = widget.post;
    final text = p.body.trim().isEmpty ? 'Lihat postingan ${p.username} di Zenime!' : '${p.username} di Zenime:\n"${p.body.trim()}"';
    try {
      await Share.share(text);
    } catch (_) {}
  }

  Future<void> _delete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surfaceDark,
        title: const Text('Hapus postingan?', style: TextStyle(color: AppColors.textWhite)),
        content: const Text('Postingan & komentarnya akan hilang.', style: TextStyle(color: AppColors.textSecondary)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Batal')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Hapus', style: TextStyle(color: AppColors.errorRed)),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await ref.read(feedRepositoryProvider).delete(widget.post.id);
      widget.onDeleted(widget.post.id);
      if (mounted) showAppToast(context, 'Postingan dihapus', kind: ToastKind.success);
    } catch (e) {
      if (mounted) showAppToast(context, _err(e, 'Gagal menghapus postingan'), kind: ToastKind.error);
    }
  }

  void _openImage(String url) {
    Navigator.of(context).push<void>(PageRouteBuilder<void>(
      opaque: false,
      barrierColor: Colors.black,
      pageBuilder: (_, __, ___) => _ImageViewer(url: url),
      transitionsBuilder: (_, a, __, child) => FadeTransition(opacity: a, child: child),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.post;
    final detail = widget.onOpen == null;
    final myUid = ref.watch(authUserProvider).valueOrNull?.uid ?? '';
    final staff = ref.watch(canChatMuteProvider).valueOrNull == true;
    final canDelete = p.uid == myUid || staff;
    final url = p.imageUrl;
    final long = !detail && !_expanded && p.body.length > _collapseAt;
    final body = long ? '${p.body.substring(0, _collapseAt).trimRight()}…' : p.body;

    return InkWell(
      onTap: widget.onOpen,
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 14, 8, 6),
        decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: Color(0x14FFFFFF)))),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            GestureDetector(
              onTap: () => openPublicProfile(context, p.uid),
              child: FriendAvatar(url: p.avatarUrl, seed: p.uid, label: p.username, size: 42),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ---------------------------------------- nama · waktu · menu
                  Row(
                    children: [
                      Flexible(
                        child: GestureDetector(
                          onTap: () => openPublicProfile(context, p.uid),
                          child: Text(
                            p.username,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: _hex(p.usernameColor) ?? AppColors.textWhite,
                              fontWeight: FontWeight.w800,
                              fontSize: 14.5,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        [if (p.userNumber != null) '#${p.userNumber}', _ago(p.createdAt)].join(' · '),
                        style: const TextStyle(color: AppColors.textMuted, fontSize: 12.5),
                      ),
                      const Spacer(),
                      if (canDelete)
                        SizedBox(
                          width: 32,
                          height: 24,
                          child: PopupMenuButton<String>(
                            padding: EdgeInsets.zero,
                            icon: const Icon(Icons.more_horiz_rounded, color: AppColors.textMuted, size: 20),
                            color: AppColors.surfaceDark,
                            onSelected: (v) {
                              if (v == 'delete') _delete();
                            },
                            itemBuilder: (_) => const [
                              PopupMenuItem(
                                value: 'delete',
                                child: Row(
                                  children: [
                                    Icon(Icons.delete_outline_rounded, color: AppColors.errorRed, size: 20),
                                    SizedBox(width: 10),
                                    Text('Hapus postingan', style: TextStyle(color: AppColors.errorRed)),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                  // ---------------------------------------- teks
                  if (p.body.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 3, right: 8),
                      child: Text.rich(
                        TextSpan(
                          text: body,
                          children: [
                            if (long)
                              WidgetSpan(
                                alignment: PlaceholderAlignment.baseline,
                                baseline: TextBaseline.alphabetic,
                                child: GestureDetector(
                                  onTap: () => setState(() => _expanded = true),
                                  child: const Text(
                                    ' Lihat selengkapnya',
                                    style: TextStyle(color: AppColors.accentVioletLight, fontWeight: FontWeight.w700, fontSize: 14),
                                  ),
                                ),
                              ),
                          ],
                        ),
                        style: TextStyle(
                          color: AppColors.textWhite,
                          fontSize: detail ? 16 : 14.5,
                          height: 1.45,
                        ),
                      ),
                    ),
                  // ---------------------------------------- gambar
                  if (url != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 10, right: 8),
                      child: GestureDetector(
                        onTap: () => _openImage(url),
                        onDoubleTap: _doubleTapLike,
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(16),
                          child: AspectRatio(
                            aspectRatio: p.imageRatio,
                            child: Stack(
                              fit: StackFit.expand,
                              children: [
                                ColoredBox(
                                  color: AppColors.surfaceElevated,
                                  child: NetImage(url, fit: BoxFit.cover),
                                ),
                                if (_burst > 0) _HeartBurst(key: ValueKey(_burst)),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  // ---------------------------------------- aksi
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Row(
                      children: [
                        _Action(
                          icon: TweenAnimationBuilder<double>(
                            key: ValueKey('pop$_pop'),
                            tween: Tween(begin: _pop == 0 ? 1.0 : 0.6, end: 1.0),
                            duration: const Duration(milliseconds: 380),
                            curve: Curves.elasticOut,
                            builder: (_, s, child) => Transform.scale(scale: s, child: child),
                            child: Icon(
                              p.liked ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                              size: 21,
                              color: p.liked ? _likeRed : AppColors.textSecondary,
                            ),
                          ),
                          label: p.likeCount > 0 ? _count(p.likeCount) : null,
                          color: p.liked ? _likeRed : AppColors.textSecondary,
                          onTap: () => _toggleLike(),
                        ),
                        _Action(
                          icon: const Icon(Icons.mode_comment_outlined, size: 20, color: AppColors.textSecondary),
                          label: p.commentCount > 0 ? _count(p.commentCount) : null,
                          color: AppColors.textSecondary,
                          onTap: widget.onOpen,
                        ),
                        _Action(
                          icon: const Icon(Icons.send_outlined, size: 19, color: AppColors.textSecondary),
                          color: AppColors.textSecondary,
                          onTap: _share,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Action extends StatelessWidget {
  const _Action({required this.icon, required this.color, this.label, this.onTap});

  final Widget icon;
  final String? label;
  final Color color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(4, 8, 14, 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            icon,
            if (label != null) ...[
              const SizedBox(width: 5),
              Text(label!, style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 13)),
            ],
          ],
        ),
      ),
    );
  }
}

/// Hati besar yang muncul lalu memudar saat gambar diketuk dua kali.
class _HeartBurst extends StatelessWidget {
  const _HeartBurst({super.key});

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: 1),
        duration: const Duration(milliseconds: 750),
        builder: (_, t, __) {
          final scale = t < 0.35 ? Curves.easeOutBack.transform(t / 0.35) * 1.15 : 1.15 - (t - 0.35) * 0.25;
          final opacity = t < 0.7 ? 1.0 : (1 - (t - 0.7) / 0.3).clamp(0.0, 1.0);
          return Center(
            child: Opacity(
              opacity: opacity,
              child: Transform.scale(
                scale: scale,
                child: const Icon(
                  Icons.favorite_rounded,
                  size: 96,
                  color: Colors.white,
                  shadows: [Shadow(color: Color(0x88000000), blurRadius: 18)],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Gambar layar penuh, bisa di-zoom; ketuk / geser untuk menutup.
class _ImageViewer extends StatelessWidget {
  const _ImageViewer({required this.url});

  final String url;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          GestureDetector(
            onTap: () => Navigator.of(context).maybePop(),
            onVerticalDragEnd: (d) {
              if ((d.primaryVelocity ?? 0).abs() > 600) Navigator.of(context).maybePop();
            },
            child: Center(
              child: InteractiveViewer(
                minScale: 1,
                maxScale: 4,
                child: NetImage(url, fit: BoxFit.contain),
              ),
            ),
          ),
          SafeArea(
            child: IconButton(
              onPressed: () => Navigator.of(context).maybePop(),
              icon: const Icon(Icons.close_rounded, color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }
}

// =================================================================== detail

/// Satu postingan + komentarnya. Bisa dibuka dari kartu atau notifikasi.
class FeedPostScreen extends ConsumerStatefulWidget {
  const FeedPostScreen({super.key, required this.postId, this.initial, this.onChanged, this.onDeleted});

  final int postId;
  final FeedPost? initial;
  final ValueChanged<FeedPost>? onChanged;
  final ValueChanged<int>? onDeleted;

  @override
  ConsumerState<FeedPostScreen> createState() => _FeedPostScreenState();
}

class _FeedPostScreenState extends ConsumerState<FeedPostScreen> {
  final _input = TextEditingController();
  final _focus = FocusNode();
  FeedPost? _post;
  List<FeedComment> _comments = const [];
  bool _loadingComments = true;
  bool _hasMoreComments = false;
  bool _loadingMoreComments = false;
  bool _sending = false;
  String? _error;

  FeedRepository get _repo => ref.read(feedRepositoryProvider);

  @override
  void initState() {
    super.initState();
    _post = widget.initial;
    _load();
  }

  @override
  void dispose() {
    _input.dispose();
    _focus.dispose();
    super.dispose();
  }

  /// Postingan & 30 komentar pertama dimuat bersamaan (tidak menunggu satu sama lain).
  Future<void> _load() async {
    await Future.wait([_loadPost(), _loadComments()]);
  }

  Future<void> _loadPost() async {
    try {
      final p = await _repo.get(widget.postId);
      if (mounted) _setPost(p);
    } catch (e) {
      if (mounted && _post == null) setState(() => _error = _err(e, 'Gagal memuat postingan'));
    }
  }

  Future<void> _loadComments() async {
    try {
      final page = await _repo.comments(widget.postId);
      if (!mounted) return;
      setState(() {
        _comments = page;
        _hasMoreComments = page.length >= 30;
        _loadingComments = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loadingComments = false);
    }
  }

  Future<void> _loadMoreComments() async {
    if (_loadingMoreComments || _comments.isEmpty) return;
    setState(() => _loadingMoreComments = true);
    try {
      final page = await _repo.comments(widget.postId, after: _comments.last.id);
      if (!mounted) return;
      final known = _comments.map((c) => c.id).toSet();
      setState(() {
        _comments = [..._comments, ...page.where((c) => !known.contains(c.id))];
        _hasMoreComments = page.length >= 30;
        _loadingMoreComments = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loadingMoreComments = false);
    }
  }

  void _setPost(FeedPost p) {
    setState(() => _post = p);
    widget.onChanged?.call(p);
  }

  Future<void> _send() async {
    final text = _input.text.trim();
    if (text.isEmpty || _sending) return;
    final uid = ref.read(authUserProvider).valueOrNull?.uid;
    if (uid == null || uid.isEmpty) {
      showAppToast(context, 'Login dulu untuk berkomentar', kind: ToastKind.warning);
      return;
    }
    setState(() => _sending = true);
    try {
      final c = await _repo.comment(widget.postId, text);
      if (!mounted) return;
      _input.clear();
      setState(() => _comments = [..._comments, c]);
      final p = _post;
      if (p != null) _setPost(p.copyWith(commentCount: p.commentCount + 1));
    } catch (e) {
      if (mounted) showAppToast(context, _err(e, 'Gagal mengirim komentar'), kind: ToastKind.error);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _deleteComment(FeedComment c) async {
    try {
      await _repo.deleteComment(c.id);
      if (!mounted) return;
      setState(() => _comments = _comments.where((x) => x.id != c.id).toList());
      final p = _post;
      if (p != null) _setPost(p.copyWith(commentCount: (p.commentCount - 1).clamp(0, 1 << 30)));
    } catch (e) {
      if (mounted) showAppToast(context, _err(e, 'Gagal menghapus komentar'), kind: ToastKind.error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = _post;
    final myUid = ref.watch(authUserProvider).valueOrNull?.uid ?? '';
    final me = myUid.isEmpty ? null : ref.watch(chatProfileProvider(myUid)).valueOrNull;
    final staff = ref.watch(canChatMuteProvider).valueOrNull == true;

    Widget body;
    if (p == null) {
      body = _error == null
          ? ListView(physics: const NeverScrollableScrollPhysics(), children: const [_PostSkeleton()])
          : Center(child: Text(_error!, style: const TextStyle(color: AppColors.textSecondary)));
    } else {
      body = ListView(
        padding: const EdgeInsets.only(bottom: 16),
        children: [
          FeedPostCard(
            post: p,
            onChanged: _setPost,
            onDeleted: (id) {
              widget.onDeleted?.call(id);
              Navigator.of(context).maybePop();
            },
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
            child: Text(
              p.commentCount > 0 ? 'Komentar · ${_count(p.commentCount)}' : 'Komentar',
              style: const TextStyle(color: AppColors.textWhite, fontWeight: FontWeight.w800, fontSize: 15),
            ),
          ),
          if (_loadingComments)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Center(child: CircularProgressIndicator(color: AppColors.accentViolet, strokeWidth: 2.5)),
            )
          else if (_comments.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 28),
              child: Column(
                children: [
                  const Icon(Icons.chat_bubble_outline_rounded, color: AppColors.textMuted, size: 34),
                  const SizedBox(height: 8),
                  const Text('Belum ada komentar', style: TextStyle(color: AppColors.textSecondary, fontWeight: FontWeight.w600)),
                  TextButton(onPressed: () => _focus.requestFocus(), child: const Text('Jadi yang pertama')),
                ],
              ),
            )
          else ...[
            for (final c in _comments)
              _CommentTile(
                comment: c,
                isAuthor: c.uid == p.uid,
                canDelete: c.uid == myUid || p.uid == myUid || staff,
                onDelete: () => _deleteComment(c),
              ),
            if (_hasMoreComments)
              Center(
                child: TextButton(
                  onPressed: _loadingMoreComments ? null : _loadMoreComments,
                  child: _loadingMoreComments
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.accentViolet),
                        )
                      : const Text('Muat komentar lainnya'),
                ),
              ),
          ],
        ],
      );
    }

    return Scaffold(
      backgroundColor: AppColors.backgroundDark,
      appBar: AppBar(
        backgroundColor: AppColors.backgroundDark,
        surfaceTintColor: Colors.transparent,
        foregroundColor: AppColors.textWhite,
        title: const Text('Postingan', style: TextStyle(fontWeight: FontWeight.w800)),
      ),
      body: Column(
        children: [
          Expanded(child: body),
          if (p != null)
            Container(
              decoration: const BoxDecoration(
                color: AppColors.backgroundDark,
                border: Border(top: BorderSide(color: Color(0x14FFFFFF))),
              ),
              padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
              child: SafeArea(
                top: false,
                child: Row(
                  children: [
                    FriendAvatar(url: me?.avatarUrl, seed: myUid.isEmpty ? 'guest' : myUid, label: me?.username ?? '?', size: 34, framed: false),
                    const SizedBox(width: 10),
                    Expanded(
                      child: TextField(
                        controller: _input,
                        focusNode: _focus,
                        maxLength: 500,
                        minLines: 1,
                        maxLines: 4,
                        textCapitalization: TextCapitalization.sentences,
                        style: const TextStyle(color: AppColors.textWhite, fontSize: 14),
                        decoration: InputDecoration(
                          counterText: '',
                          isDense: true,
                          hintText: 'Tambahkan komentar...',
                          hintStyle: const TextStyle(color: AppColors.textMuted),
                          filled: true,
                          fillColor: AppColors.surfaceCard,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(22), borderSide: BorderSide.none),
                        ),
                      ),
                    ),
                    ListenableBuilder(
                      listenable: _input,
                      builder: (_, __) {
                        final empty = _input.text.trim().isEmpty;
                        return TextButton(
                          onPressed: _sending || empty ? null : _send,
                          child: _sending
                              ? const SizedBox.square(
                                  dimension: 18,
                                  child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.accentViolet),
                                )
                              : Text(
                                  'Kirim',
                                  style: TextStyle(
                                    color: empty ? AppColors.textMuted : AppColors.accentVioletLight,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                        );
                      },
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _CommentTile extends StatelessWidget {
  const _CommentTile({
    required this.comment,
    required this.isAuthor,
    required this.canDelete,
    required this.onDelete,
  });

  final FeedComment comment;
  final bool isAuthor;
  final bool canDelete;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final c = comment;
    return InkWell(
      onLongPress: !canDelete
          ? null
          : () => showModalBottomSheet<void>(
                context: context,
                backgroundColor: AppColors.surfaceDark,
                builder: (ctx) => SafeArea(
                  child: ListTile(
                    leading: const Icon(Icons.delete_outline_rounded, color: AppColors.errorRed),
                    title: const Text('Hapus komentar', style: TextStyle(color: AppColors.errorRed)),
                    onTap: () {
                      Navigator.pop(ctx);
                      onDelete();
                    },
                  ),
                ),
              ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            GestureDetector(
              onTap: () => openPublicProfile(context, c.uid),
              child: FriendAvatar(url: c.avatarUrl, seed: c.uid, label: c.username, size: 34, framed: false),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          c.username,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: _hex(c.usernameColor) ?? AppColors.textWhite,
                            fontWeight: FontWeight.w800,
                            fontSize: 13,
                          ),
                        ),
                      ),
                      if (isAuthor) ...[
                        const SizedBox(width: 5),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                          decoration: BoxDecoration(
                            color: AppColors.accentViolet.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: const Text(
                            'Pembuat',
                            style: TextStyle(color: AppColors.accentVioletLight, fontSize: 9.5, fontWeight: FontWeight.w800),
                          ),
                        ),
                      ],
                      const SizedBox(width: 6),
                      Text(_ago(c.createdAt), style: const TextStyle(color: AppColors.textMuted, fontSize: 11.5)),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(c.body, style: const TextStyle(color: AppColors.textWhite, fontSize: 14, height: 1.4)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// =================================================================== tulis

/// Bikin postingan baru (Premium). Pop dengan [FeedPost] yang jadi.
class FeedComposeScreen extends ConsumerStatefulWidget {
  const FeedComposeScreen({super.key});

  @override
  ConsumerState<FeedComposeScreen> createState() => _FeedComposeScreenState();
}

class _FeedComposeScreenState extends ConsumerState<FeedComposeScreen> {
  static const int _max = 1000;
  final _text = TextEditingController();
  final _picker = ImagePicker();
  String? _imagePath;
  int? _w;
  int? _h;
  bool _posting = false;
  double _progress = 0;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _pick() async {
    try {
      final x = await _picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1280,
        maxHeight: 1280,
        imageQuality: 80,
        requestFullMetadata: false,
      );
      if (x == null || !mounted) return;
      final bytes = await File(x.path).readAsBytes();
      if (bytes.length > FeedRepository.maxImageBytes) {
        if (mounted) showAppToast(context, 'Ukuran gambar maksimal 2 MB', kind: ToastKind.warning);
        return;
      }
      final img = await decodeImageFromList(bytes);
      final w = img.width;
      final h = img.height;
      img.dispose();
      if (!mounted) return;
      setState(() {
        _imagePath = x.path;
        _w = w;
        _h = h;
      });
    } catch (_) {
      if (mounted) showAppToast(context, 'Gambar tidak bisa dibuka', kind: ToastKind.error);
    }
  }

  Future<void> _post() async {
    final text = _text.text.trim();
    if (_posting) return;
    if (text.isEmpty && _imagePath == null) {
      showAppToast(context, 'Tulis sesuatu atau pilih gambar dulu', kind: ToastKind.warning);
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() {
      _posting = true;
      _progress = 0;
    });
    try {
      final post = await ref.read(feedRepositoryProvider).create(
            body: text,
            imagePath: _imagePath,
            width: _w,
            height: _h,
            onProgress: (v) {
              if (mounted) setState(() => _progress = v);
            },
          );
      if (!mounted) return;
      showAppToast(context, 'Postingan terkirim', kind: ToastKind.success);
      Navigator.pop(context, post);
    } catch (e) {
      if (!mounted) return;
      setState(() => _posting = false);
      showAppToast(context, _err(e, 'Gagal membuat postingan'), kind: ToastKind.error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final path = _imagePath;
    final uid = ref.watch(authUserProvider).valueOrNull?.uid ?? '';
    final me = uid.isEmpty ? null : ref.watch(chatProfileProvider(uid)).valueOrNull;

    return Scaffold(
      backgroundColor: AppColors.backgroundDark,
      appBar: AppBar(
        backgroundColor: AppColors.backgroundDark,
        surfaceTintColor: Colors.transparent,
        foregroundColor: AppColors.textWhite,
        leading: IconButton(
          onPressed: () => Navigator.of(context).maybePop(),
          icon: const Icon(Icons.close_rounded),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: ListenableBuilder(
              listenable: _text,
              builder: (_, __) {
                final ready = _text.text.trim().isNotEmpty || path != null;
                return FilledButton(
                  onPressed: _posting || !ready ? null : _post,
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.accentViolet,
                    disabledBackgroundColor: AppColors.surfaceElevated,
                    shape: const StadiumBorder(),
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                  ),
                  child: _posting
                      ? SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                            value: path != null && _progress > 0 && _progress < 1 ? _progress : null,
                          ),
                        )
                      : const Text('Posting', style: TextStyle(fontWeight: FontWeight.w800)),
                );
              },
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    FriendAvatar(url: me?.avatarUrl, seed: uid.isEmpty ? 'guest' : uid, label: me?.username ?? '?', size: 42),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: Text(
                              me?.username ?? '',
                              style: const TextStyle(color: AppColors.textWhite, fontWeight: FontWeight.w800, fontSize: 15),
                            ),
                          ),
                          Container(
                            margin: const EdgeInsets.only(top: 4),
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: const Color(0x33FFFFFF)),
                            ),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.public_rounded, size: 13, color: AppColors.textSecondary),
                                SizedBox(width: 4),
                                Text('Publik', style: TextStyle(color: AppColors.textSecondary, fontSize: 11.5)),
                              ],
                            ),
                          ),
                          TextField(
                            controller: _text,
                            autofocus: true,
                            maxLength: _max,
                            minLines: 3,
                            maxLines: null,
                            textCapitalization: TextCapitalization.sentences,
                            style: const TextStyle(color: AppColors.textWhite, fontSize: 17, height: 1.45),
                            decoration: const InputDecoration(
                              counterText: '',
                              hintText: 'Apa yang lagi kamu tonton?',
                              hintStyle: TextStyle(color: AppColors.textMuted, fontSize: 17),
                              border: InputBorder.none,
                            ),
                          ),
                          if (path != null)
                            Padding(
                              padding: const EdgeInsets.only(top: 8),
                              child: Stack(
                                children: [
                                  ClipRRect(
                                    borderRadius: BorderRadius.circular(16),
                                    child: Image.file(File(path), fit: BoxFit.cover, width: double.infinity),
                                  ),
                                  Positioned(
                                    top: 8,
                                    right: 8,
                                    child: Material(
                                      color: Colors.black54,
                                      shape: const CircleBorder(),
                                      child: IconButton(
                                        visualDensity: VisualDensity.compact,
                                        onPressed: _posting ? null : () => setState(() => _imagePath = null),
                                        icon: const Icon(Icons.close_rounded, color: Colors.white, size: 18),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          // ------------------------------------------------ toolbar bawah
          Container(
            decoration: const BoxDecoration(border: Border(top: BorderSide(color: Color(0x14FFFFFF)))),
            padding: const EdgeInsets.fromLTRB(8, 4, 16, 4),
            child: SafeArea(
              top: false,
              child: Row(
                children: [
                  IconButton(
                    tooltip: 'Tambah gambar',
                    onPressed: _posting || path != null ? null : _pick,
                    icon: const Icon(Icons.image_outlined, color: AppColors.accentVioletLight),
                  ),
                  const Expanded(
                    child: Text(
                      'Jaga sopan santun ya 🙏',
                      style: TextStyle(color: AppColors.textMuted, fontSize: 12),
                    ),
                  ),
                  ListenableBuilder(
                    listenable: _text,
                    builder: (_, __) {
                      final left = _max - _text.text.length;
                      return Text(
                        '$left',
                        style: TextStyle(
                          color: left < 50 ? AppColors.errorRed : AppColors.textMuted,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/theme/app_colors.dart';
import '../../../data/repository/feed_repository.dart';
import '../../../providers.dart';
import '../../app_routes.dart';
import '../../components/app_toast.dart';
import '../../components/friend_avatar.dart';
import '../../components/net_image.dart';
import '../chat/chat_mute.dart' show canChatMuteProvider;
import '../profile/public_profile_screen.dart';

final feedRepositoryProvider = Provider<FeedRepository>(
  (ref) => FeedRepository(ref.watch(supabaseDioProvider)),
);

String _ago(DateTime t) {
  final d = DateTime.now().difference(t);
  if (d.inMinutes < 1) return 'baru saja';
  if (d.inMinutes < 60) return '${d.inMinutes} mnt';
  if (d.inHours < 24) return '${d.inHours} jam';
  if (d.inDays < 7) return '${d.inDays} hr';
  String two(int v) => v.toString().padLeft(2, '0');
  return '${two(t.day)}/${two(t.month)}/${t.year}';
}

Color? _hex(String? hex) {
  if (hex == null) return null;
  final h = hex.replaceFirst('#', '');
  if (h.length != 6) return null;
  final v = int.tryParse(h, radix: 16);
  return v == null ? null : Color(0xFF000000 | v);
}

String _err(Object e, String fallback) => e is FeedException ? e.message : fallback;

// =================================================================== layar

/// Feed: postingan user (Premium), tab Semua & Teman.
class FeedScreen extends ConsumerStatefulWidget {
  const FeedScreen({super.key});

  @override
  ConsumerState<FeedScreen> createState() => _FeedScreenState();
}

class _FeedScreenState extends ConsumerState<FeedScreen> {
  final _allKey = GlobalKey<_FeedTabState>();
  final _friendsKey = GlobalKey<_FeedTabState>();

  Future<void> _compose() async {
    final uid = ref.read(authUserProvider).valueOrNull?.uid;
    if (uid == null || uid.isEmpty) {
      showAppToast(context, 'Login dulu untuk posting', kind: ToastKind.warning);
      return;
    }
    if (ref.read(myPremiumProvider).valueOrNull != true) {
      showAppToast(context, 'Bikin postingan khusus Premium', kind: ToastKind.warning, icon: Icons.workspace_premium);
      openPremium(context);
      return;
    }
    final post = await Navigator.of(context).push<FeedPost>(fadeRoute(const FeedComposeScreen()));
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
        appBar: AppBar(
          backgroundColor: AppColors.backgroundDark,
          foregroundColor: AppColors.textWhite,
          title: const Text('Feed', style: TextStyle(fontWeight: FontWeight.w800)),
          bottom: const TabBar(
            indicatorColor: AppColors.accentViolet,
            labelColor: AppColors.textWhite,
            unselectedLabelColor: AppColors.textMuted,
            labelStyle: TextStyle(fontWeight: FontWeight.w800),
            tabs: [Tab(text: 'Semua'), Tab(text: 'Teman')],
          ),
        ),
        floatingActionButton: FloatingActionButton.extended(
          backgroundColor: AppColors.accentViolet,
          foregroundColor: Colors.white,
          onPressed: _compose,
          icon: const Icon(Icons.edit_rounded),
          label: const Text('Posting', style: TextStyle(fontWeight: FontWeight.w800)),
        ),
        body: TabBarView(
          children: [
            _FeedTab(key: _allKey, tab: 'all'),
            _FeedTab(key: _friendsKey, tab: 'friends'),
          ],
        ),
      ),
    );
  }
}

class _FeedTab extends ConsumerStatefulWidget {
  const _FeedTab({super.key, required this.tab});

  final String tab;

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
      if (_scroll.position.pixels > _scroll.position.maxScrollExtent - 600) _loadMore();
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
  }

  void _replace(FeedPost p) => setState(() => _posts = [for (final x in _posts) x.id == p.id ? p : x]);

  void _remove(int id) => setState(() => _posts = _posts.where((x) => x.id != id).toList());

  @override
  Widget build(BuildContext context) {
    super.build(context);
    if (_loading) {
      return const Center(child: CircularProgressIndicator(color: AppColors.accentViolet, strokeWidth: 3));
    }
    if (_error != null && _posts.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_error!, style: const TextStyle(color: AppColors.textSecondary)),
            TextButton(
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
      onRefresh: _load,
      child: _posts.isEmpty
          ? ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              children: [
                const SizedBox(height: 120),
                Center(
                  child: Text(
                    widget.tab == 'friends' ? 'Belum ada postingan dari temanmu.' : 'Belum ada postingan. Jadi yang pertama!',
                    style: const TextStyle(color: AppColors.textMuted),
                  ),
                ),
              ],
            )
          : ListView.builder(
              controller: _scroll,
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 96),
              itemCount: _posts.length + (_loadingMore ? 1 : 0),
              itemBuilder: (context, i) {
                if (i >= _posts.length) {
                  return const Padding(
                    padding: EdgeInsets.all(16),
                    child: Center(child: CircularProgressIndicator(color: AppColors.accentViolet, strokeWidth: 2.5)),
                  );
                }
                final p = _posts[i];
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

// =================================================================== kartu

/// Satu postingan: kepala (avatar, nama, waktu, menu), isi, gambar, like & komentar.
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

  /// null = sudah di halaman detail (kartu tidak bisa di-tap).
  final VoidCallback? onOpen;

  @override
  ConsumerState<FeedPostCard> createState() => _FeedPostCardState();
}

class _FeedPostCardState extends ConsumerState<FeedPostCard> {
  bool _liking = false;

  Future<void> _toggleLike() async {
    final uid = ref.read(authUserProvider).valueOrNull?.uid;
    if (uid == null || uid.isEmpty) {
      showAppToast(context, 'Login dulu untuk menyukai', kind: ToastKind.warning);
      return;
    }
    if (_liking) return;
    _liking = true;
    HapticFeedback.selectionClick();
    final p = widget.post;
    final on = !p.liked;
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

  @override
  Widget build(BuildContext context) {
    final p = widget.post;
    final myUid = ref.watch(authUserProvider).valueOrNull?.uid ?? '';
    final staff = ref.watch(canChatMuteProvider).valueOrNull == true;
    final canDelete = p.uid == myUid || staff;
    final url = p.imageUrl;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: AppColors.surfaceCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: widget.onOpen,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 4, 6),
              child: Row(
                children: [
                  GestureDetector(
                    onTap: () => openPublicProfile(context, p.uid),
                    child: FriendAvatar(url: p.avatarUrl, seed: p.uid, label: p.username, size: 38),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          p.username,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: _hex(p.usernameColor) ?? AppColors.textWhite,
                            fontWeight: FontWeight.w800,
                            fontSize: 14,
                          ),
                        ),
                        Text(
                          [if (p.userNumber != null) '#${p.userNumber}', _ago(p.createdAt)].join(' · '),
                          style: const TextStyle(color: AppColors.textMuted, fontSize: 11.5),
                        ),
                      ],
                    ),
                  ),
                  if (canDelete)
                    PopupMenuButton<String>(
                      icon: const Icon(Icons.more_vert_rounded, color: AppColors.textMuted, size: 20),
                      color: AppColors.surfaceDark,
                      onSelected: (v) {
                        if (v == 'delete') _delete();
                      },
                      itemBuilder: (_) => const [
                        PopupMenuItem(
                          value: 'delete',
                          child: Text('Hapus postingan', style: TextStyle(color: AppColors.errorRed)),
                        ),
                      ],
                    ),
                ],
              ),
            ),
            if (p.body.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 0, 14, 8),
                child: Text(
                  p.body,
                  maxLines: widget.onOpen == null ? null : 8,
                  overflow: widget.onOpen == null ? null : TextOverflow.ellipsis,
                  style: const TextStyle(color: AppColors.textWhite, fontSize: 14.5, height: 1.4),
                ),
              ),
            if (url != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(10, 0, 10, 4),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: AspectRatio(
                    aspectRatio: p.imageRatio,
                    child: ColoredBox(
                      color: AppColors.surfaceElevated,
                      child: NetImage(url, fit: BoxFit.cover),
                    ),
                  ),
                ),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 0, 8, 4),
              child: Row(
                children: [
                  TextButton.icon(
                    onPressed: _toggleLike,
                    style: TextButton.styleFrom(foregroundColor: p.liked ? const Color(0xFFFF4D6A) : AppColors.textSecondary),
                    icon: Icon(p.liked ? Icons.favorite_rounded : Icons.favorite_border_rounded, size: 20),
                    label: Text('${p.likeCount}', style: const TextStyle(fontWeight: FontWeight.w700)),
                  ),
                  TextButton.icon(
                    onPressed: widget.onOpen,
                    style: TextButton.styleFrom(foregroundColor: AppColors.textSecondary),
                    icon: const Icon(Icons.mode_comment_outlined, size: 19),
                    label: Text('${p.commentCount}', style: const TextStyle(fontWeight: FontWeight.w700)),
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
    final staff = ref.watch(canChatMuteProvider).valueOrNull == true;

    Widget body;
    if (p == null) {
      body = Center(
        child: _error == null
            ? const CircularProgressIndicator(color: AppColors.accentViolet, strokeWidth: 3)
            : Text(_error!, style: const TextStyle(color: AppColors.textSecondary)),
      );
    } else {
      body = ListView(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 16),
        children: [
          FeedPostCard(
            post: p,
            onChanged: _setPost,
            onDeleted: (id) {
              widget.onDeleted?.call(id);
              Navigator.of(context).maybePop();
            },
          ),
          const Padding(
            padding: EdgeInsets.fromLTRB(4, 4, 4, 8),
            child: Text('Komentar', style: TextStyle(color: AppColors.textWhite, fontWeight: FontWeight.w800)),
          ),
          if (_loadingComments)
            const Padding(
              padding: EdgeInsets.all(20),
              child: Center(child: CircularProgressIndicator(color: AppColors.accentViolet, strokeWidth: 2.5)),
            )
          else if (_comments.isEmpty)
            const Padding(
              padding: EdgeInsets.all(20),
              child: Center(child: Text('Belum ada komentar.', style: TextStyle(color: AppColors.textMuted))),
            )
          else ...[
            for (final c in _comments)
              _CommentTile(
                comment: c,
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
        foregroundColor: AppColors.textWhite,
        title: const Text('Postingan', style: TextStyle(fontWeight: FontWeight.w800)),
      ),
      body: Column(
        children: [
          Expanded(child: body),
          if (p != null)
            Container(
              color: AppColors.backgroundDarkSecondary,
              padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
              child: SafeArea(
                top: false,
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _input,
                        maxLength: 500,
                        minLines: 1,
                        maxLines: 4,
                        style: const TextStyle(color: AppColors.textWhite, fontSize: 14),
                        decoration: InputDecoration(
                          counterText: '',
                          isDense: true,
                          hintText: 'Tulis komentar...',
                          hintStyle: const TextStyle(color: AppColors.textMuted),
                          filled: true,
                          fillColor: AppColors.surfaceDark,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(22), borderSide: BorderSide.none),
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    IconButton.filled(
                      onPressed: _sending ? null : _send,
                      style: IconButton.styleFrom(backgroundColor: AppColors.accentViolet),
                      icon: _sending
                          ? const SizedBox.square(
                              dimension: 18,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                            )
                          : const Icon(Icons.send_rounded, color: Colors.white, size: 20),
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
  const _CommentTile({required this.comment, required this.canDelete, required this.onDelete});

  final FeedComment comment;
  final bool canDelete;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final c = comment;
    return GestureDetector(
      onLongPress: !canDelete
          ? null
          : () => showModalBottomSheet<void>(
                context: context,
                backgroundColor: AppColors.surfaceDark,
                builder: (ctx) => SafeArea(
                  child: ListTile(
                    leading: const Icon(Icons.delete_outline, color: AppColors.errorRed),
                    title: const Text('Hapus komentar', style: TextStyle(color: AppColors.errorRed)),
                    onTap: () {
                      Navigator.pop(ctx);
                      onDelete();
                    },
                  ),
                ),
              ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 7),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            GestureDetector(
              onTap: () => openPublicProfile(context, c.uid),
              child: FriendAvatar(url: c.avatarUrl, seed: c.uid, label: c.username, size: 32, framed: false),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: AppColors.surfaceCard,
                  borderRadius: BorderRadius.circular(14),
                ),
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
                              color: _hex(c.usernameColor) ?? AppColors.accentVioletLight,
                              fontWeight: FontWeight.w800,
                              fontSize: 12.5,
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(_ago(c.createdAt), style: const TextStyle(color: AppColors.textMuted, fontSize: 10.5)),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(c.body, style: const TextStyle(color: AppColors.textWhite, fontSize: 13.5, height: 1.35)),
                  ],
                ),
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
    return Scaffold(
      backgroundColor: AppColors.backgroundDark,
      appBar: AppBar(
        backgroundColor: AppColors.backgroundDark,
        foregroundColor: AppColors.textWhite,
        title: const Text('Postingan baru', style: TextStyle(fontWeight: FontWeight.w800)),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 10),
            child: FilledButton(
              onPressed: _posting ? null : _post,
              style: FilledButton.styleFrom(backgroundColor: AppColors.accentViolet),
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
            ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            controller: _text,
            autofocus: true,
            maxLength: 1000,
            minLines: 4,
            maxLines: 12,
            style: const TextStyle(color: AppColors.textWhite, fontSize: 15, height: 1.4),
            decoration: InputDecoration(
              hintText: 'Lagi nonton apa? Ceritain dong...',
              hintStyle: const TextStyle(color: AppColors.textMuted),
              filled: true,
              fillColor: AppColors.surfaceCard,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
            ),
          ),
          const SizedBox(height: 12),
          if (path == null)
            OutlinedButton.icon(
              onPressed: _posting ? null : _pick,
              icon: const Icon(Icons.image_outlined),
              label: const Text('Tambah gambar'),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.accentVioletLight,
                side: BorderSide(color: AppColors.accentViolet.withValues(alpha: 0.5)),
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
            )
          else
            Stack(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(14),
                  child: Image.file(File(path), fit: BoxFit.cover, width: double.infinity),
                ),
                Positioned(
                  top: 8,
                  right: 8,
                  child: IconButton.filled(
                    onPressed: _posting ? null : () => setState(() => _imagePath = null),
                    style: IconButton.styleFrom(backgroundColor: Colors.black54),
                    icon: const Icon(Icons.close_rounded, color: Colors.white, size: 20),
                  ),
                ),
              ],
            ),
          const SizedBox(height: 14),
          const Text(
            'Postingan bisa dilihat semua pengguna. Jaga sopan santun ya; postingan yang melanggar akan dihapus.',
            style: TextStyle(color: AppColors.textMuted, fontSize: 12, height: 1.4),
          ),
        ],
      ),
    );
  }
}

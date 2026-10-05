import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/error_message.dart';
import '../../../data/models/chat_models.dart';
import '../../../data/models/comment_models.dart';
import '../../../providers.dart';

const int kMaxCommentLength = 300;

/// Argumen: (episodeId, animeId). Dikunci per episode, jadi pindah episode
/// otomatis dapat thread komentar baru.
typedef CommentsArgs = (String, String);

class CommentsUiState {
  const CommentsUiState({
    this.isLoading = true,
    this.isSending = false,
    this.errorMessage,
    this.totalCount = 0,
    this.sortTop = false,
    this.topLevel = const [],
    this.repliesByParent = const {},
    this.openThreadParentId,
    this.replyTarget,
    this.deletingCommentId,
    this.premiumUids = const {},
    this.levels = const {},
    this.userNumbers = const {},
    this.avatarUrls = const {},
  });

  final bool isLoading;
  final bool isSending;
  final String? errorMessage;
  final int totalCount;

  /// false = tab "Terbaru", true = tab "Top Comment".
  final bool sortTop;
  final List<EpisodeComment> topLevel;
  final Map<int, List<EpisodeComment>> repliesByParent;

  /// Thread yang sedang dibuka di sheet "Threads" (null = tertutup).
  final int? openThreadParentId;

  /// Balasan yang ditarget di dalam thread (null = balas komentar utama).
  final EpisodeComment? replyTarget;
  final int? deletingCommentId;

  final Set<String> premiumUids;
  final Map<String, int> levels;
  final Map<String, int> userNumbers;
  final Map<String, String> avatarUrls;

  List<EpisodeComment> get sortedTopLevel {
    if (!sortTop) return topLevel;
    final list = [...topLevel];
    list.sort((a, b) {
      if (a.isPinned != b.isPinned) return a.isPinned ? -1 : 1;
      final ra = repliesByParent[a.id]?.length ?? 0;
      final rb = repliesByParent[b.id]?.length ?? 0;
      return rb.compareTo(ra);
    });
    return list;
  }

  CommentsUiState copyWith({
    bool? isLoading,
    bool? isSending,
    String? Function()? errorMessage,
    int? totalCount,
    bool? sortTop,
    List<EpisodeComment>? topLevel,
    Map<int, List<EpisodeComment>>? repliesByParent,
    int? Function()? openThreadParentId,
    EpisodeComment? Function()? replyTarget,
    int? Function()? deletingCommentId,
    Set<String>? premiumUids,
    Map<String, int>? levels,
    Map<String, int>? userNumbers,
    Map<String, String>? avatarUrls,
  }) {
    return CommentsUiState(
      isLoading: isLoading ?? this.isLoading,
      isSending: isSending ?? this.isSending,
      errorMessage: errorMessage != null ? errorMessage() : this.errorMessage,
      totalCount: totalCount ?? this.totalCount,
      sortTop: sortTop ?? this.sortTop,
      topLevel: topLevel ?? this.topLevel,
      repliesByParent: repliesByParent ?? this.repliesByParent,
      openThreadParentId:
          openThreadParentId != null ? openThreadParentId() : this.openThreadParentId,
      replyTarget: replyTarget != null ? replyTarget() : this.replyTarget,
      deletingCommentId:
          deletingCommentId != null ? deletingCommentId() : this.deletingCommentId,
      premiumUids: premiumUids ?? this.premiumUids,
      levels: levels ?? this.levels,
      userNumbers: userNumbers ?? this.userNumbers,
      avatarUrls: avatarUrls ?? this.avatarUrls,
    );
  }
}

/// Port CommentsViewModel.kt. Identitas pengirim diambil dari profil Chat
/// Global (`chat_profiles`) supaya konsisten dengan Chat/Profil.
class CommentsController
    extends AutoDisposeFamilyNotifier<CommentsUiState, CommentsArgs> {
  bool _alive = true;
  final Set<String> _badgeChecked = {};

  String get _episodeId => arg.$1;
  String get _animeId => arg.$2;

  @override
  CommentsUiState build(CommentsArgs arg) {
    _alive = true;
    ref.onDispose(() => _alive = false);
    Future.microtask(refresh);
    return const CommentsUiState();
  }

  void _update(CommentsUiState Function(CommentsUiState s) f) {
    if (_alive) state = f(state);
  }

  Future<void> refresh() async {
    _update((s) => s.copyWith(isLoading: true, errorMessage: () => null));
    try {
      final r = await ref.read(commentRepositoryProvider).getComments(_episodeId);
      _update((s) => s.copyWith(
            isLoading: false,
            topLevel: r.topLevel,
            repliesByParent: r.repliesByParent,
            totalCount: r.totalCount,
          ));
      unawaited(_loadBadges([
        ...r.topLevel,
        ...r.repliesByParent.values.expand((e) => e),
      ]));
    } catch (e) {
      _update((s) => s.copyWith(
            isLoading: false,
            errorMessage: () => errorMessage(e, 'Gagal memuat komentar'),
          ));
    }
  }

  void setSortTop(bool top) => _update((s) => s.copyWith(sortTop: top));

  void openThread(int parentId) => _update(
        (s) => s.copyWith(openThreadParentId: () => parentId, replyTarget: () => null),
      );

  void closeThread() => _update(
        (s) => s.copyWith(openThreadParentId: () => null, replyTarget: () => null),
      );

  void setReplyTarget(EpisodeComment? target) =>
      _update((s) => s.copyWith(replyTarget: () => target));

  void clearError() => _update((s) => s.copyWith(errorMessage: () => null));

  Future<void> postTopLevel(
    String text, {
    bool pinned = false,
    CommentMeta meta = const CommentMeta(),
  }) =>
      _post(text: text, pinned: pinned, meta: meta);

  Future<void> postReply(String text, {CommentMeta meta = const CommentMeta()}) {
    final threadId = state.openThreadParentId;
    if (threadId == null) return Future.value();
    return _post(
      text: text,
      parentId: threadId,
      replyToUsername: state.replyTarget?.username,
      meta: meta,
    );
  }

  Future<void> _post({
    required String text,
    int? parentId,
    String? replyToUsername,
    bool pinned = false,
    required CommentMeta meta,
  }) async {
    final trimmed = text.trim();
    final body = trimmed.length > kMaxCommentLength
        ? trimmed.substring(0, kMaxCommentLength)
        : trimmed;
    if (body.isEmpty || state.isSending) return;

    final user = ref.read(authUserProvider).valueOrNull;
    if (user == null) {
      _update((s) => s.copyWith(errorMessage: () => 'Masuk dulu untuk berkomentar'));
      return;
    }

    _update((s) => s.copyWith(isSending: true, errorMessage: () => null));
    try {
      final profile = await ref.read(chatProfileProvider(user.uid).future);
      final username = (profile?.username.isNotEmpty ?? false)
          ? profile!.username
          : ((user.displayName?.isNotEmpty ?? false) ? user.displayName! : 'Pengguna');
      // Sorotan mahkota cuma efektif buat Premium -- dicek ulang di sini.
      final isPremium = ref.read(myPremiumProvider).valueOrNull ?? false;

      final inserted = await ref.read(commentRepositoryProvider).postComment(
            episodeId: _episodeId,
            animeId: _animeId,
            firebaseUid: user.uid,
            username: username,
            avatarUrl: profile?.avatarUrl,
            comment: body,
            parentId: parentId,
            replyToUsername: replyToUsername,
            isPinned: pinned && isPremium,
            meta: meta,
          );

      if (parentId == null) {
        _update((s) => s.copyWith(
              isSending: false,
              topLevel: [inserted, ...s.topLevel],
              totalCount: s.totalCount + 1,
            ));
      } else {
        _update((s) {
          final map = {...s.repliesByParent};
          map[parentId] = [...(map[parentId] ?? const []), inserted];
          return s.copyWith(
            isSending: false,
            repliesByParent: map,
            replyTarget: () => null,
            totalCount: s.totalCount + 1,
          );
        });
      }
      unawaited(_loadBadges([inserted]));
    } catch (e) {
      _update((s) => s.copyWith(
            isSending: false,
            errorMessage: () => errorMessage(e, 'Gagal mengirim komentar'),
          ));
    }
  }

  Future<void> deleteComment(EpisodeComment c) async {
    final uid = ref.read(authUserProvider).valueOrNull?.uid ?? '';
    if (uid.isEmpty || c.firebaseUid != uid) return;
    _update((s) => s.copyWith(deletingCommentId: () => c.id));
    try {
      await ref.read(commentRepositoryProvider).deleteComment(c.id, uid);
      _update((s) {
        final p = c.parentId;
        if (p == null) {
          return s.copyWith(
            topLevel: s.topLevel.where((e) => e.id != c.id).toList(),
            deletingCommentId: () => null,
            totalCount: s.totalCount > 0 ? s.totalCount - 1 : 0,
          );
        }
        final map = {...s.repliesByParent};
        map[p] = (map[p] ?? const []).where((e) => e.id != c.id).toList();
        return s.copyWith(
          repliesByParent: map,
          deletingCommentId: () => null,
          totalCount: s.totalCount > 0 ? s.totalCount - 1 : 0,
        );
      });
    } catch (e) {
      _update((s) => s.copyWith(
            deletingCommentId: () => null,
            errorMessage: () => errorMessage(e, 'Gagal menghapus komentar'),
          ));
    }
  }

  /// Level / Premium / ID urut / avatar terkini untuk pengirim baru.
  Future<void> _loadBadges(List<EpisodeComment> comments) async {
    final fresh = comments
        .map((c) => c.firebaseUid)
        .where((u) => u.isNotEmpty && !_badgeChecked.contains(u))
        .toSet()
        .toList();
    if (fresh.isEmpty) return;
    _badgeChecked.addAll(fresh);

    try {
      final xp = ref.read(xpRepositoryProvider);
      final chat = ref.read(chatRepositoryProvider);
      // Tiga request jalan paralel; gagal salah satu tidak menggagalkan yang lain.
      final levelsF = xp.getLevelsForUids(fresh).catchError((_) => <String, int>{});
      final premiumF = xp.getPremiumUids(fresh).catchError((_) => <String>{});
      final profilesF =
          chat.getProfilesForUids(fresh).catchError((_) => <String, ChatProfile>{});
      final levels = await levelsF;
      final premiums = await premiumF;
      final profiles = await profilesF;

      final numbers = <String, int>{};
      final avatars = <String, String>{};
      profiles.forEach((uid, p) {
        final n = p.userNumber;
        final a = p.avatarUrl;
        if (n != null) numbers[uid] = n;
        if (a != null && a.isNotEmpty) avatars[uid] = a;
      });

      _update((s) => s.copyWith(
            levels: {...s.levels, ...levels},
            premiumUids: {...s.premiumUids, ...premiums},
            userNumbers: {...s.userNumbers, ...numbers},
            avatarUrls: {...s.avatarUrls, ...avatars},
          ));
    } catch (_) {
      // Badge best effort: komentar tetap tampil tanpa badge.
    }
  }
}

final commentsControllerProvider = NotifierProvider.autoDispose
    .family<CommentsController, CommentsUiState, CommentsArgs>(CommentsController.new);

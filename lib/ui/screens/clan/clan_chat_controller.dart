import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/error_message.dart';
import '../../../data/models/chat_models.dart';
import '../../../data/models/clan_chat_models.dart';
import '../../../providers.dart';
import '../chat/chat_mention.dart' show chatMentionRepositoryProvider;

const int kClanChatMaxLength = 500;

class ClanChatState {
  const ClanChatState({
    this.isLoading = true,
    this.error,
    this.messages = const [],
    this.profiles = const {},
    this.levels = const {},
    this.clanTags = const {},
    this.premiumUids = const {},
    this.isSending = false,
    this.sendError,
    this.replyTarget,
  });

  final bool isLoading;
  final String? error;

  /// Urut lama -> baru.
  final List<ClanMessage> messages;
  final Map<String, ChatProfile> profiles;

  /// Badge seperti Chat Global: level XP, tag clan, centang Premium.
  final Map<String, int> levels;
  final Map<String, String> clanTags;
  final Set<String> premiumUids;
  final bool isSending;
  final String? sendError;
  final ClanMessage? replyTarget;

  ClanChatState copyWith({
    bool? isLoading,
    String? Function()? error,
    List<ClanMessage>? messages,
    Map<String, ChatProfile>? profiles,
    Map<String, int>? levels,
    Map<String, String>? clanTags,
    Set<String>? premiumUids,
    bool? isSending,
    String? Function()? sendError,
    ClanMessage? Function()? replyTarget,
  }) {
    return ClanChatState(
      isLoading: isLoading ?? this.isLoading,
      error: error != null ? error() : this.error,
      messages: messages ?? this.messages,
      profiles: profiles ?? this.profiles,
      levels: levels ?? this.levels,
      clanTags: clanTags ?? this.clanTags,
      premiumUids: premiumUids ?? this.premiumUids,
      isSending: isSending ?? this.isSending,
      sendError: sendError != null ? sendError() : this.sendError,
      replyTarget: replyTarget != null ? replyTarget() : this.replyTarget,
    );
  }
}

/// Chat clan: muat awal, lalu cek pesan baru tiap beberapa detik selama
/// layar terbuka (Realtime sengaja tidak dipakai: tabel tertutup dari klien).
class ClanChatController extends AutoDisposeNotifier<ClanChatState> {
  bool _alive = true;
  bool _busy = false;
  bool _active = true;
  Timer? _poll;

  @override
  ClanChatState build() {
    _alive = true;
    ref.onDispose(() {
      _alive = false;
      _poll?.cancel();
    });
    Future.microtask(_start);
    return const ClanChatState();
  }

  void _update(ClanChatState Function(ClanChatState s) f) {
    if (_alive) state = f(state);
  }

  Future<void> _start() async {
    await _fetch(initial: true);
    _poll?.cancel();
    _poll = Timer.periodic(const Duration(seconds: 4), (_) {
      if (_active) _fetch();
    });
  }

  /// Dipanggil layar saat app ke background/foreground.
  void setActive(bool active) {
    _active = active;
    if (active) _fetch();
  }

  Future<void> retry() {
    _update((s) => s.copyWith(isLoading: true, error: () => null));
    return _fetch(initial: true);
  }

  Future<void> _fetch({bool initial = false}) async {
    if (_busy || !_alive) return;
    _busy = true;
    try {
      final last = state.messages.isEmpty ? null : state.messages.last.id;
      final page = await ref
          .read(clanChatRepositoryProvider)
          .list(afterId: initial ? null : last);
      if (!_alive) return;
      var list = initial ? <ClanMessage>[] : [...state.messages];
      final known = list.map((m) => m.id).toSet();
      for (final m in page.messages) {
        if (known.add(m.id)) list.add(m);
      }
      if (page.deletedIds.isNotEmpty) {
        list = list.where((m) => !page.deletedIds.contains(m.id)).toList();
      }
      list.sort((a, b) => a.id.compareTo(b.id));
      _update((s) => s.copyWith(isLoading: false, error: () => null, messages: list));
      unawaited(_loadProfiles(list));
    } catch (e) {
      // Gagal saat polling diam saja; error cuma ditampilkan kalau belum ada data.
      if (initial || state.messages.isEmpty) {
        _update((s) => s.copyWith(
              isLoading: false,
              error: () => errorMessage(e, 'Gagal memuat chat clan'),
            ));
      }
    } finally {
      _busy = false;
    }
  }

  /// uid yang badge-nya (level / tag clan / Premium) sudah diambil.
  final Set<String> _badgeChecked = {};

  Future<void> _loadProfiles(List<ClanMessage> list) async {
    final uids = list.map((m) => m.firebaseUid).where((u) => u.isNotEmpty).toSet();
    final missing = uids.where((u) => !state.profiles.containsKey(u)).toList();
    final badgeMissing = uids.where((u) => !_badgeChecked.contains(u)).toList();
    _badgeChecked.addAll(badgeMissing);

    // Semua diambil bersamaan lalu dipasang sekali (seperti Chat Global);
    // masing-masing boleh gagal sendiri.
    final chat = ref.read(chatRepositoryProvider);
    final xp = ref.read(xpRepositoryProvider);
    final profilesF = missing.isEmpty
        ? Future.value(const <String, ChatProfile>{})
        : chat.getProfilesForUids(missing).catchError((Object _) => const <String, ChatProfile>{});
    final levelsF = badgeMissing.isEmpty
        ? Future.value(const <String, int>{})
        : xp.getLevelsForUids(badgeMissing).catchError((Object _) => const <String, int>{});
    final tagsF = badgeMissing.isEmpty
        ? Future.value(const <String, String>{})
        : chat.getClanTagsForUids(badgeMissing).catchError((Object _) => const <String, String>{});
    final premiumF = badgeMissing.isEmpty
        ? Future.value(const <String>{})
        : xp.getPremiumUids(badgeMissing).catchError((Object _) => const <String>{});

    final got = await profilesF;
    final levels = await levelsF;
    final tags = await tagsF;
    final premium = await premiumF;
    if (got.isEmpty && levels.isEmpty && tags.isEmpty && premium.isEmpty) return;
    _update((s) => s.copyWith(
          profiles: got.isEmpty ? null : {...s.profiles, ...got},
          levels: levels.isEmpty ? null : {...s.levels, ...levels},
          clanTags: tags.isEmpty ? null : {...s.clanTags, ...tags},
          premiumUids: premium.isEmpty ? null : {...s.premiumUids, ...premium},
        ));
  }

  void setReplyTarget(ClanMessage? m) => _update((s) => s.copyWith(replyTarget: () => m));

  /// [mentionUids]: teman yang di-mention (@nama) -> dapat notif.
  Future<bool> send(String raw, {List<String> mentionUids = const []}) async {
    final text = raw.trim();
    if (text.isEmpty || state.isSending) return false;
    _update((s) => s.copyWith(isSending: true, sendError: () => null));
    try {
      final sent = await ref
          .read(clanChatRepositoryProvider)
          .send(text, replyToId: state.replyTarget?.id);
      _update((s) {
        final has = s.messages.any((m) => m.id == sent.id);
        return s.copyWith(
          isSending: false,
          replyTarget: () => null,
          messages: has ? s.messages : [...s.messages, sent],
        );
      });
      unawaited(_loadProfiles(state.messages));
      if (mentionUids.isNotEmpty) {
        unawaited(ref.read(chatMentionRepositoryProvider).notify('clan', sent.id, mentionUids));
      }
      return true;
    } catch (e) {
      _update((s) => s.copyWith(
            isSending: false,
            sendError: () => errorMessage(e, 'Gagal mengirim pesan'),
          ));
      return false;
    }
  }

  Future<void> delete(ClanMessage m) async {
    try {
      await ref.read(clanChatRepositoryProvider).delete(m.id);
      _update((s) => s.copyWith(
            messages: s.messages.where((x) => x.id != m.id).toList(),
            replyTarget: () => s.replyTarget?.id == m.id ? null : s.replyTarget,
          ));
    } catch (e) {
      _update((s) => s.copyWith(sendError: () => errorMessage(e, 'Gagal menghapus pesan')));
    }
  }
}

final clanChatControllerProvider =
    NotifierProvider.autoDispose<ClanChatController, ClanChatState>(
  ClanChatController.new,
);

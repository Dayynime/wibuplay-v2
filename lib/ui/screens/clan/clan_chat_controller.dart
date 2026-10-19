import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/error_message.dart';
import '../../../data/models/chat_models.dart';
import '../../../data/models/clan_chat_models.dart';
import '../../../providers.dart';

const int kClanChatMaxLength = 500;

class ClanChatState {
  const ClanChatState({
    this.isLoading = true,
    this.error,
    this.messages = const [],
    this.profiles = const {},
    this.isSending = false,
    this.sendError,
    this.replyTarget,
  });

  final bool isLoading;
  final String? error;

  /// Urut lama -> baru.
  final List<ClanMessage> messages;
  final Map<String, ChatProfile> profiles;
  final bool isSending;
  final String? sendError;
  final ClanMessage? replyTarget;

  ClanChatState copyWith({
    bool? isLoading,
    String? Function()? error,
    List<ClanMessage>? messages,
    Map<String, ChatProfile>? profiles,
    bool? isSending,
    String? Function()? sendError,
    ClanMessage? Function()? replyTarget,
  }) {
    return ClanChatState(
      isLoading: isLoading ?? this.isLoading,
      error: error != null ? error() : this.error,
      messages: messages ?? this.messages,
      profiles: profiles ?? this.profiles,
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

  Future<void> _loadProfiles(List<ClanMessage> list) async {
    final missing = list
        .map((m) => m.firebaseUid)
        .where((u) => !state.profiles.containsKey(u))
        .toSet()
        .toList();
    if (missing.isEmpty) return;
    try {
      final got = await ref.read(chatRepositoryProvider).getProfilesForUids(missing);
      if (got.isEmpty) return;
      _update((s) => s.copyWith(profiles: {...s.profiles, ...got}));
    } catch (_) {}
  }

  void setReplyTarget(ClanMessage? m) => _update((s) => s.copyWith(replyTarget: () => m));

  Future<bool> send(String raw) async {
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

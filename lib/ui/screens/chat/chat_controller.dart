import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/models/chat_models.dart';
import '../../../data/realtime/chat_realtime_client.dart';
import '../../../data/repository/chat_repository.dart';
import '../../../providers.dart';

const int _cooldownSeconds = 5;
const int _maxMessageLength = 300;
const int _maxMessagesInMemory = 200;

/// State Chat Global. Port ChatUiState di ChatViewModel.kt (versi inti:
/// kirim teks, balas, hapus pesan sendiri, realtime, badge warna/ID/avatar).
class ChatUiState {
  const ChatUiState({
    this.messages = const [],
    this.isLoading = true,
    this.isSending = false,
    this.errorMessage,
    this.cooldownSeconds = 0,
    this.replyTarget,
    this.usernameColors = const {},
    this.userNumbers = const {},
    this.avatarUrls = const {},
    this.myUid = '',
    this.myUsername = '',
    this.myAvatarUrl,
  });

  final List<ChatMessage> messages;
  final bool isLoading;
  final bool isSending;
  final String? errorMessage;
  final int cooldownSeconds;
  final ChatMessage? replyTarget;
  final Map<String, String> usernameColors;
  final Map<String, int> userNumbers;
  final Map<String, String> avatarUrls;
  final String myUid;
  final String myUsername;
  final String? myAvatarUrl;

  /// Parameter berupa fungsi supaya bisa mengisi null secara eksplisit.
  ChatUiState copyWith({
    List<ChatMessage>? messages,
    bool? isLoading,
    bool? isSending,
    String? Function()? errorMessage,
    int? cooldownSeconds,
    ChatMessage? Function()? replyTarget,
    Map<String, String>? usernameColors,
    Map<String, int>? userNumbers,
    Map<String, String>? avatarUrls,
    String? myUsername,
    String? myAvatarUrl,
  }) {
    return ChatUiState(
      messages: messages ?? this.messages,
      isLoading: isLoading ?? this.isLoading,
      isSending: isSending ?? this.isSending,
      errorMessage: errorMessage != null ? errorMessage() : this.errorMessage,
      cooldownSeconds: cooldownSeconds ?? this.cooldownSeconds,
      replyTarget: replyTarget != null ? replyTarget() : this.replyTarget,
      usernameColors: usernameColors ?? this.usernameColors,
      userNumbers: userNumbers ?? this.userNumbers,
      avatarUrls: avatarUrls ?? this.avatarUrls,
      myUid: myUid,
      myUsername: myUsername ?? this.myUsername,
      myAvatarUrl: myAvatarUrl ?? this.myAvatarUrl,
    );
  }
}

class ChatController extends AutoDisposeNotifier<ChatUiState> {
  bool _alive = true;
  ChatRealtimeClient? _realtime;
  StreamSubscription<ChatRealtimeEvent>? _realtimeSub;
  Timer? _resyncTimer;
  Timer? _cooldownTimer;
  final Set<String> _badgeChecked = {};

  ChatRepository get _repo => ref.read(chatRepositoryProvider);

  @override
  ChatUiState build() {
    _alive = true;
    ref.onDispose(_dispose);
    final user = ref.read(authRepositoryProvider).currentUser;
    Future.microtask(_init);
    final name = user?.displayName;
    return ChatUiState(
      myUid: user?.uid ?? '',
      myUsername: (name != null && name.trim().isNotEmpty) ? name.trim() : 'Pengguna',
      myAvatarUrl: user?.photoURL,
    );
  }

  void _dispose() {
    _alive = false;
    _resyncTimer?.cancel();
    _cooldownTimer?.cancel();
    _realtimeSub?.cancel();
    _realtime?.stop();
  }

  void _update(ChatUiState Function(ChatUiState s) f) {
    if (_alive) state = f(state);
  }

  Future<void> _init() async {
    if (state.myUid.isEmpty) {
      _update((s) => s.copyWith(
            isLoading: false,
            errorMessage: () => 'Kamu harus login dulu.',
          ));
      return;
    }
    // Profil bersama Zenime: pakai username/avatar yang sudah ada kalau ada.
    try {
      await _repo.ensureProfile(state.myUid, state.myUsername, state.myAvatarUrl);
      final profile = await _repo.getProfile(state.myUid);
      if (profile != null && profile.username.isNotEmpty) {
        _update((s) => s.copyWith(
              myUsername: profile.username,
              myAvatarUrl: profile.avatarUrl,
            ));
      }
    } catch (_) {}

    await _refresh(initial: true);
    if (!_alive) return;
    _startRealtime();
    // Jaring pengaman jarang-jarang (bukan polling tiap beberapa detik).
    _resyncTimer = Timer.periodic(const Duration(seconds: 60), (_) => _refresh());
  }

  Future<void> _refresh({bool initial = false}) async {
    try {
      final fetched = await _repo.getMessages(limit: 50);
      if (!_alive) return;
      final merged = _merge(state.messages, fetched);
      _update((s) => s.copyWith(
            messages: merged,
            isLoading: false,
            errorMessage: initial ? () => null : null,
          ));
      _checkBadges(merged);
    } catch (e) {
      if (!_alive) return;
      if (initial) {
        _update((s) => s.copyWith(
              isLoading: false,
              errorMessage: () => _friendly(e, 'Gagal memuat chat'),
            ));
      }
    }
  }

  /// Gabungkan hasil server (50 terbaru) dengan pesan yang sudah di memori.
  /// Pesan lama (id di bawah jendela server) dipertahankan; pesan di dalam
  /// jendela diambil dari server, jadi pesan yang sudah dihapus ikut hilang.
  List<ChatMessage> _merge(List<ChatMessage> current, List<ChatMessage> fetched) {
    if (fetched.isEmpty) return current;
    final minId = fetched.map((m) => m.id).reduce((a, b) => a < b ? a : b);
    final older = current.where((m) => m.id < minId);
    final all = <ChatMessage>[...older, ...fetched]..sort((a, b) => a.id.compareTo(b.id));
    return all.length > _maxMessagesInMemory
        ? all.sublist(all.length - _maxMessagesInMemory)
        : all;
  }

  void _startRealtime() {
    final client = ChatRealtimeClient();
    _realtime = client;
    _realtimeSub = client.events.listen(_onRealtime);
    client.start();
  }

  void _onRealtime(ChatRealtimeEvent event) {
    if (!_alive) return;
    if (event is ChatInserted) {
      final msg = event.message;
      if (state.messages.any((m) => m.id == msg.id)) return;
      var updated = [...state.messages, msg];
      if (updated.length > _maxMessagesInMemory) {
        updated = updated.sublist(updated.length - _maxMessagesInMemory);
      }
      _update((s) => s.copyWith(messages: updated, isLoading: false));
      _checkBadges([msg]);
    } else if (event is ChatDeleted) {
      _update((s) => s.copyWith(
            messages: s.messages.where((m) => m.id != event.id).toList(),
          ));
    }
  }

  /// Ambil warna username, ID urut, dan avatar terkini untuk pengirim baru
  /// (1 request batch). Gagal -> dicoba lagi di refresh berikutnya.
  void _checkBadges(List<ChatMessage> messages) {
    final fresh = messages
        .map((m) => m.firebaseUid)
        .where((u) => u.isNotEmpty && !_badgeChecked.contains(u))
        .toSet()
        .toList();
    if (fresh.isEmpty) return;
    _badgeChecked.addAll(fresh);
    () async {
      try {
        final data = await _repo.getBadgeData(fresh);
        _update((s) => s.copyWith(
              usernameColors: {...s.usernameColors, ...data.usernameColors},
              userNumbers: {...s.userNumbers, ...data.userNumbers},
              avatarUrls: {...s.avatarUrls, ...data.avatarUrls},
            ));
      } catch (_) {
        _badgeChecked.removeAll(fresh);
      }
    }();
  }

  // ------------------------------------------------------------------ aksi

  /// Return true kalau pesan terkirim (UI mengosongkan kolom input).
  Future<bool> send(String text) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return false;
    if (state.cooldownSeconds > 0 || state.isSending) return false;
    final safe =
        trimmed.length > _maxMessageLength ? trimmed.substring(0, _maxMessageLength) : trimmed;
    final reply = state.replyTarget;

    _update((s) => s.copyWith(isSending: true, errorMessage: () => null));
    try {
      final sent = await _repo.sendMessage(
        firebaseUid: state.myUid,
        username: state.myUsername,
        avatarUrl: state.myAvatarUrl,
        message: safe,
        replyToId: reply?.id,
        replyToUsername: reply?.username,
        replyToMessage: reply?.message,
      );
      if (!_alive) return true;
      final exists = state.messages.any((m) => m.id == sent.id);
      _update((s) => s.copyWith(
            messages: exists ? s.messages : [...s.messages, sent],
            isSending: false,
            replyTarget: () => null,
          ));
      _checkBadges([sent]);
      _startCooldown();
      return true;
    } catch (e) {
      // Gagal kirim: tidak kena cooldown, user bisa langsung coba lagi.
      _update((s) => s.copyWith(
            isSending: false,
            errorMessage: () => _friendly(e, 'Gagal mengirim pesan'),
          ));
      return false;
    }
  }

  void _startCooldown() {
    _cooldownTimer?.cancel();
    var remaining = _cooldownSeconds;
    _update((s) => s.copyWith(cooldownSeconds: remaining));
    _cooldownTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      remaining--;
      if (remaining <= 0) {
        t.cancel();
        _update((s) => s.copyWith(cooldownSeconds: 0));
      } else {
        _update((s) => s.copyWith(cooldownSeconds: remaining));
      }
    });
  }

  void setReplyTarget(ChatMessage message) =>
      _update((s) => s.copyWith(replyTarget: () => message));

  void clearReplyTarget() => _update((s) => s.copyWith(replyTarget: () => null));

  void clearError() => _update((s) => s.copyWith(errorMessage: () => null));

  /// Hapus pesan milik sendiri (hanya kalau firebase_uid cocok).
  Future<void> deleteMessage(ChatMessage message) async {
    if (message.firebaseUid != state.myUid) return;
    try {
      await _repo.deleteMessage(message.id, state.myUid);
      _update((s) => s.copyWith(
            messages: s.messages.where((m) => m.id != message.id).toList(),
          ));
    } catch (e) {
      _update((s) => s.copyWith(
            errorMessage: () => _friendly(e, 'Gagal menghapus pesan'),
          ));
    }
  }

  String _friendly(Object e, String fallback) {
    if (e is DioException) {
      switch (e.type) {
        case DioExceptionType.connectionTimeout:
        case DioExceptionType.sendTimeout:
        case DioExceptionType.receiveTimeout:
        case DioExceptionType.connectionError:
          return '$fallback: koneksi bermasalah, coba lagi.';
        default:
          final code = e.response?.statusCode;
          if (code == 401 || code == 403) return '$fallback: tidak punya izin (kode $code).';
          if (code != null) return '$fallback (kode $code).';
          return fallback;
      }
    }
    return fallback;
  }
}

final chatControllerProvider =
    NotifierProvider.autoDispose<ChatController, ChatUiState>(ChatController.new);

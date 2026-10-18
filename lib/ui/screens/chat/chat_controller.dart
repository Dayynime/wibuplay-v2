import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/models/chat_models.dart';
import '../../../data/realtime/chat_realtime_client.dart';
import '../../../data/repository/chat_repository.dart';
import '../../../providers.dart';
import 'chat_session_cache.dart';

const int _cooldownSeconds = 5;
const int _maxMessageLength = 300;
const int _maxMessagesInMemory = 200;

/// Resync penuh cuma jaring pengaman (bukan mekanisme utama), sama seperti Zenime.
const int _resyncSeconds = 45;

/// State Chat Global. Port ChatUiState di ChatViewModel.kt (versi inti:
/// kirim teks, balas, hapus pesan (sendiri / semua kalau admin-developer),
/// realtime, badge warna/ID/avatar).
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
    this.levels = const {},
    this.clanTags = const {},
    this.premiumUids = const {},
    this.myUid = '',
    this.myUsername = '',
    this.myAvatarUrl,
    this.canDeleteOthers = false,
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
  final Map<String, int> levels;

  /// uid -> tag clan (cuma yang sedang gabung clan).
  final Map<String, String> clanTags;

  /// uid pengirim yang Premium (badge centang biru).
  final Set<String> premiumUids;
  final String myUid;
  final String myUsername;
  final String? myAvatarUrl;

  /// true kalau akun yang login role-nya admin/developer: boleh hapus pesan
  /// orang lain (sama seperti Zenime). Cuma gating UI, server cek ulang.
  final bool canDeleteOthers;

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
    Map<String, int>? levels,
    Map<String, String>? clanTags,
    Set<String>? premiumUids,
    String? myUsername,
    String? myAvatarUrl,
    bool? canDeleteOthers,
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
      levels: levels ?? this.levels,
      clanTags: clanTags ?? this.clanTags,
      premiumUids: premiumUids ?? this.premiumUids,
      myUid: myUid,
      myUsername: myUsername ?? this.myUsername,
      myAvatarUrl: myAvatarUrl ?? this.myAvatarUrl,
      canDeleteOthers: canDeleteOthers ?? this.canDeleteOthers,
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
    // Kalau pernah dimuat di sesi ini, langsung tampilkan pesan + badge dari
    // cache (tanpa spinner); fetch terbaru jalan di belakang dan menimpa.
    return ChatUiState(
      messages: ChatSessionCache.messages,
      isLoading: ChatSessionCache.messages.isEmpty,
      usernameColors: ChatSessionCache.usernameColors,
      userNumbers: ChatSessionCache.userNumbers,
      avatarUrls: ChatSessionCache.avatarUrls,
      levels: ChatSessionCache.levels,
      clanTags: ChatSessionCache.clanTags,
      premiumUids: ChatSessionCache.premiumUids,
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
    if (!_alive) return;
    state = f(state);
    ChatSessionCache.save(
      messages: state.messages,
      premiumUids: state.premiumUids,
      clanTags: state.clanTags,
      levels: state.levels,
      usernameColors: state.usernameColors,
      userNumbers: state.userNumbers,
      avatarUrls: state.avatarUrls,
    );
  }

  Future<void> _init() async {
    if (state.myUid.isEmpty) {
      _update((s) => s.copyWith(
            isLoading: false,
            errorMessage: () => 'Kamu harus login dulu.',
          ));
      return;
    }
    if (!_alive) return;
    // Sama seperti Zenime: profil, fetch awal, realtime, dan resync dimulai
    // BERSAMAAN. Realtime + resync tidak boleh menunggu request profil/fetch
    // (kalau salah satunya lambat/timeout, chat jadi tidak live sama sekali).
    unawaited(_loadProfile());
    unawaited(_loadMyRole());
    unawaited(_refresh(initial: true));
    _startRealtime();
    // Jaring pengaman jarang-jarang (bukan polling tiap beberapa detik).
    _resyncTimer = Timer.periodic(
      const Duration(seconds: _resyncSeconds),
      (_) => _refresh(),
    );
  }

  /// Dipanggil dialog Edit Profil Chat setelah tersimpan di server: langsung
  /// perbarui username/avatar/warna sendiri di layar (dan untuk pesan yang
  /// dikirim berikutnya) tanpa menunggu refresh.
  void applyMyProfile({
    required String username,
    String? avatarUrl,
    String? usernameColor,
  }) {
    final uid = state.myUid;
    if (uid.isEmpty) return;
    _update((s) {
      final colors = Map<String, String>.from(s.usernameColors);
      if (usernameColor != null && usernameColor.isNotEmpty) {
        colors[uid] = usernameColor;
      } else {
        colors.remove(uid);
      }
      final avatars = Map<String, String>.from(s.avatarUrls);
      if (avatarUrl != null && avatarUrl.isNotEmpty) {
        avatars[uid] = avatarUrl;
      } else {
        avatars.remove(uid);
      }
      return s.copyWith(
        myUsername: username,
        myAvatarUrl: avatarUrl,
        usernameColors: colors,
        avatarUrls: avatars,
      );
    });
  }

  /// Profil bersama Zenime: pakai username/avatar yang sudah ada kalau ada.
  Future<void> _loadProfile() async {
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
  }

  Future<void> _refresh({bool initial = false}) async {
    try {
      final fetched = await _repo.getMessages(limit: 50);
      if (!_alive) return;
      // Sama seperti Zenime: hasil server MENGGANTIKAN list, jadi pesan yang
      // baru masuk muncul dan pesan yang sudah dihapus ikut hilang.
      _update((s) => s.copyWith(
            messages: fetched,
            isLoading: false,
            errorMessage: initial ? () => null : null,
          ));
      _checkBadges(fetched);
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

  void _startRealtime() {
    final client = ChatRealtimeClient();
    _realtime = client;
    _realtimeSub = client.events.listen(_onRealtime);
    client.start();
  }

  void _onRealtime(ChatRealtimeEvent event) {
    if (!_alive) return;
    if (event is ChatConnected) {
      // Socket baru saja subscribe (pertama kali atau setelah reconnect):
      // ambil ulang supaya pesan yang kelewat selama belum tersambung masuk.
      unawaited(_refresh());
    } else if (event is ChatInserted) {
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
      // Level XP (badge "Lv.N"). Gagal = badge level tidak tampil, tidak
      // menggagalkan badge warna/ID di atas.
      try {
        final levels = await ref.read(xpRepositoryProvider).getLevelsForUids(fresh);
        _update((s) => s.copyWith(levels: {...s.levels, ...levels}));
      } catch (_) {}
      // Tag clan (badge di bawah username). Gagal = tidak tampil.
      try {
        final tags = await _repo.getClanTagsForUids(fresh);
        _update((s) => s.copyWith(clanTags: {...s.clanTags, ...tags}));
      } catch (_) {}
      // Status Premium (centang biru di samping username). Gagal = tidak tampil.
      try {
        final premium = await ref.read(xpRepositoryProvider).getPremiumUids(fresh);
        _update((s) => s.copyWith(premiumUids: {...s.premiumUids, ...premium}));
      } catch (_) {}
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
      // Sama seperti Zenime: habis kirim, sinkron ulang dengan server.
      await _refresh();
      if (!_alive) return true;
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

  /// Cek role diri sendiri: nentuin boleh/nggaknya hapus pesan orang lain.
  /// Gagal = anggap user biasa (tombol hapus pesan orang tidak muncul).
  Future<void> _loadMyRole() async {
    try {
      final r = await ref.read(adminRepositoryProvider).getMyRole();
      final role = r.role;
      _update((s) => s.copyWith(
            canDeleteOthers: role == 'admin' || role == 'developer',
          ));
    } catch (_) {}
  }

  /// Pesan sendiri: hapus lewat Edge Function `chat-global`. Pesan ORANG LAIN:
  /// cuma kalau [ChatUiState.canDeleteOthers] (admin/developer), lewat Edge
  /// Function zenime-admin-delete-message -- role dicek ULANG di server.
  Future<void> deleteMessage(ChatMessage message) async {
    final isOwn = message.firebaseUid == state.myUid;
    if (!isOwn && !state.canDeleteOthers) return;
    try {
      if (isOwn) {
        await _repo.deleteMessage(message.id, state.myUid);
      } else {
        await ref.read(adminRepositoryProvider).deleteMessage(message.id);
      }
      _update((s) => s.copyWith(
            messages: s.messages.where((m) => m.id != message.id).toList(),
            replyTarget: s.replyTarget?.id == message.id ? () => null : null,
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

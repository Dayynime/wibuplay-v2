import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../../../core/premium_access.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/watch_xp_gate.dart';
import '../../../core/wp_video.dart';
import '../../../data/models/episode_item.dart';
import '../../../data/models/nobar_models.dart';
import '../../../data/models/stream_data.dart';
import '../../../data/realtime/chess_realtime_client.dart';
import '../../../data/repository/nobar_repository.dart';
import '../../../data/voice/nobar_voice.dart';
import '../../../providers.dart';
import '../../components/mini_player.dart';
import '../../components/net_image.dart';
import '../player/player_controller.dart';
import 'nobar_chat_panel.dart';
import 'nobar_invite.dart';
import 'nobar_voice_panel.dart';

/// Status video dari host yang sedang diikuti anggota.
class _SyncTarget {
  _SyncTarget(this.episodeId, this.positionMs, this.playing) : at = DateTime.now();
  final String episodeId;
  final int positionMs;
  final bool playing;
  final DateTime at;

  /// Perkiraan posisi host sekarang (+ ~150 ms jeda kirim).
  int get nowMs => playing ? positionMs + DateTime.now().difference(at).inMilliseconds + 150 : positionMs;
}

/// Layar Nobar: video yang dikontrol host + voice chat maks 5 orang.
///
/// Sinkron video lewat Realtime Broadcast topik `nobar-<id>`:
/// - host mengirim `sync` {ep, pos, playing} tiap 2 detik & setiap ada perubahan;
/// - anggota menyesuaikan: ganti episode, play/pause, dan seek kalau selisih
///   lebih dari 2 detik;
/// - anggota yang baru masuk mengirim `need_sync`, host langsung membalas.
/// Data room (anggota, host, kick) dari Edge Function `nobar-room`, dimuat ulang
/// saat ada `ping` dari server dan tiap 30 detik (sekaligus heartbeat).
class NobarScreen extends ConsumerStatefulWidget {
  const NobarScreen({super.key, required this.initial});

  final NobarRoom initial;

  @override
  ConsumerState<NobarScreen> createState() => _NobarScreenState();
}

class _NobarScreenState extends ConsumerState<NobarScreen> with WidgetsBindingObserver {
  static const int _driftMs = 2000;

  late NobarRoom _room = widget.initial;
  late final (String, String) _args = (widget.initial.movieId, widget.initial.episodeId);
  late final NobarRepository _repo;
  String? _uid;

  ChessRealtimeClient? _rt;
  StreamSubscription<ChessRtMessage>? _rtSub;
  NobarVoice? _voice;

  Timer? _heartbeat;
  Timer? _hostTick;
  Timer? _refreshDebounce;
  Timer? _hideControls;
  int _tickCount = 0;
  bool _leaving = false;

  /// XP nonton cuma dihitung saat app di layar depan.
  bool _inForeground = true;

  // ------------------------------------------------------------ chat
  /// 0 = tab Room, 1 = tab Chat.
  int _panel = 0;
  List<NobarChatMessage> _chat = const [];
  int _chatLastId = 0;
  int _chatUnread = 0;
  bool _chatLoading = true;
  bool _chatSending = false;
  bool _chatFetching = false;
  bool _chatAgain = false;

  // ------------------------------------------------------------ video
  WpVideoController? _vc;
  String? _loadedLink;
  bool _videoError = false;
  String? _videoErrorText;
  bool _locked = false;
  int _decoderLevel = WpDecoder.savedLevel;
  int _decoderRetries = 0;
  bool _showControls = true;
  bool _fullscreen = false;
  double _videoVolume = 100;

  /// Posisi awal untuk video yang akan dimuat berikutnya.
  int? _startAtMs;

  // Host: status terakhir yang dikirim (deteksi play/pause/seek).
  bool _lastSentPlaying = false;
  int _lastSentPos = 0;
  DateTime _lastSentAt = DateTime.fromMillisecondsSinceEpoch(0);

  bool _autoNexted = false;

  /// Posisi slider saat host sedang menggeser (seek dikirim saat dilepas).
  double? _dragMs;

  // Anggota: status host yang diikuti.
  _SyncTarget? _target;
  DateTime _lastCorrection = DateTime.fromMillisecondsSinceEpoch(0);

  bool get _isHost => _room.isHost(_uid);
  PlayerController get _notifier => ref.read(playerControllerProvider(_args).notifier);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _repo = ref.read(nobarRepositoryProvider);
    _uid = ref.read(authUserProvider).valueOrNull?.uid;

    // Mini player (kalau ada) ditutup: cuma satu video yang jalan.
    MiniPlayerManager.instance.close();
    WakelockPlus.enable();

    _startAtMs = _room.isHost(_uid) ? _room.positionMs : _room.estimatedPositionMs;
    if (!_room.isHost(_uid)) {
      _target = _SyncTarget(_room.episodeId, _room.estimatedPositionMs, _room.playing);
    }

    final rt = ChessRealtimeClient(_room.topic, onJoined: _onRtJoined);
    _rt = rt;
    _rtSub = rt.messages.listen(_onRt);

    final uid = _uid;
    if (uid != null) {
      final voice = NobarVoice(myUid: uid, rt: rt, fetchIce: () => _repo.ice(_room.id));
      voice.setRoom(_room);
      _voice = voice;
    }
    rt.start();

    _heartbeat = Timer.periodic(const Duration(seconds: 30), (_) => _refresh());
    _hostTick = Timer.periodic(const Duration(seconds: 1), (_) => _onTick());

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      // Episode awal mengikuti room (bisa beda dengan episode saat room dibuat).
      final ui = ref.read(playerControllerProvider(_args));
      if (_room.episodeId.isNotEmpty && ui.currentEpisodeId != _room.episodeId) {
        _notifier.loadEpisodeStream(_room.episodeId);
      }
      _applyPlayback();
      _scheduleHideControls();
      _pullChat();
    });
  }

  // ================================================================ chat

  /// Ambil chat baru dari server (setelah id terakhir). Dipanggil saat ada
  /// sinyal "chat" dari realtime dan tiap heartbeat room (cadangan).
  Future<void> _pullChat() async {
    if (_leaving) return;
    if (_chatFetching) {
      _chatAgain = true;
      return;
    }
    _chatFetching = true;
    try {
      do {
        _chatAgain = false;
        final fresh = await _repo.chatList(_room.id, after: _chatLastId);
        if (!mounted) return;
        final news = fresh.where((m) => m.id > _chatLastId).toList();
        if (news.isNotEmpty) {
          final first = _chatLastId == 0;
          final fromOthers = news.where((m) => m.uid != _uid).length;
          setState(() {
            _chat = [..._chat, ...news].length > 200
                ? [..._chat, ...news].sublist([..._chat, ...news].length - 200)
                : [..._chat, ...news];
            _chatLastId = news.last.id;
            // Riwayat awal tidak dihitung sebagai pesan baru.
            if (!first && _panel != 1) _chatUnread += fromOthers;
          });
        }
      } while (_chatAgain && mounted);
    } catch (_) {
      // Chat cuma pelengkap; heartbeat berikutnya mencoba lagi.
    } finally {
      _chatFetching = false;
      if (mounted && _chatLoading) setState(() => _chatLoading = false);
    }
  }

  Future<bool> _sendChat(String text) async {
    if (_chatSending) return false;
    setState(() => _chatSending = true);
    try {
      await _repo.sendChat(_room.id, text);
      await _pullChat();
      return true;
    } on NobarException catch (e) {
      _snack(e.message);
      return false;
    } catch (_) {
      _snack('Gagal mengirim pesan');
      return false;
    } finally {
      if (mounted) setState(() => _chatSending = false);
    }
  }

  void _setPanel(int i) {
    if (_panel == i) return;
    setState(() {
      _panel = i;
      if (i == 1) _chatUnread = 0;
    });
    if (i == 1) _pullChat();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    WatchXpGate.release(this);
    _heartbeat?.cancel();
    _hostTick?.cancel();
    _refreshDebounce?.cancel();
    _hideControls?.cancel();
    _voice?.dispose();
    _rtSub?.cancel();
    unawaited(_rt?.stop());
    final vc = _vc;
    _vc = null;
    vc?.removeListener(_onVideo);
    vc?.dispose();
    WakelockPlus.disable();
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    if (!_leaving) unawaited(_repo.leave(_room.id).catchError((Object _) {}));
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _inForeground = state == AppLifecycleState.resumed;
    if (state == AppLifecycleState.resumed) {
      _refresh();
      if (!_isHost) _rt?.send('sync_req', {'from': _uid});
    }
  }

  // ================================================================ room

  void _onRtJoined() {
    _voice?.start();
    if (_isHost) {
      _broadcastSync();
    } else {
      _rt?.send('sync_req', {'from': _uid});
    }
    _scheduleRefresh();
  }

  void _scheduleRefresh() {
    _refreshDebounce?.cancel();
    _refreshDebounce = Timer(const Duration(milliseconds: 300), _refresh);
  }

  Future<void> _refresh() async {
    if (_leaving) return;
    try {
      final room = await _repo.get(_room.id);
      if (!mounted) return;
      unawaited(_pullChat());
      final wasHost = _isHost;
      setState(() => _room = room);
      _voice?.setRoom(room);
      if (!wasHost && _isHost) {
        _snack('Kamu sekarang host. Kamu yang mengatur videonya.');
        _broadcastSync();
      } else if (wasHost && !_isHost) {
        _rt?.send('sync_req', {'from': _uid});
      }
    } on NobarException catch (e) {
      if (!mounted) return;
      if (e.roomGone) {
        _leaving = true;
        _snack(e.message);
        // pop() langsung (maybePop akan memunculkan dialog konfirmasi keluar).
        Navigator.of(context).pop();
      }
    }
  }

  void _onRt(ChessRtMessage m) {
    if (!mounted) return;
    final p = m.payload;
    switch (m.event) {
      case 'ping':
        _scheduleRefresh();
      case 'chat':
        _pullChat();
      case 'sync_req':
        if (_isHost) _broadcastSync();
      case 'sync':
        if (_isHost || p['from'] != _room.hostUid) return;
        final ep = p['ep'];
        final pos = p['pos'];
        if (ep is! String || ep.isEmpty || pos is! num) return;
        _onHostState(_SyncTarget(ep, pos.toInt(), p['playing'] == true));
    }
  }

  // ================================================================ sinkron

  void _onTick() {
    if (!mounted) return;
    _tickCount++;
    final vc = _vc;
    // Layar player lama (kalau nobar dibuka dari player) mematikan wakelock
    // saat ditutup; pasang lagi.
    if (_tickCount % 10 == 1) WakelockPlus.enable();
    if (_isHost) {
      // Status rutin tiap 2 detik; simpan ke server tiap 15 detik.
      if (_tickCount % 2 == 0) _broadcastSync();
      if (_tickCount % 15 == 0) _saveState();
      // Episode selesai: host otomatis lanjut ke episode berikutnya.
      if (vc != null && vc.value.isCompleted && !_autoNexted) {
        final next = _notifier.nextEpisodeId;
        if (next != null && next.trim().isNotEmpty) {
          _autoNexted = true;
          _hostPlayEpisode(next);
        }
      }
    } else {
      _applyTarget();
    }
    if (_tickCount % 15 == 0 && vc != null && vc.value.isInitialized) {
      _notifier.saveProgress(vc.value.position.inMilliseconds, vc.value.duration.inMilliseconds);
    }

    // XP nonton (host & anggota), aturan sama dengan player biasa: cuma detik
    // yang benar-benar diputar, tidak buffering, app di depan. Server tetap
    // membatasi (jarak 50 detik per akun, maks akun per HP).
    if (vc != null &&
        vc.value.isInitialized &&
        vc.value.isPlaying &&
        !vc.value.isBuffering &&
        _inForeground &&
        WatchXpGate.onActiveSecond(this)) {
      unawaited(
        ref.read(xpRepositoryProvider).sendHeartbeat(minutes: 1).then((ok) {
          if (ok && mounted) ref.invalidate(myXpProvider);
        }).catchError((Object _) => false),
      );
    }
  }

  ({String ep, int pos, bool playing}) _hostState() {
    final ui = ref.read(playerControllerProvider(_args));
    final vc = _vc;
    final ready = vc != null && vc.value.isInitialized;
    return (
      ep: ui.currentEpisodeId,
      pos: ready ? vc.value.position.inMilliseconds : (_startAtMs ?? 0),
      playing: ready && vc.value.isPlaying,
    );
  }

  void _broadcastSync() {
    if (!_isHost) return;
    // Video host belum siap (baru ganti episode): jangan kirim posisi 0
    // yang bikin anggota lompat ke awal.
    if (!(_vc?.value.isInitialized ?? false)) return;
    final s = _hostState();
    if (s.ep.isEmpty) return;
    _lastSentPlaying = s.playing;
    _lastSentPos = s.pos;
    _lastSentAt = DateTime.now();
    _rt?.send('sync', {'from': _uid, 'ep': s.ep, 'pos': s.pos, 'playing': s.playing});
  }

  Future<void> _saveState() async {
    if (!_isHost || !(_vc?.value.isInitialized ?? false)) return;
    final s = _hostState();
    if (s.ep.isEmpty) return;
    try {
      await _repo.saveState(_room.id, episodeId: s.ep, positionMs: s.pos, playing: s.playing);
    } catch (_) {}
  }

  /// Host: kirim langsung kalau ada perubahan (play/pause/seek), tanpa
  /// menunggu jadwal 2 detik.
  void _hostDetectChange() {
    if (!_isHost) return;
    final s = _hostState();
    final expected = _lastSentPlaying
        ? _lastSentPos + DateTime.now().difference(_lastSentAt).inMilliseconds
        : _lastSentPos;
    if (s.playing != _lastSentPlaying || (s.pos - expected).abs() > 1500) _broadcastSync();
  }

  void _onHostState(_SyncTarget t) {
    _target = t;
    final ui = ref.read(playerControllerProvider(_args));
    if (t.episodeId != ui.currentEpisodeId) {
      _startAtMs = t.nowMs;
      _notifier.loadEpisodeStream(t.episodeId);
      return;
    }
    _applyTarget();
  }

  /// Anggota: samakan video dengan status host.
  void _applyTarget() {
    final t = _target;
    final vc = _vc;
    if (_isHost || t == null || vc == null || !vc.value.isInitialized || vc.isSeekPending) return;
    final ui = ref.read(playerControllerProvider(_args));
    if (t.episodeId != ui.currentEpisodeId) return;

    final now = DateTime.now();
    final want = t.nowMs;
    final have = vc.value.position.inMilliseconds;
    if ((want - have).abs() > _driftMs && now.difference(_lastCorrection) > const Duration(seconds: 3)) {
      _lastCorrection = now;
      final dur = vc.value.duration.inMilliseconds;
      final clamped = dur > 1000 ? want.clamp(0, dur - 500) : (want < 0 ? 0 : want);
      vc.seekTo(Duration(milliseconds: clamped));
    }
    if (t.playing && !vc.value.isPlaying && !vc.value.isCompleted) {
      vc.play();
    } else if (!t.playing && vc.value.isPlaying) {
      vc.pause();
    }
  }

  // ================================================================ video

  /// null = belum bisa diputuskan (status Premium / daftar episode belum siap).
  bool? _episodeLocked(PlayerUiState ui) {
    final premium = ref.read(myPremiumProvider);
    if (premium.valueOrNull == true) return false;
    if (!(premium.hasValue || premium.hasError) || !ui.episodesLoaded) return null;
    String? idx;
    for (final e in ui.episodes) {
      if (e.id == ui.currentEpisodeId) idx = e.index;
    }
    idx ??= ui.streamData?.episode?.index;
    final total = latestEpisodeIndex(ui.episodes.map((e) => e.index));
    return isEpisodeLocked(idx, total, false);
  }

  void _applyPlayback() {
    if (!mounted) return;
    final ui = ref.read(playerControllerProvider(_args));
    final locked = _episodeLocked(ui);
    if (locked == null) return;
    if (locked != _locked) setState(() => _locked = locked);
    if (locked) {
      _stopVideo();
      return;
    }
    final isPremium = ref.read(myPremiumProvider).valueOrNull ?? false;
    final sel = ui.selectedServer;
    if (!isPremium && sel != null && isQualityLocked(sel.quality, false)) {
      final fallback = _bestUnlockedServer(ui.streamData?.server ?? const []);
      if (fallback != null && fallback.link != sel.link) {
        _notifier.selectServer(fallback);
        return;
      }
    }
    _loadLink(sel?.link);
  }

  StreamServer? _bestUnlockedServer(List<StreamServer> servers) {
    StreamServer? best;
    var bestValue = -1;
    for (final s in servers) {
      final link = s.link;
      if (link == null || link.trim().isEmpty || isQualityLocked(s.quality, false)) continue;
      final v = qualityValueP(s.quality) ?? 0;
      if (v > bestValue) {
        best = s;
        bestValue = v;
      }
    }
    return best;
  }

  void _stopVideo() {
    final vc = _vc;
    _loadedLink = null;
    if (vc == null) return;
    _vc = null;
    vc.removeListener(_onVideo);
    vc.dispose();
    if (mounted) setState(() {});
  }

  Future<void> _loadLink(String? link) async {
    if (link == null || link.trim().isEmpty || link == _loadedLink) return;
    _loadedLink = link;
    _autoNexted = false;
    final old = _vc;
    old?.removeListener(_onVideo);

    final startMs = _isHost ? (_startAtMs ?? 0) : (_target?.nowMs ?? _startAtMs ?? 0);
    _startAtMs = null;
    final startAt = startMs > 1000 ? Duration(milliseconds: startMs) : null;

    final WpVideoController vc;
    try {
      vc = link.startsWith('file://')
          ? WpVideoController.file(File.fromUri(Uri.parse(link)), startAt: startAt, decoderLevel: _decoderLevel)
          : WpVideoController.networkUrl(Uri.parse(link), startAt: startAt, decoderLevel: _decoderLevel);
    } catch (e) {
      setState(() {
        _videoError = true;
        _videoErrorText = 'Link tidak valid';
      });
      return;
    }
    setState(() {
      _vc = vc;
      _videoError = false;
      _videoErrorText = null;
    });
    await old?.dispose();

    try {
      await vc.initialize();
      if (!mounted || _vc != vc) return;
      vc.addListener(_onVideo);
      await vc.setVolume(_videoVolume);
      if (_isHost) {
        await vc.play();
        _broadcastSync();
        unawaited(_saveState());
      } else {
        _lastCorrection = DateTime.fromMillisecondsSinceEpoch(0);
        _applyTarget();
      }
      if (mounted) setState(() {});
    } catch (e) {
      if (!mounted || _vc != vc) return;
      final desc = vc.value.errorDescription ?? '$e';
      final isDecoder = desc.contains('MediaCodec') || desc.toLowerCase().contains('decoder') || desc.contains('hwdec');
      if (isDecoder && _decoderRetries < 2 && _decoderLevel < WpDecoder.maxLevel) {
        _decoderRetries++;
        _decoderLevel++;
        _loadedLink = null;
        await Future<void>.delayed(const Duration(milliseconds: 600));
        if (mounted) _loadLink(link);
        return;
      }
      setState(() {
        _videoError = true;
        _videoErrorText = desc.length > 160 ? desc.substring(0, 160) : desc;
      });
    }
  }

  void _onVideo() {
    if (!mounted) return;
    _hostDetectChange();
  }

  void _retryVideo() {
    final link = ref.read(playerControllerProvider(_args)).selectedServer?.link;
    _loadedLink = null;
    _decoderRetries = 0;
    setState(() => _videoError = false);
    _loadLink(link);
  }

  // ================================================================ aksi host

  void _hostTogglePlay() {
    final vc = _vc;
    if (!_isHost || vc == null || !vc.value.isInitialized) return;
    if (vc.value.isPlaying) {
      vc.pause();
    } else {
      vc.play();
    }
    _scheduleHideControls();
    Future<void>.delayed(const Duration(milliseconds: 250), _broadcastSync);
  }

  Future<void> _hostSeek(int ms) async {
    final vc = _vc;
    if (!_isHost || vc == null || !vc.value.isInitialized) return;
    final dur = vc.value.duration.inMilliseconds;
    final target = dur > 1000 ? ms.clamp(0, dur - 500) : (ms < 0 ? 0 : ms);
    await vc.seekTo(Duration(milliseconds: target));
    _lastSentPos = target;
    _lastSentAt = DateTime.now();
    _rt?.send('sync', {'from': _uid, 'ep': _hostState().ep, 'pos': target, 'playing': vc.value.isPlaying});
    _scheduleHideControls();
  }

  void _hostPlayEpisode(String id) {
    if (!_isHost) return;
    _startAtMs = 0;
    _notifier.loadEpisodeStream(id);
    _rt?.send('sync', {'from': _uid, 'ep': id, 'pos': 0, 'playing': true});
    unawaited(_repo.saveState(_room.id, episodeId: id, positionMs: 0, playing: true).catchError((Object _) {}));
  }

  Future<void> _kick(NobarMember m) async {
    try {
      final room = await _repo.kick(_room.id, m.uid);
      if (!mounted) return;
      setState(() => _room = room);
      _voice?.setRoom(room);
      _snack('${m.username} dikeluarkan dari room');
    } on NobarException catch (e) {
      _snack(e.message);
    }
  }

  // ================================================================ UI bantu

  void _snack(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text)));
  }

  void _scheduleHideControls() {
    _hideControls?.cancel();
    _hideControls = Timer(const Duration(seconds: 4), () {
      if (mounted && (_vc?.value.isPlaying ?? false)) setState(() => _showControls = false);
    });
  }

  void _toggleControls() {
    setState(() => _showControls = !_showControls);
    if (_showControls) _scheduleHideControls();
  }

  Future<void> _setFullscreen(bool on) async {
    setState(() => _fullscreen = on);
    if (on) {
      await SystemChrome.setPreferredOrientations([DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight]);
      await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    } else {
      await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
      await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    }
  }

  Future<void> _confirmLeave() async {
    if (_fullscreen) {
      await _setFullscreen(false);
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surfaceDark,
        title: const Text('Keluar dari Nobar?', style: TextStyle(color: AppColors.textWhite)),
        content: Text(
          _isHost && _room.members.length > 1
              ? 'Kamu host. Kalau keluar, host otomatis pindah ke anggota lain.'
              : 'Voice chat dan video nobar akan ditutup.',
          style: const TextStyle(color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Batal')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.accentViolet),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Keluar'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    _leaving = true;
    unawaited(_repo.leave(_room.id).catchError((Object _) {}));
    Navigator.of(context).pop();
  }

  void _openInvite() {
    showNobarInviteSheet(context, _room, onShareCode: _share);
  }

  void _share() {
    final title = _room.movieTitle ?? 'anime';
    Share.share(
      'Yuk nobar "$title" bareng aku di Zenime, sambil ngobrol pakai voice!\n'
      'Buka Menu > Nobar, lalu masukkan kode room: ${_room.code}',
      subject: 'Nobar di Zenime',
    );
  }

  void _copyCode() {
    Clipboard.setData(ClipboardData(text: _room.code));
    _snack('Kode ${_room.code} disalin');
  }

  String _episodeLabel(PlayerUiState ui) {
    for (final e in ui.episodes) {
      if (e.id == ui.currentEpisodeId) return 'Episode ${e.index ?? '?'}';
    }
    final idx = ui.streamData?.episode?.index;
    return idx == null ? 'Memuat episode…' : 'Episode $idx';
  }

  // ================================================================ build

  @override
  Widget build(BuildContext context) {
    ref.listen<PlayerUiState>(playerControllerProvider(_args), (prev, next) {
      if (prev?.selectedServer?.link != next.selectedServer?.link ||
          prev?.episodesLoaded != next.episodesLoaded ||
          prev?.currentEpisodeId != next.currentEpisodeId) {
        final epChanged = prev?.currentEpisodeId != next.currentEpisodeId;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          if (epChanged) _stopVideo();
          _applyPlayback();
        });
      }
    });
    ref.listen(myPremiumProvider, (_, _) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _applyPlayback());
    });
    final ui = ref.watch(playerControllerProvider(_args));

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _confirmLeave();
      },
      child: Scaffold(
        backgroundColor: _fullscreen ? Colors.black : AppColors.backgroundDark,
        body: _fullscreen ? _fullscreenLayout(ui) : _portraitLayout(ui),
      ),
    );
  }

  Widget _portraitLayout(PlayerUiState ui) {
    final voice = _voice;
    final bottomInset = MediaQuery.paddingOf(context).bottom;
    return Stack(
      children: [
        SafeArea(
          bottom: false,
          child: Column(
            children: [
              AspectRatio(aspectRatio: 16 / 9, child: _videoBox(ui)),
              _panelTabs(),
              Expanded(
                child: _panel == 1
                    ? NobarChatPanel(
                        messages: _chat,
                        myUid: _uid ?? '',
                        hostUid: _room.hostUid,
                        sending: _chatSending,
                        loading: _chatLoading,
                        onSend: _sendChat,
                        // Kolom ketik di atas dock suara yang mengambang.
                        bottomPadding: voice != null ? 92 + bottomInset : 8 + bottomInset,
                      )
                    : ListView(
                        padding: EdgeInsets.fromLTRB(16, 16, 16, 130 + bottomInset),
                        children: [
                          _roomHeader(ui),
                          const SizedBox(height: 22),
                          if (voice != null)
                            NobarMembersStrip(
                              room: _room,
                              voice: voice,
                              myUid: _uid ?? '',
                              onKick: _kick,
                              onInvite: _openInvite,
                            ),
                          const SizedBox(height: 26),
                          _episodeSection(ui),
                        ],
                      ),
              ),
            ],
          ),
        ),
        if (voice != null)
          Positioned(
            left: 16,
            right: 16,
            bottom: 12 + bottomInset,
            child: NobarControlDock(
              voice: voice,
              isHost: _isHost,
              onVolume: _openVolume,
              onMuteAll: () {
                voice.forceMute(null);
                _snack('Mic semua anggota dimatikan');
              },
            ),
          ),
      ],
    );
  }

  Widget _fullscreenLayout(PlayerUiState ui) {
    final voice = _voice;
    return Stack(
      fit: StackFit.expand,
      children: [
        _videoBox(ui),
        if (voice != null)
          Positioned(
            right: 16,
            bottom: 70,
            child: NobarMiniVoice(room: _room, voice: voice, myUid: _uid ?? ''),
          ),
      ],
    );
  }

  /// Tab Room / Chat di bawah video (Chat dapat badge pesan baru).
  Widget _panelTabs() {
    Widget tab(int i, IconData icon, String label, {int badge = 0}) {
      final sel = _panel == i;
      return Expanded(
        child: InkWell(
          onTap: () => _setPanel(i),
          child: Container(
            height: 44,
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(color: sel ? AppColors.accentViolet : Colors.transparent, width: 2.5),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: 17, color: sel ? AppColors.textWhite : AppColors.textMuted),
                const SizedBox(width: 6),
                Text(
                  label,
                  style: TextStyle(
                    color: sel ? AppColors.textWhite : AppColors.textMuted,
                    fontWeight: sel ? FontWeight.w800 : FontWeight.w600,
                    fontSize: 13.5,
                  ),
                ),
                if (badge > 0) ...[
                  const SizedBox(width: 6),
                  Container(
                    constraints: const BoxConstraints(minWidth: 18),
                    height: 18,
                    padding: const EdgeInsets.symmetric(horizontal: 5),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: AppColors.accentViolet,
                      borderRadius: BorderRadius.circular(9),
                    ),
                    child: Text(
                      badge > 99 ? '99+' : '$badge',
                      style: const TextStyle(color: Colors.white, fontSize: 10.5, fontWeight: FontWeight.w800),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: AppColors.backgroundDark,
        border: Border(bottom: BorderSide(color: Colors.white.withValues(alpha: 0.06))),
      ),
      child: Row(
        children: [
          tab(0, Icons.groups_rounded, 'Room'),
          tab(1, Icons.chat_bubble_rounded, 'Chat', badge: _chatUnread),
        ],
      ),
    );
  }

  /// Poster + judul + episode + kode, dengan tombol Undang dan menu lainnya.
  Widget _roomHeader(PlayerUiState ui) {
    final title = ui.anime?.title ?? _room.movieTitle ?? 'Nobar';
    final poster = ui.anime?.posterUrl ?? _room.posterUrl ?? '';
    return Row(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: SizedBox(
            width: 46,
            height: 64,
            child: poster.isEmpty
                ? const ColoredBox(
                    color: AppColors.surfaceElevated,
                    child: Icon(Icons.movie_rounded, color: AppColors.textMuted),
                  )
                : NetImage(poster, fit: BoxFit.cover),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: AppColors.textWhite,
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  height: 1.25,
                ),
              ),
              const SizedBox(height: 5),
              Row(
                children: [
                  Flexible(
                    child: Text(
                      _episodeLabel(ui),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: AppColors.textSecondary, fontSize: 12.5),
                    ),
                  ),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 6),
                    child: Text('·', style: TextStyle(color: AppColors.textMuted)),
                  ),
                  InkWell(
                    onTap: _copyCode,
                    borderRadius: BorderRadius.circular(6),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 1),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            _room.code,
                            style: const TextStyle(
                              color: AppColors.accentVioletLight,
                              fontSize: 12.5,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 1.2,
                            ),
                          ),
                          const SizedBox(width: 3),
                          const Icon(Icons.copy_rounded, size: 12, color: AppColors.accentVioletLight),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        FilledButton.icon(
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.accentViolet,
            foregroundColor: Colors.white,
            visualDensity: VisualDensity.compact,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            shape: const StadiumBorder(),
          ),
          onPressed: _openInvite,
          icon: const Icon(Icons.person_add_alt_1_rounded, size: 18),
          label: const Text('Undang', style: TextStyle(fontWeight: FontWeight.w700)),
        ),
        PopupMenuButton<String>(
          tooltip: 'Lainnya',
          color: AppColors.surfaceElevated,
          icon: const Icon(Icons.more_vert_rounded, color: AppColors.textSecondary),
          onSelected: (v) {
            switch (v) {
              case 'share':
                _share();
              case 'copy':
                _copyCode();
              case 'leave':
                _confirmLeave();
            }
          },
          itemBuilder: (_) => const [
            PopupMenuItem(value: 'share', child: Text('Bagikan kode room')),
            PopupMenuItem(value: 'copy', child: Text('Salin kode')),
            PopupMenuItem(
              value: 'leave',
              child: Text('Keluar dari nobar', style: TextStyle(color: AppColors.errorRed)),
            ),
          ],
        ),
      ],
    );
  }

  /// Lembar volume video (suara teman tidak ikut berubah).
  void _openVolume() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.surfaceDark,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Suara video',
                  style: TextStyle(color: AppColors.textWhite, fontSize: 16, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 2),
                const Text(
                  'Kecilkan supaya obrolan teman lebih jelas. Suara teman tidak ikut berubah.',
                  style: TextStyle(color: AppColors.textMuted, fontSize: 12.5),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Icon(
                      _videoVolume == 0 ? Icons.volume_off_rounded : Icons.volume_down_rounded,
                      color: AppColors.textSecondary,
                    ),
                    Expanded(
                      child: Slider(
                        value: _videoVolume,
                        min: 0,
                        max: 100,
                        activeColor: AppColors.accentViolet,
                        onChanged: (v) {
                          setState(() => _videoVolume = v);
                          setSheet(() {});
                          _vc?.setVolume(v);
                        },
                      ),
                    ),
                    SizedBox(
                      width: 40,
                      child: Text(
                        '${_videoVolume.round()}%',
                        textAlign: TextAlign.end,
                        style: const TextStyle(color: AppColors.textSecondary, fontSize: 12.5),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _episodeSection(PlayerUiState ui) {
    final eps = ui.episodes.where((e) => (e.id ?? '').isNotEmpty).toList();
    if (eps.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Text(
              'Episode',
              style: TextStyle(color: AppColors.textWhite, fontSize: 15, fontWeight: FontWeight.w700),
            ),
            const SizedBox(width: 8),
            Text('${eps.length}', style: const TextStyle(color: AppColors.textMuted, fontSize: 12.5)),
            const Spacer(),
            if (!_isHost)
              const Row(
                children: [
                  Icon(Icons.lock_outline_rounded, size: 13, color: AppColors.textMuted),
                  SizedBox(width: 4),
                  Text('Dipilih host', style: TextStyle(color: AppColors.textMuted, fontSize: 12)),
                ],
              ),
          ],
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 42,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: eps.length,
            separatorBuilder: (_, _) => const SizedBox(width: 8),
            itemBuilder: (_, i) => _episodeChip(eps[i], ui),
          ),
        ),
      ],
    );
  }

  Widget _episodeChip(EpisodeItem e, PlayerUiState ui) {
    final current = e.id == ui.currentEpisodeId;
    return Material(
      color: current ? AppColors.accentViolet : Colors.white.withValues(alpha: 0.06),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: !_isHost || current ? null : () => _hostPlayEpisode(e.id!),
        child: Container(
          constraints: const BoxConstraints(minWidth: 52),
          padding: const EdgeInsets.symmetric(horizontal: 14),
          alignment: Alignment.center,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (current) ...[
                const Icon(Icons.graphic_eq_rounded, size: 15, color: Colors.white),
                const SizedBox(width: 5),
              ],
              Text(
                e.index ?? '?',
                style: TextStyle(
                  color: current || _isHost ? AppColors.textWhite : AppColors.textMuted,
                  fontWeight: FontWeight.w700,
                  fontSize: 13.5,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ------------------------------------------------------------ video box

  Widget _videoBox(PlayerUiState ui) {
    final vc = _vc;
    Widget content;
    if (_locked) {
      content = _overlayMessage(
        Icons.workspace_premium_rounded,
        'Episode ini khusus Premium',
        'Kamu tetap bisa ngobrol di voice chat.',
      );
    } else if (ui.streamError != null) {
      content = _overlayMessage(Icons.error_outline_rounded, ui.streamError!, null, retry: true);
    } else if (_videoError) {
      content = _overlayMessage(Icons.error_outline_rounded, 'Video gagal diputar', _videoErrorText, retry: true);
    } else if (vc == null) {
      content = const Center(child: CircularProgressIndicator(color: AppColors.accentViolet));
    } else {
      content = Stack(
        fit: StackFit.expand,
        children: [
          WpVideoView(vc),
          ListenableBuilder(
            listenable: vc,
            builder: (context, _) {
              final v = vc.value;
              if (v.isInitialized && !v.isBuffering) return const SizedBox.shrink();
              return const Center(child: CircularProgressIndicator(color: AppColors.accentViolet));
            },
          ),
        ],
      );
    }

    return ColoredBox(
      color: Colors.black,
      child: Stack(
        fit: StackFit.expand,
        children: [
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _toggleControls,
            onDoubleTap: _isHost ? _hostTogglePlay : null,
            child: content,
          ),
          if (vc != null) _controls(vc),
        ],
      ),
    );
  }

  Widget _overlayMessage(IconData icon, String title, String? sub, {bool retry = false}) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: AppColors.warningAmber, size: 34),
            const SizedBox(height: 8),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.textWhite, fontWeight: FontWeight.w700),
            ),
            if (sub != null) ...[
              const SizedBox(height: 4),
              Text(
                sub,
                textAlign: TextAlign.center,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: AppColors.textMuted, fontSize: 12),
              ),
            ],
            if (retry) ...[
              const SizedBox(height: 10),
              OutlinedButton(
                onPressed: () {
                  final ui = ref.read(playerControllerProvider(_args));
                  if (ui.streamError != null) {
                    _notifier.loadEpisodeStream(ui.currentEpisodeId);
                  } else {
                    _retryVideo();
                  }
                },
                child: const Text('Coba lagi'),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _controls(WpVideoController vc) {
    return IgnorePointer(
      ignoring: !_showControls,
      child: AnimatedOpacity(
        opacity: _showControls ? 1 : 0,
        duration: const Duration(milliseconds: 200),
        child: ListenableBuilder(
          listenable: vc,
          builder: (context, _) {
            final v = vc.value;
            final pos = v.position.inMilliseconds;
            final dur = v.duration.inMilliseconds;
            return DecoratedBox(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color(0x99000000), Color(0x00000000), Color(0x00000000), Color(0xB3000000)],
                  stops: [0, 0.3, 0.6, 1],
                ),
              ),
              child: Stack(
                children: [
                  Positioned(
                    top: 8,
                    left: 8,
                    child: _liveBadge(),
                  ),
                  if (_fullscreen)
                    Positioned(
                      top: 4,
                      right: 4,
                      child: IconButton(
                        onPressed: _confirmLeave,
                        icon: const Icon(Icons.close_rounded, color: Colors.white),
                      ),
                    ),
                  if (_isHost)
                    Center(
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _circleBtn(Icons.replay_10_rounded, () => _hostSeek(pos - 10000)),
                          const SizedBox(width: 24),
                          _circleBtn(
                            v.isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                            _hostTogglePlay,
                            big: true,
                          ),
                          const SizedBox(width: 24),
                          _circleBtn(Icons.forward_10_rounded, () => _hostSeek(pos + 10000)),
                        ],
                      ),
                    ),
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(12, 0, 4, 2),
                      child: Row(
                        children: [
                          Text(
                            '${_fmt(_dragMs?.round() ?? pos)} / ${_fmt(dur)}',
                            style: const TextStyle(color: Colors.white, fontSize: 11.5),
                          ),
                          Expanded(
                            child: _isHost
                                ? SliderTheme(
                                    data: SliderTheme.of(context).copyWith(
                                      trackHeight: 3,
                                      thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                                      overlayShape: SliderComponentShape.noOverlay,
                                    ),
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(horizontal: 12),
                                      child: Slider(
                                        value: dur > 0 ? (_dragMs ?? pos.toDouble()).clamp(0, dur).toDouble() : 0,
                                        max: dur > 0 ? dur.toDouble() : 1,
                                        activeColor: AppColors.accentViolet,
                                        inactiveColor: Colors.white24,
                                        onChanged: dur > 0
                                            ? (x) {
                                                _hideControls?.cancel();
                                                setState(() => _dragMs = x);
                                              }
                                            : null,
                                        onChangeEnd: dur > 0
                                            ? (x) {
                                                setState(() => _dragMs = null);
                                                _hostSeek(x.round());
                                              }
                                            : null,
                                      ),
                                    ),
                                  )
                                : Padding(
                                    padding: const EdgeInsets.symmetric(horizontal: 12),
                                    child: Row(
                                      children: [
                                        Expanded(
                                          child: ClipRRect(
                                            borderRadius: BorderRadius.circular(2),
                                            child: LinearProgressIndicator(
                                              value: dur > 0 ? (pos / dur).clamp(0.0, 1.0) : 0,
                                              minHeight: 3,
                                              color: AppColors.accentViolet,
                                              backgroundColor: Colors.white24,
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        InkWell(
                                          onTap: () {
                                            _lastCorrection = DateTime.fromMillisecondsSinceEpoch(0);
                                            _rt?.send('sync_req', {'from': _uid});
                                            _snack('Menyamakan dengan host…');
                                          },
                                          child: const Padding(
                                            padding: EdgeInsets.all(6),
                                            child: Icon(Icons.sync_rounded, color: Colors.white, size: 18),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                          ),
                          IconButton(
                            visualDensity: VisualDensity.compact,
                            onPressed: () => _setFullscreen(!_fullscreen),
                            icon: Icon(
                              _fullscreen ? Icons.fullscreen_exit_rounded : Icons.fullscreen_rounded,
                              color: Colors.white,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _liveBadge() {
    final host = _room.member(_room.hostUid);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 7,
            height: 7,
            decoration: const BoxDecoration(color: AppColors.accentViolet, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          Text(
            _isHost
                ? 'NOBAR · kamu host'
                : 'NOBAR · dikontrol ${host?.username ?? 'host'}',
            style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700),
          ),
          const SizedBox(width: 6),
          Icon(Icons.people_alt_rounded, size: 13, color: Colors.white.withValues(alpha: 0.8)),
          const SizedBox(width: 3),
          Text(
            '${_room.members.length}/${_room.maxMembers}',
            style: TextStyle(color: Colors.white.withValues(alpha: 0.8), fontSize: 11),
          ),
        ],
      ),
    );
  }

  Widget _circleBtn(IconData icon, VoidCallback onTap, {bool big = false}) {
    return Material(
      color: Colors.black.withValues(alpha: 0.4),
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: Padding(
          padding: EdgeInsets.all(big ? 12 : 8),
          child: Icon(icon, color: Colors.white, size: big ? 36 : 26),
        ),
      ),
    );
  }

  static String _fmt(int ms) {
    final s = (ms < 0 ? 0 : ms) ~/ 1000;
    final h = s ~/ 3600;
    final m = (s % 3600) ~/ 60;
    final sec = s % 60;
    String two(int n) => n.toString().padLeft(2, '0');
    return h > 0 ? '$h:${two(m)}:${two(sec)}' : '${two(m)}:${two(sec)}';
  }
}

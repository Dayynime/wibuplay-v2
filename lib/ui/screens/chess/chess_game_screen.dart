import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/theme/app_colors.dart';
import '../../../data/models/chess_models.dart';
import '../../../data/realtime/chess_realtime_client.dart';
import '../../../data/repository/chess_repository.dart';
import '../../../data/voice/chess_voice_call.dart';
import '../../../providers.dart';
import '../../app_routes.dart';
import '../../components/friend_avatar.dart';
import '../../glass/glass.dart';
import 'chess_board.dart';
import 'chess_voice_bar.dart';

/// Satu permainan catur: menunggu lawan, bermain, dan hasil akhir.
///
/// Sumber kebenaran ada di server. Layar ini memuat ulang posisi setiap ada
/// ping Realtime Broadcast (`chess-game-<id>`), saat app kembali aktif, dan
/// berkala sebagai cadangan kalau koneksi realtime putus.
class ChessGameScreen extends ConsumerStatefulWidget {
  const ChessGameScreen({super.key, required this.gameId, this.initial});

  final String gameId;

  /// Data awal (mis. dari hasil buat/terima tantangan) supaya tidak kosong.
  final ChessGame? initial;

  @override
  ConsumerState<ChessGameScreen> createState() => _ChessGameScreenState();
}

class _ChessGameScreenState extends ConsumerState<ChessGameScreen> with WidgetsBindingObserver {
  late final ChessRepository _repo;
  ChessRealtimeClient? _rt;
  StreamSubscription<Map<String, dynamic>>? _rtSub;

  /// Panggilan suara dengan lawan; dibuat begitu kedua pemain sudah ada.
  ChessVoiceCall? _voice;

  ChessGame? _game;
  String? _error;
  bool _busy = false;

  // Tampilan lokal (langkah yang baru dikirim muncul sebelum server menjawab).
  Map<String, String> _pieces = const {};
  String? _pendingUci;
  String? _selected;

  Timer? _ticker;
  Timer? _poll;
  Timer? _debounce;
  final ValueNotifier<int> _tick = ValueNotifier<int>(0);
  int _loadSeq = 0;
  int _expiredRefreshPly = -1;

  final ScrollController _movesScroll = ScrollController();

  String? get _uid => ref.read(authUserProvider).valueOrNull?.uid;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _repo = ref.read(chessRepositoryProvider);
    final init = widget.initial;
    if (init != null) {
      // Langsung isi tanpa setState (belum boleh di initState).
      _game = init;
      _pieces = chessPiecesFromFen(init.fen);
    }
    _load();

    _rt = ChessRealtimeClient('chess-game-${widget.gameId}', onJoined: _scheduleLoad);
    _rtSub = _rt!.pings.listen((_) => _scheduleLoad());
    _rt!.start();
    _ensureVoice();

    _ticker = Timer.periodic(const Duration(milliseconds: 250), (_) => _onTick());
    _poll = Timer.periodic(const Duration(seconds: 4), (_) => _onPoll());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _ticker?.cancel();
    _poll?.cancel();
    _debounce?.cancel();
    _rtSub?.cancel();
    _voice?.dispose(); // menutup panggilan + memberi tahu lawan
    unawaited(_rt?.stop());
    _tick.dispose();
    _movesScroll.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _load(silent: true);
  }

  // ================================================================ data

  void _scheduleLoad() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 200), () => _load(silent: true));
  }

  int _lastPollAt = 0;

  void _onPoll() {
    final g = _game;
    if (g == null || !(g.isActive || g.isWaiting || (g.isOver && g.rematch != null))) return;
    final joined = _rt?.isJoined ?? false;
    // Realtime aktif: cadangan tiap 20 detik saja. Putus: tiap 4 detik.
    final now = DateTime.now().millisecondsSinceEpoch;
    if (joined && now - _lastPollAt < 20000) return;
    _lastPollAt = now;
    _load(silent: true);
  }

  void _onTick() {
    final g = _game;
    if (g == null) return;
    _tick.value++;
    if (!g.isActive) return;
    // Jam lawan / batas langkah pertama habis: minta server menghitung hasilnya.
    final running = g.clockRunning;
    final runningOut = running != null && g.remainingMs(running) <= 0;
    final firstOut = (g.firstMoveLeftMs() ?? 1) <= 0;
    if ((runningOut || firstOut) && _expiredRefreshPly != g.ply) {
      _expiredRefreshPly = g.ply;
      Future<void>.delayed(const Duration(milliseconds: 600), () {
        if (mounted) _load(silent: true);
      });
    }
  }

  Future<void> _load({bool silent = false}) async {
    final seq = ++_loadSeq;
    try {
      final g = await _repo.get(widget.gameId);
      if (!mounted || seq != _loadSeq) return;
      if (_pendingUci != null) return; // jawaban langkah yang sedang dikirim yang dipakai
      _apply(g);
    } on ChessException catch (e) {
      if (!mounted || seq != _loadSeq) return;
      if (_game == null) {
        setState(() => _error = e.message);
      } else if (!silent) {
        _snack(e.message);
      }
    }
  }

  void _apply(ChessGame g) {
    final prev = _game;
    // Abaikan respons lama yang datang terlambat (status tidak pernah mundur:
    // menunggu -> berjalan -> selesai, dan jumlah langkah tidak berkurang).
    if (prev != null && prev.id == g.id) {
      int rank(ChessGame x) => x.isWaiting ? 0 : (x.isActive ? 1 : 2);
      if (rank(g) < rank(prev)) return;
      if (g.isActive && prev.isActive && g.ply < prev.ply) return;
    }

    final newMove = prev != null && g.ply > prev.ply && g.lastMove != null;
    final byOpponent = newMove && g.myColor != null && g.turn == g.myColor;
    if (byOpponent) {
      HapticFeedback.lightImpact();
    }
    if (prev != null && !prev.isOver && g.isOver) {
      HapticFeedback.mediumImpact();
    }

    setState(() {
      _game = g;
      _ensureVoice();
      _error = null;
      _pieces = chessPiecesFromFen(g.fen);
      if (!g.isMyTurn || (_selected != null && !_targetsFor(g, _selected!).isNotEmpty)) {
        _selected = null;
      }
    });
    if (newMove) _scrollMovesToEnd();
  }

  /// Siapkan panggilan suara kalau aku pemain dan lawan sudah ada.
  void _ensureVoice() {
    if (_voice != null) return;
    final g = _game;
    final rt = _rt;
    final uid = _uid;
    if (g == null || rt == null || uid == null || g.myColor == null) return;
    final opp = g.myColor == 'w' ? g.black : g.white;
    if (opp == null || opp.uid == uid) return;
    _voice = ChessVoiceCall(
      myUid: uid,
      opponentUid: opp.uid,
      rt: rt,
      fetchIce: () => _repo.voiceIce(widget.gameId),
    );
  }

  void _scrollMovesToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_movesScroll.hasClients) return;
      _movesScroll.animateTo(
        _movesScroll.position.maxScrollExtent,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    });
  }

  // ================================================================ papan

  Set<String> _targetsFor(ChessGame g, String from) =>
      g.legal.where((m) => m.startsWith(from)).map((m) => m.substring(2, 4)).toSet();

  bool _canPick(String square) {
    final g = _game;
    if (g == null || !g.isMyTurn || _pendingUci != null || _busy) return false;
    final p = _pieces[square];
    if (p == null) return false;
    final mine = g.myColor == 'w' ? p == p.toUpperCase() : p == p.toLowerCase();
    return mine && _targetsFor(g, square).isNotEmpty;
  }

  Future<void> _onMove(String from, String to) async {
    final g = _game;
    if (g == null) return;
    final options = g.legal.where((m) => m.startsWith('$from$to')).toList();
    if (options.isEmpty) return;
    var uci = options.first;
    if (options.length > 1) {
      final promo = await _pickPromotion(g.myColor ?? 'w');
      if (promo == null || !mounted) return;
      uci = '$from$to$promo';
      if (!options.contains(uci)) return;
    }
    await _send(uci);
  }

  Future<void> _send(String uci) async {
    final g = _game;
    if (g == null) return;
    HapticFeedback.lightImpact();
    setState(() {
      _pendingUci = uci;
      _selected = null;
      _pieces = chessApplyLocal(_pieces, uci);
    });
    _loadSeq++; // muatan lama yang masih jalan tidak boleh menimpa
    try {
      final res = await _repo.move(g.id, uci, g.ply);
      if (!mounted) return;
      _pendingUci = null;
      _apply(res.game);
      if (res.rejected != null) _snack(res.rejected!);
    } on ChessException catch (e) {
      if (!mounted) return;
      setState(() {
        _pendingUci = null;
        _pieces = chessPiecesFromFen(g.fen);
      });
      _snack(e.message);
      _load(silent: true);
    }
  }

  Future<String?> _pickPromotion(String color) {
    final pieces = color == 'w' ? ['Q', 'R', 'B', 'N'] : ['q', 'r', 'b', 'n'];
    const names = ['Ratu', 'Benteng', 'Gajah', 'Kuda'];
    return showGlassSheet<String>(
      context: context,
      backgroundColor: AppColors.surfaceDark,
      builder: (ctx) => SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Promosi pion jadi…',
                  style: TextStyle(color: AppColors.textWhite, fontSize: 16, fontWeight: FontWeight.w800)),
              const SizedBox(height: 14),
              Row(
                children: [
                  for (var i = 0; i < 4; i++)
                    Expanded(
                      child: Padding(
                        padding: EdgeInsets.only(right: i < 3 ? 10 : 0),
                        child: Material(
                          color: ChessPalette.light,
                          borderRadius: BorderRadius.circular(14),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(14),
                            onTap: () => Navigator.of(ctx).pop(pieces[i].toLowerCase()),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(vertical: 8),
                              child: Column(
                                children: [
                                  ChessPieceGlyph(piece: pieces[i], size: 52),
                                  const SizedBox(height: 2),
                                  Text(names[i],
                                      style: const TextStyle(
                                          color: ChessPalette.whiteLine, fontSize: 12, fontWeight: FontWeight.w700)),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ================================================================ aksi

  Future<void> _run(Future<ChessGame> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final g = await action();
      if (!mounted) return;
      _apply(g);
    } on ChessException catch (e) {
      if (mounted) _snack(e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<bool> _confirm(String title, String body, String yes, {bool danger = false}) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surfaceDark,
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
        content: Text(body, style: const TextStyle(color: AppColors.textSecondary, fontSize: 13.5)),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Tidak')),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(yes,
                style: TextStyle(
                    color: danger ? AppColors.errorRed : AppColors.accentViolet, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
    return ok == true;
  }

  Future<void> _resign() async {
    final g = _game;
    if (g == null) return;
    final abort = g.ply < 2;
    final ok = await _confirm(
      abort ? 'Batalkan permainan?' : 'Menyerah?',
      abort
          ? 'Kedua pemain belum melangkah, jadi permainan dibatalkan tanpa pemenang.'
          : 'Lawanmu langsung dinyatakan menang.',
      abort ? 'Batalkan' : 'Menyerah',
      danger: true,
    );
    if (ok) await _run(() => _repo.resign(g.id));
  }

  Future<void> _offerDraw() async {
    final g = _game;
    if (g == null) return;
    final ok = await _confirm('Tawarkan remis?', 'Kalau lawan setuju, permainan berakhir seri.', 'Tawarkan');
    if (ok) await _run(() => _repo.draw(g.id, 'offer'));
  }

  Future<void> _cancelWaiting() async {
    final g = _game;
    if (g == null) return;
    await _run(() => _repo.cancel(g.id));
  }

  Future<void> _rematch() async {
    final g = _game;
    if (g == null || _busy) return;
    setState(() => _busy = true);
    try {
      final next = await _repo.rematch(g.id);
      if (!mounted) return;
      Navigator.of(context).pushReplacement(fadeRoute(ChessGameScreen(gameId: next.id, initial: next)));
    } on ChessException catch (e) {
      if (mounted) {
        _snack(e.message);
        setState(() => _busy = false);
      }
    }
  }

  void _openRematch(String id) {
    Navigator.of(context).pushReplacement(fadeRoute(ChessGameScreen(gameId: id)));
  }

  Future<void> _shareCode(String code) async {
    await Share.share('Ayo main catur di Zenime! Buka Zenime Games → Catur → Masuk pakai kode, lalu ketik: $code');
  }

  void _snack(String msg) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(msg)));
  }

  // ================================================================ UI

  @override
  Widget build(BuildContext context) {
    final g = _game;

    return GlassScaffold(
      backgroundColor: AppColors.backgroundDark,
      appBar: GlassAppBar(
        backgroundColor: AppColors.backgroundDark,
        leading: IconButton(
          onPressed: () => Navigator.of(context).maybePop(),
          tooltip: 'Kembali',
          icon: const Icon(Icons.arrow_back_rounded, color: AppColors.textWhite),
        ),
        title: Text(
          g == null ? 'Catur' : _title(g),
          style: const TextStyle(color: AppColors.textWhite, fontSize: 18, fontWeight: FontWeight.w700),
        ),
        actions: [
          if (g != null && g.isActive && g.myColor != null)
            PopupMenuButton<String>(
              tooltip: 'Opsi permainan',
              color: AppColors.surfaceElevated,
              icon: const Icon(Icons.more_vert_rounded, color: AppColors.textWhite),
              onSelected: (v) {
                if (v == 'draw') _offerDraw();
                if (v == 'resign') _resign();
              },
              itemBuilder: (_) => [
                if (g.ply >= 2 && g.drawOfferBy == null)
                  const PopupMenuItem(value: 'draw', child: Text('Tawarkan remis')),
                PopupMenuItem(value: 'resign', child: Text(g.ply < 2 ? 'Batalkan permainan' : 'Menyerah')),
              ],
            ),
        ],
      ),
      body: _body(g),
    );
  }

  String _title(ChessGame g) {
    final mins = g.baseMs ~/ 60000;
    final inc = g.incMs ~/ 1000;
    return inc > 0 ? 'Catur · $mins + $inc' : 'Catur · $mins menit';
  }

  Widget _body(ChessGame? g) {
    if (g == null) {
      if (_error != null) {
        return _Message(
          icon: Icons.wifi_off_rounded,
          text: _error!,
          action: 'Coba lagi',
          onAction: () {
            setState(() => _error = null);
            _load();
          },
        );
      }
      return const Center(child: CircularProgressIndicator(color: AppColors.accentViolet));
    }

    final uid = _uid ?? '';
    if (g.isClosed) {
      final text = switch (g.status) {
        ChessStatus.declined => 'Tantangan ditolak.',
        ChessStatus.cancelled => 'Tantangan dibatalkan.',
        _ => 'Tantangan sudah kedaluwarsa karena tidak ada yang bergabung.',
      };
      return _Message(
        icon: Icons.hourglass_disabled_rounded,
        text: text,
        action: 'Kembali ke lobby',
        onAction: () => Navigator.of(context).maybePop(),
      );
    }

    final flipped = g.myColor == 'b';
    final myColor = g.myColor ?? (flipped ? 'b' : 'w');
    final oppColor = myColor == 'w' ? 'b' : 'w';
    final opp = g.isWaiting ? g.opponentOf(uid) : (oppColor == 'w' ? g.white : g.black);
    final me = g.isWaiting ? (g.creator?.uid == uid ? g.creator : g.invitee) : (myColor == 'w' ? g.white : g.black);

    final selectedTargets = _selected == null ? const <String>{} : _targetsFor(g, _selected!);
    final checkSq = g.inCheck ? chessKingSquare(_pieces, g.turn) : null;
    final lastFrom = _pendingUci?.substring(0, 2) ?? g.lastMove?.from;
    final lastTo = _pendingUci?.substring(2, 4) ?? g.lastMove?.to;

    return LayoutBuilder(builder: (context, c) {
      final maxBoard = c.maxWidth - 24;
      final boardSize = maxBoard.clamp(0.0, c.maxHeight * 0.62).toDouble();
      return ListView(
        physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
        padding: EdgeInsets.fromLTRB(12, 6, 12, 24 + MediaQuery.paddingOf(context).bottom),
        children: [
          _PlayerBar(
            player: opp,
            color: oppColor,
            game: g,
            tick: _tick,
            placeholder: g.isWaiting ? 'Menunggu lawan…' : 'Lawan',
          ),
          const SizedBox(height: 8),
          Center(
            child: SizedBox.square(
              dimension: boardSize,
              child: ChessBoardView(
                pieces: _pieces,
                flipped: flipped,
                lastFrom: lastFrom,
                lastTo: lastTo,
                moveKey: g.ply + (_pendingUci != null ? 1 : 0),
                checkSquare: _pendingUci == null ? checkSq : null,
                selected: _selected,
                targets: selectedTargets,
                canPick: g.isActive ? _canPick : null,
                onSelect: (s) => setState(() => _selected = s),
                onMove: _onMove,
                dimmed: g.isWaiting,
              ),
            ),
          ),
          const SizedBox(height: 8),
          _PlayerBar(player: me, color: myColor, game: g, tick: _tick, placeholder: 'Kamu', isMe: true),
          const SizedBox(height: 12),
          if (_voice != null) ...[
            ChessVoiceBar(call: _voice!, opponentName: opp?.username ?? 'Lawan', tick: _tick),
            const SizedBox(height: 12),
          ],
          if (g.isWaiting) _waitingCard(g, uid),
          if (g.isActive) ..._activeExtras(g),
          if (g.isOver) _resultCard(g),
          if (g.history.isNotEmpty) ...[
            const SizedBox(height: 12),
            _MoveList(history: g.history, controller: _movesScroll),
          ],
        ],
      );
    });
  }

  List<Widget> _activeExtras(ChessGame g) {
    final out = <Widget>[];
    final oppOffer = g.drawOfferBy != null && g.drawOfferBy != g.myColor;
    if (oppOffer) {
      out.add(_Banner(
        icon: Icons.handshake_rounded,
        text: 'Lawan menawarkan remis.',
        actions: [
          _SmallButton(label: 'Tolak', onTap: _busy ? null : () => _run(() => _repo.draw(g.id, 'decline'))),
          _SmallButton(
            label: 'Terima',
            primary: true,
            onTap: _busy ? null : () => _run(() => _repo.draw(g.id, 'accept')),
          ),
        ],
      ));
      out.add(const SizedBox(height: 10));
    } else if (g.drawOfferBy != null && g.drawOfferBy == g.myColor) {
      out.add(const _Banner(icon: Icons.handshake_outlined, text: 'Tawaran remis terkirim. Menunggu jawaban lawan.'));
      out.add(const SizedBox(height: 10));
    }

    out.add(ValueListenableBuilder<int>(
      valueListenable: _tick,
      builder: (_, __, ___) {
        final first = g.firstMoveLeftMs();
        String text;
        Color color = AppColors.textSecondary;
        if (_pendingUci != null) {
          text = 'Mengirim langkah…';
        } else if (g.isMyTurn) {
          text = g.inCheck ? 'Skak! Selamatkan rajamu.' : 'Giliranmu';
          color = g.inCheck ? AppColors.accentVioletLight : AppColors.textWhite;
          if (first != null) text += ' · langkah pertama dalam ${(first / 1000).ceil()} dtk';
        } else {
          text = 'Giliran lawan';
          if (first != null) text += ' · ${(first / 1000).ceil()} dtk untuk langkah pertama';
        }
        return Text(
          text,
          textAlign: TextAlign.center,
          style: TextStyle(color: color, fontSize: 14, fontWeight: FontWeight.w700),
        );
      },
    ));
    return out;
  }

  Widget _waitingCard(ChessGame g, String uid) {
    final mine = g.creator?.uid == uid;
    final code = g.code;

    if (!mine) {
      // Aku yang diundang: terima / tolak dari sini juga bisa.
      return _Card(
        children: [
          Text(
            '${g.creator?.username ?? 'Temanmu'} menantangmu main catur.',
            style: const TextStyle(color: AppColors.textWhite, fontSize: 15, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _SmallButton(
                  label: 'Tolak',
                  onTap: _busy ? null : () => _run(() => _repo.decline(g.id)),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _SmallButton(
                  label: 'Terima & main',
                  primary: true,
                  onTap: _busy ? null : () => _run(() => _repo.accept(g.id)),
                ),
              ),
            ],
          ),
        ],
      );
    }

    return _Card(
      children: [
        if (code != null) ...[
          const Text('Kode room', style: TextStyle(color: AppColors.textSecondary, fontSize: 13)),
          const SizedBox(height: 6),
          GestureDetector(
            onTap: () {
              Clipboard.setData(ClipboardData(text: code));
              _snack('Kode disalin');
            },
            child: Text(
              code.split('').join(' '),
              style: const TextStyle(
                color: AppColors.textWhite,
                fontSize: 32,
                fontWeight: FontWeight.w800,
                letterSpacing: 2,
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'Bagikan kode ini. Permainan mulai otomatis begitu temanmu masuk.',
            style: TextStyle(color: AppColors.textSecondary, fontSize: 13, height: 1.35),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _SmallButton(
                  label: 'Salin',
                  onTap: () {
                    Clipboard.setData(ClipboardData(text: code));
                    _snack('Kode disalin');
                  },
                ),
              ),
              const SizedBox(width: 10),
              Expanded(child: _SmallButton(label: 'Bagikan', primary: true, onTap: () => _shareCode(code))),
            ],
          ),
        ] else
          Text(
            'Menunggu ${g.invitee?.username ?? 'temanmu'} menerima tantangan.',
            style: const TextStyle(color: AppColors.textWhite, fontSize: 15, fontWeight: FontWeight.w700),
          ),
        const SizedBox(height: 10),
        ValueListenableBuilder<int>(
          valueListenable: _tick,
          builder: (_, __, ___) {
            final exp = g.expiresAt;
            if (exp == null) return const SizedBox.shrink();
            final serverNow = g.serverNow.add(DateTime.now().difference(g.receivedAt));
            final left = exp.difference(serverNow);
            final m = left.isNegative ? 0 : left.inMinutes;
            final s = left.isNegative ? 0 : left.inSeconds % 60;
            return Text(
              'Berlaku ${m.toString()}:${s.toString().padLeft(2, '0')} lagi',
              style: const TextStyle(color: AppColors.textMuted, fontSize: 12),
            );
          },
        ),
        const SizedBox(height: 6),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton(
            onPressed: _busy ? null : _cancelWaiting,
            child: const Text('Batalkan tantangan', style: TextStyle(color: AppColors.errorRed)),
          ),
        ),
      ],
    );
  }

  Widget _resultCard(ChessGame g) {
    final outcome = g.outcomeFor(g.myColor);
    final title = switch (outcome) {
      'win' => 'Kamu menang!',
      'loss' => 'Kamu kalah',
      'draw' => 'Remis',
      _ => g.status == ChessStatus.aborted ? 'Dibatalkan' : 'Selesai',
    };
    final accent = switch (outcome) {
      'win' => AppColors.successGreen,
      'loss' => AppColors.accentViolet,
      _ => AppColors.textSecondary,
    };
    final rm = g.rematch;

    Widget rematchButton;
    if (rm != null && !rm.byMe) {
      rematchButton = _SmallButton(
        label: 'Terima ajakan main lagi',
        primary: true,
        onTap: _busy ? null : _rematch,
      );
    } else if (rm != null && rm.byMe) {
      rematchButton = _SmallButton(label: 'Menunggu lawan…', onTap: () => _openRematch(rm.id));
    } else {
      rematchButton = _SmallButton(label: 'Main lagi', primary: true, onTap: _busy ? null : _rematch);
    }

    return _Card(
      borderColor: accent.withValues(alpha: 0.5),
      children: [
        Text(title, style: TextStyle(color: accent, fontSize: 22, fontWeight: FontWeight.w800)),
        const SizedBox(height: 4),
        Text(chessEndText(g), style: const TextStyle(color: AppColors.textSecondary, fontSize: 13.5)),
        const SizedBox(height: 14),
        Row(
          children: [
            Expanded(child: _SmallButton(label: 'Ke lobby', onTap: () => Navigator.of(context).maybePop())),
            const SizedBox(width: 10),
            Expanded(flex: 2, child: rematchButton),
          ],
        ),
      ],
    );
  }
}

// ============================================================================
// Komponen kecil
// ============================================================================

String _fmtClock(int ms) {
  final totalSec = (ms / 1000).ceil();
  final m = totalSec ~/ 60;
  final s = totalSec % 60;
  if (ms < 10000 && ms > 0) {
    // 10 detik terakhir: tampilkan persepuluhan.
    final tenths = (ms % 1000) ~/ 100;
    return '0:0${ms ~/ 1000}.$tenths';
  }
  return '$m:${s.toString().padLeft(2, '0')}';
}

class _PlayerBar extends StatelessWidget {
  const _PlayerBar({
    required this.player,
    required this.color,
    required this.game,
    required this.tick,
    required this.placeholder,
    this.isMe = false,
  });

  final ChessPlayer? player;
  final String color;
  final ChessGame game;
  final ValueListenable<int> tick;
  final String placeholder;
  final bool isMe;

  @override
  Widget build(BuildContext context) {
    final p = player;
    final showClock = game.isActive || game.isOver;
    return Row(
      children: [
        if (p != null)
          FriendAvatar(url: p.avatarUrl, seed: p.uid, label: p.username, size: 34)
        else
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppColors.surfaceElevated,
              border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
            ),
            child: const Icon(Icons.person_outline_rounded, size: 18, color: AppColors.textMuted),
          ),
        const SizedBox(width: 10),
        Expanded(
          child: Row(
            children: [
              Flexible(
                child: Text(
                  p == null ? placeholder : (isMe ? '${p.username} (kamu)' : p.username),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: p == null ? AppColors.textSecondary : AppColors.textWhite,
                    fontSize: 14.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: 6),
              if (!game.isWaiting)
                SizedBox.square(dimension: 18, child: ChessPieceGlyph(piece: color == 'w' ? 'K' : 'k', size: 18)),
            ],
          ),
        ),
        if (showClock)
          ValueListenableBuilder<int>(
            valueListenable: tick,
            builder: (_, __, ___) {
              final running = game.isActive && game.clockRunning == color;
              final ms = game.remainingMs(color);
              final low = ms < 20000;
              return AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(10),
                  color: running
                      ? (low ? AppColors.accentViolet : AppColors.textWhite)
                      : AppColors.surfaceElevated,
                ),
                child: Text(
                  _fmtClock(ms),
                  style: TextStyle(
                    color: running ? (low ? Colors.white : AppColors.backgroundDark) : AppColors.textSecondary,
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              );
            },
          ),
      ],
    );
  }
}

class _MoveList extends StatelessWidget {
  const _MoveList({required this.history, required this.controller});

  final List<String> history;
  final ScrollController controller;

  @override
  Widget build(BuildContext context) {
    final pairs = <String>[];
    for (var i = 0; i < history.length; i += 2) {
      final black = i + 1 < history.length ? ' ${history[i + 1]}' : '';
      pairs.add('${i ~/ 2 + 1}. ${history[i]}$black');
    }
    return SizedBox(
      height: 34,
      child: ListView.separated(
        controller: controller,
        scrollDirection: Axis.horizontal,
        itemCount: pairs.length,
        separatorBuilder: (_, __) => const SizedBox(width: 6),
        itemBuilder: (_, i) {
          final last = i == pairs.length - 1;
          return Container(
            alignment: Alignment.center,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            decoration: BoxDecoration(
              color: last ? AppColors.accentVioletSubtle : AppColors.surfaceCard,
              borderRadius: BorderRadius.circular(9),
            ),
            child: Text(
              pairs[i],
              style: TextStyle(
                color: last ? AppColors.textWhite : AppColors.textSecondary,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          );
        },
      ),
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({required this.children, this.borderColor});

  final List<Widget> children;
  final Color? borderColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        color: AppColors.surfaceCard,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: borderColor ?? Colors.white.withValues(alpha: 0.08)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: children),
    );
  }
}

class _Banner extends StatelessWidget {
  const _Banner({required this.icon, required this.text, this.actions = const []});

  final IconData icon;
  final String text;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
      decoration: BoxDecoration(
        color: AppColors.surfaceElevated,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Icon(icon, color: AppColors.warningAmber, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(text, style: const TextStyle(color: AppColors.textWhite, fontSize: 13.5)),
          ),
          for (final a in actions) ...[const SizedBox(width: 6), a],
        ],
      ),
    );
  }
}

class _SmallButton extends StatelessWidget {
  const _SmallButton({required this.label, required this.onTap, this.primary = false});

  final String label;
  final VoidCallback? onTap;
  final bool primary;

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    return Opacity(
      opacity: enabled ? 1 : 0.5,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Ink(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              gradient: primary
                  ? const LinearGradient(colors: [AppColors.accentVioletDark, AppColors.accentVioletLight])
                  : null,
              color: primary ? null : AppColors.surfaceElevated,
            ),
            child: Center(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: primary ? Colors.white : AppColors.textWhite,
                  fontSize: 13.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({required this.icon, required this.text, required this.action, required this.onAction});

  final IconData icon;
  final String text;
  final String action;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 44, color: AppColors.textMuted),
            const SizedBox(height: 12),
            Text(text,
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppColors.textSecondary, fontSize: 14.5, height: 1.4)),
            const SizedBox(height: 16),
            _SmallButton(label: action, primary: true, onTap: onAction),
          ],
        ),
      ),
    );
  }
}

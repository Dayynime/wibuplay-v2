import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../data/models/chess_models.dart';
import '../../../data/models/friend_models.dart';
import '../../../data/realtime/chess_realtime_client.dart';
import '../../../data/repository/chess_repository.dart';
import '../../../providers.dart';
import '../../app_routes.dart';
import '../../components/friend_avatar.dart';
import '../../glass/glass.dart';
import 'chess_board.dart';
import 'chess_game_screen.dart';

/// Lobby catur: tantangan masuk, yang menunggu lawan, permainan berjalan,
/// dan riwayat. Dari sini user menantang teman, membuat room berkode, atau
/// masuk ke room orang lain pakai kode.
class ChessLobbyScreen extends ConsumerStatefulWidget {
  const ChessLobbyScreen({super.key});

  @override
  ConsumerState<ChessLobbyScreen> createState() => _ChessLobbyScreenState();
}

class _ChessLobbyScreenState extends ConsumerState<ChessLobbyScreen> with WidgetsBindingObserver {
  late final ChessRepository _repo;
  ChessRealtimeClient? _rt;
  StreamSubscription<Map<String, dynamic>>? _rtSub;
  Timer? _debounce;
  Timer? _poll;

  ChessLobby? _lobby;

  /// Permainan orang lain yang sedang berlangsung (bisa ditonton).
  List<ChessGame> _live = const [];
  String? _error;
  bool _busy = false;
  bool _inGame = false;
  int _loadSeq = 0;

  /// Room / undangan buatanku yang masih menunggu; kalau berubah jadi
  /// berjalan selagi lobby terbuka, permainan langsung dibuka.
  Set<String> _myWaiting = <String>{};

  final TextEditingController _codeCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _repo = ref.read(chessRepositoryProvider);
    _load();
    final uid = ref.read(authUserProvider).valueOrNull?.uid;
    if (uid != null && uid.isNotEmpty) {
      _rt = ChessRealtimeClient('chess-user-$uid', onJoined: _scheduleLoad);
      _rtSub = _rt!.pings.listen((_) => _scheduleLoad());
      _rt!.start();
    }
    _poll = Timer.periodic(const Duration(seconds: 20), (_) {
      if (_inGame) return;
      if (!(_rt?.isJoined ?? false)) _load(silent: true);
      _loadLive();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _debounce?.cancel();
    _poll?.cancel();
    _rtSub?.cancel();
    unawaited(_rt?.stop());
    _codeCtrl.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && !_inGame) _load(silent: true);
  }

  void _scheduleLoad() {
    if (_inGame) return;
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 250), () => _load(silent: true));
  }

  Future<void> _loadLive() async {
    try {
      final live = await _repo.live();
      if (mounted) setState(() => _live = live);
    } catch (_) {
      // Daftar tontonan cuma pelengkap.
    }
  }

  Future<void> _load({bool silent = false}) async {
    unawaited(_loadLive());
    final seq = ++_loadSeq;
    try {
      final lobby = await _repo.lobby();
      if (!mounted || seq != _loadSeq) return;
      final started = lobby.active.where((g) => _myWaiting.contains(g.id)).toList();
      setState(() {
        _lobby = lobby;
        _error = null;
        _myWaiting = lobby.waiting.map((g) => g.id).toSet();
      });
      if (started.isNotEmpty && !_inGame) {
        HapticFeedback.mediumImpact();
        _open(started.first);
      }
    } on ChessException catch (e) {
      if (!mounted || seq != _loadSeq) return;
      if (_lobby == null) {
        setState(() => _error = e.message);
      } else if (!silent) {
        _snack(e.message);
      }
    }
  }

  Future<void> _open(ChessGame g) async {
    _inGame = true;
    await Navigator.of(context).push<void>(fadeRoute(ChessGameScreen(gameId: g.id, initial: g)));
    _inGame = false;
    if (mounted) _load(silent: true);
  }

  Future<void> _run(Future<ChessGame> Function() action, {bool openAfter = true}) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final g = await action();
      if (!mounted) return;
      setState(() => _busy = false);
      if (openAfter && (g.isActive || g.isWaiting)) {
        await _open(g);
      } else {
        _load(silent: true);
      }
    } on ChessException catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      _snack(e.message);
    }
  }

  void _join() {
    final code = _codeCtrl.text.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');
    if (code.length != 6) {
      _snack('Kode room terdiri dari 6 huruf/angka');
      return;
    }
    FocusScope.of(context).unfocus();
    _codeCtrl.clear();
    _run(() => _repo.join(code));
  }

  Future<void> _newGame({required bool friend}) async {
    final res = await showGlassSheet<_NewGameChoice>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surfaceDark,
      builder: (_) => _NewGameSheet(friendMode: friend),
    );
    if (res == null || !mounted) return;
    await _run(() => _repo.create(time: res.time, color: res.color, inviteeUid: res.friendUid));
  }

  void _snack(String msg) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(msg)));
  }

  /// 0 = Permainanku, 1 = Tonton.
  int _tab = 0;

  @override
  Widget build(BuildContext context) {
    final uid = ref.read(authUserProvider).valueOrNull?.uid ?? '';
    final l = _lobby;
    final myBadge = l == null ? 0 : l.incoming.length + l.active.where((g) => g.isMyTurn).length;
    return GlassScaffold(
      backgroundColor: AppColors.backgroundDark,
      appBar: GlassAppBar(
        backgroundColor: AppColors.backgroundDark,
        leading: IconButton(
          onPressed: () => Navigator.of(context).maybePop(),
          tooltip: 'Kembali',
          icon: const Icon(Icons.arrow_back_rounded, color: AppColors.textWhite),
        ),
        title: const Text(
          'Catur',
          style: TextStyle(color: AppColors.textWhite, fontSize: 18, fontWeight: FontWeight.w700),
        ),
      ),
      body: RefreshIndicator(
        color: AppColors.accentViolet,
        onRefresh: () => _load(),
        child: ListView(
          physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
          padding: EdgeInsets.fromLTRB(16, 4, 16, 32 + MediaQuery.paddingOf(context).bottom),
          children: [
            _header(),
            const SizedBox(height: 16),
            _quickActions(),
            const SizedBox(height: 10),
            _joinCard(),
            const SizedBox(height: 22),
            _LobbyTabs(
              index: _tab,
              myBadge: myBadge,
              liveCount: _live.length,
              onChanged: (i) {
                if (i == _tab) return;
                HapticFeedback.selectionClick();
                setState(() => _tab = i);
              },
            ),
            const SizedBox(height: 16),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 220),
              switchInCurve: Curves.easeOutCubic,
              switchOutCurve: Curves.easeInCubic,
              transitionBuilder: (child, anim) => FadeTransition(
                opacity: anim,
                child: SlideTransition(
                  position: Tween<Offset>(begin: const Offset(0, 0.03), end: Offset.zero).animate(anim),
                  child: child,
                ),
              ),
              layoutBuilder: (current, previous) => Stack(
                alignment: Alignment.topCenter,
                children: [...previous, if (current != null) current],
              ),
              child: Column(
                key: ValueKey(_tab),
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: _tab == 0 ? _myGames(uid) : _watchList(),
              ),
            ),
            const SizedBox(height: 32),
            const _ChessSignature(),
          ],
        ),
      ),
    );
  }

  // --------------------------------------------------------------------------
  // Bagian atas: judul, aksi cepat, masuk pakai kode
  // --------------------------------------------------------------------------

  Widget _header() {
    return Row(
      children: [
        Container(
          width: 56,
          height: 56,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF2A3142), AppColors.surfaceCard],
            ),
            border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
          ),
          child: const ChessPieceGlyph(piece: 'N', size: 38),
        ),
        const SizedBox(width: 14),
        const Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Main catur',
                style: TextStyle(color: AppColors.textWhite, fontSize: 20, fontWeight: FontWeight.w800),
              ),
              SizedBox(height: 3),
              Text(
                '1 lawan 1 · langkah dicek server, anti curang',
                style: TextStyle(color: AppColors.textSecondary, fontSize: 12.5),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _quickActions() {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: _ActionTile(
              icon: Icons.group_rounded,
              title: 'Tantang teman',
              subtitle: 'Pilih dari daftar temanmu',
              primary: true,
              onTap: _busy ? null : () => _newGame(friend: true),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: _ActionTile(
              icon: Icons.tag_rounded,
              title: 'Buat room',
              subtitle: 'Dapat kode untuk dibagikan',
              onTap: _busy ? null : () => _newGame(friend: false),
            ),
          ),
        ],
      ),
    );
  }

  Widget _joinCard() {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 4, 6, 4),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        color: AppColors.surfaceCard,
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
      ),
      child: Row(
        children: [
          const Icon(Icons.vpn_key_rounded, size: 20, color: AppColors.textMuted),
          const SizedBox(width: 10),
          Expanded(
            child: TextField(
              controller: _codeCtrl,
              textCapitalization: TextCapitalization.characters,
              maxLength: 6,
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[A-Za-z0-9]')),
                TextInputFormatter.withFunction((o, n) => n.copyWith(text: n.text.toUpperCase())),
              ],
              onSubmitted: (_) => _join(),
              style: const TextStyle(
                color: AppColors.textWhite,
                fontSize: 16,
                fontWeight: FontWeight.w800,
                letterSpacing: 4,
              ),
              decoration: const InputDecoration(
                counterText: '',
                isDense: true,
                border: InputBorder.none,
                hintText: 'Punya kode room? Ketik di sini',
                hintStyle: TextStyle(
                  color: AppColors.textMuted,
                  fontSize: 13.5,
                  letterSpacing: 0,
                  fontWeight: FontWeight.w500,
                ),
                contentPadding: EdgeInsets.symmetric(vertical: 14),
              ),
            ),
          ),
          ValueListenableBuilder<TextEditingValue>(
            valueListenable: _codeCtrl,
            builder: (_, v, __) {
              final ready = v.text.length == 6 && !_busy;
              return AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                height: 40,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  color: ready ? AppColors.accentViolet : AppColors.surfaceElevated,
                ),
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: _busy ? null : _join,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'Masuk',
                          style: TextStyle(
                            color: ready ? Colors.white : AppColors.textSecondary,
                            fontWeight: FontWeight.w800,
                            fontSize: 13,
                          ),
                        ),
                        const SizedBox(width: 4),
                        Icon(Icons.arrow_forward_rounded,
                            size: 16, color: ready ? Colors.white : AppColors.textSecondary),
                      ],
                    ),
                    ),
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  // --------------------------------------------------------------------------
  // Tab "Permainanku"
  // --------------------------------------------------------------------------

  List<Widget> _myGames(String uid) {
    final l = _lobby;
    if (l == null) {
      if (_error != null) {
        return [
          _EmptyState(
            icon: Icons.wifi_off_rounded,
            title: 'Lobby gagal dimuat',
            message: _error!,
            actionLabel: 'Coba lagi',
            onAction: _load,
          ),
        ];
      }
      return const [
        Padding(
          padding: EdgeInsets.symmetric(vertical: 40),
          child: Center(child: CircularProgressIndicator(color: AppColors.accentViolet)),
        ),
      ];
    }
    if (l.isEmpty) {
      return [
        _EmptyState(
          glyph: 'k',
          title: 'Belum ada permainan',
          message: 'Tantang teman, atau buat room lalu bagikan kodenya. Permainanmu akan muncul di sini.',
          actionLabel: 'Tantang teman',
          onAction: _busy ? null : () => _newGame(friend: true),
        ),
      ];
    }

    final out = <Widget>[];
    void section(String title, int count, List<Widget> rows, {Color? accent}) {
      if (rows.isEmpty) return;
      if (out.isNotEmpty) out.add(const SizedBox(height: 18));
      out.add(_SectionHeader(title: title, count: count, accent: accent));
      for (var i = 0; i < rows.length; i++) {
        if (i > 0) out.add(const SizedBox(height: 8));
        out.add(rows[i]);
      }
    }

    // 1. Tantangan masuk — butuh keputusan, paling atas.
    section(
      'Tantangan masuk',
      l.incoming.length,
      [
        for (final g in l.incoming)
          _IncomingCard(
            game: g,
            subtitle: '${_timeLabel(g)} · ${_colorLabel(g, uid)}',
            busy: _busy,
            onOpen: () => _open(g),
            onAccept: () => _run(() => _repo.accept(g.id)),
            onDecline: () => _run(() => _repo.decline(g.id), openAfter: false),
          ),
      ],
      accent: AppColors.accentViolet,
    );

    // 2. Sedang main — yang giliranku duluan.
    final active = [...l.active]..sort((a, b) => (b.isMyTurn ? 1 : 0) - (a.isMyTurn ? 1 : 0));
    section(
      'Sedang main',
      active.length,
      [
        for (final g in active)
          _GameRow(
            game: g,
            player: g.opponentOf(uid),
            subtitle: '${_timeLabel(g)} · langkah ke-${(g.ply ~/ 2) + 1}',
            highlight: g.isMyTurn,
            trailing: g.isMyTurn
                ? const _Pill(text: 'Giliranmu', color: AppColors.accentViolet, filled: true)
                : const _Pill(text: 'Giliran lawan', color: AppColors.textSecondary),
            onTap: () => _open(g),
          ),
      ],
    );

    // 3. Menunggu lawan.
    section(
      'Menunggu lawan',
      l.waiting.length,
      [
        for (final g in l.waiting)
          g.invitee == null
              ? _GameRow(
                  game: g,
                  player: null,
                  title: 'Room ${g.code ?? ''}',
                  subtitle: '${_timeLabel(g)} · bagikan kode ke lawanmu',
                  trailing: g.code == null
                      ? const Icon(Icons.chevron_right_rounded, color: AppColors.textMuted)
                      : IconButton(
                          tooltip: 'Salin kode',
                          onPressed: () => _copyCode(g.code!),
                          icon: const Icon(Icons.content_copy_rounded, size: 20, color: AppColors.textSecondary),
                        ),
                  onTap: () => _open(g),
                )
              : _GameRow(
                  game: g,
                  player: g.invitee,
                  subtitle: '${_timeLabel(g)} · menunggu diterima',
                  trailing: const _Pill(text: 'Terkirim', color: AppColors.textSecondary, icon: Icons.schedule_rounded),
                  onTap: () => _open(g),
                ),
      ],
    );

    // 4. Riwayat.
    section(
      'Riwayat',
      l.recent.length,
      [
        for (final g in l.recent)
          () {
            final (label, color) = switch (g.outcomeFor(g.myColor)) {
              'win' => ('Menang', AppColors.successGreen),
              'loss' => ('Kalah', AppColors.accentVioletLight),
              'draw' => ('Remis', AppColors.textSecondary),
              _ => ('Batal', AppColors.textMuted),
            };
            return _GameRow(
              game: g,
              player: g.opponentOf(uid),
              subtitle: '${_timeLabel(g)} · ${chessEndText(g)}',
              trailing: _Pill(text: label, color: color),
              onTap: () => _open(g),
            );
          }(),
      ],
    );

    return out;
  }

  // --------------------------------------------------------------------------
  // Tab "Tonton": permainan orang lain yang sedang berjalan. Bebas masuk
  // sebagai penonton (tanpa kode), tidak bisa menggerakkan bidak.
  // --------------------------------------------------------------------------

  List<Widget> _watchList() {
    if (_live.isEmpty) {
      return const [
        _EmptyState(
          icon: Icons.visibility_rounded,
          title: 'Belum ada yang main',
          message: 'Kalau ada pemain lain yang sedang bertanding, permainannya muncul di sini dan bisa langsung kamu tonton.',
        ),
      ];
    }
    return [
      const Padding(
        padding: EdgeInsets.only(left: 2, bottom: 10),
        child: Text(
          'Ketuk untuk menonton. Penonton tidak bisa menggerakkan bidak.',
          style: TextStyle(color: AppColors.textMuted, fontSize: 12.5),
        ),
      ),
      for (var i = 0; i < _live.length; i++) ...[
        if (i > 0) const SizedBox(height: 10),
        _LiveCard(
          game: _live[i],
          timeLabel: _timeLabel(_live[i]),
          onTap: () => _open(_live[i]),
        ),
      ],
    ];
  }

  void _copyCode(String code) {
    Clipboard.setData(ClipboardData(text: code));
    HapticFeedback.selectionClick();
    _snack('Kode $code disalin');
  }

  static String _timeLabel(ChessGame g) {
    final m = g.baseMs ~/ 60000;
    final i = g.incMs ~/ 1000;
    return i > 0 ? '$m + $i' : '$m menit';
  }

  static String _colorLabel(ChessGame g, String uid) {
    // Warna untuk yang diundang = kebalikan pilihan pembuat.
    switch (g.creatorColor) {
      case 'w':
        return 'kamu hitam';
      case 'b':
        return 'kamu putih';
      default:
        return 'warna acak';
    }
  }
}

// ============================================================================
// Lembar buat tantangan
// ============================================================================

class _NewGameChoice {
  const _NewGameChoice(this.time, this.color, this.friendUid);
  final String time;
  final String color;
  final String? friendUid;
}

class _NewGameSheet extends ConsumerStatefulWidget {
  const _NewGameSheet({required this.friendMode});

  final bool friendMode;

  @override
  ConsumerState<_NewGameSheet> createState() => _NewGameSheetState();
}

class _NewGameSheetState extends ConsumerState<_NewGameSheet> {
  String _time = '10+0';
  String _color = 'random';
  String _query = '';
  List<FriendDisplay>? _friends;
  String? _error;

  @override
  void initState() {
    super.initState();
    if (widget.friendMode) _loadFriends();
  }

  Future<void> _loadFriends() async {
    final uid = ref.read(authUserProvider).valueOrNull?.uid;
    if (uid == null || uid.isEmpty) {
      setState(() => _error = 'Kamu harus login dulu');
      return;
    }
    try {
      final lists = await ref.read(friendRepositoryProvider).getLists(uid);
      if (mounted) setState(() => _friends = lists.friends);
    } catch (_) {
      if (mounted) setState(() => _error = 'Daftar teman gagal dimuat');
    }
  }

  @override
  Widget build(BuildContext context) {
    final h = MediaQuery.sizeOf(context).height;
    return SafeArea(
      top: false,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: h * 0.85),
        child: Padding(
          padding: EdgeInsets.fromLTRB(18, 16, 18, 16 + MediaQuery.viewInsetsOf(context).bottom),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                widget.friendMode ? 'Tantang teman' : 'Buat room',
                style: const TextStyle(color: AppColors.textWhite, fontSize: 18, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 14),
              const _Label('Waktu tiap pemain'),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final p in ChessTimePreset.all)
                    _Choice(
                      label: p.label,
                      hint: p.hint,
                      selected: _time == p.id,
                      onTap: () => setState(() => _time = p.id),
                    ),
                ],
              ),
              const SizedBox(height: 14),
              const _Label('Kamu main sebagai'),
              Row(
                children: [
                  for (final c in const [('w', 'Putih', 'K'), ('random', 'Acak', null), ('b', 'Hitam', 'k')]) ...[
                    Expanded(
                      child: _Choice(
                        label: c.$2,
                        icon: c.$3,
                        selected: _color == c.$1,
                        onTap: () => setState(() => _color = c.$1),
                      ),
                    ),
                    if (c.$1 != 'b') const SizedBox(width: 8),
                  ],
                ],
              ),
              const SizedBox(height: 16),
              if (widget.friendMode) ..._friendPicker() else _createRoomButton(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _createRoomButton() {
    return _ActionButton(
      icon: Icons.tag_rounded,
      label: 'Buat room & dapatkan kode',
      primary: true,
      onTap: () => Navigator.of(context).pop(_NewGameChoice(_time, _color, null)),
    );
  }

  List<Widget> _friendPicker() {
    final friends = _friends;
    final out = <Widget>[const _Label('Pilih teman')];
    if (_error != null) {
      out.add(Text(_error!, style: const TextStyle(color: AppColors.textSecondary)));
      return out;
    }
    if (friends == null) {
      out.add(const Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: Center(child: CircularProgressIndicator(color: AppColors.accentViolet)),
      ));
      return out;
    }
    if (friends.isEmpty) {
      out.add(const Text(
        'Kamu belum punya teman di Zenime. Tambahkan teman dulu dari Profil, atau pakai "Buat room" dan bagikan kodenya.',
        style: TextStyle(color: AppColors.textSecondary, fontSize: 13.5, height: 1.4),
      ));
      return out;
    }
    final q = _query.trim().toLowerCase();
    final shown = q.isEmpty ? friends : friends.where((f) => f.username.toLowerCase().contains(q)).toList();
    if (friends.length > 6) {
      out.add(Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: TextField(
          onChanged: (v) => setState(() => _query = v),
          style: const TextStyle(color: AppColors.textWhite),
          decoration: InputDecoration(
            isDense: true,
            prefixIcon: const Icon(Icons.search_rounded, color: AppColors.textMuted, size: 20),
            hintText: 'Cari teman',
            hintStyle: const TextStyle(color: AppColors.textMuted),
            filled: true,
            fillColor: AppColors.surfaceCard,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
          ),
        ),
      ));
    }
    out.add(Flexible(
      child: ListView.builder(
        shrinkWrap: true,
        itemCount: shown.length,
        itemBuilder: (_, i) {
          final f = shown[i];
          return ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 4),
            leading: FriendAvatar(url: f.avatarUrl, seed: f.firebaseUid, label: f.username, size: 40),
            title: Text(f.username,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: AppColors.textWhite, fontWeight: FontWeight.w700)),
            subtitle: f.userNumber == null
                ? null
                : Text('ID #${f.userNumber}', style: const TextStyle(color: AppColors.textMuted, fontSize: 12)),
            trailing: const Text('Tantang',
                style: TextStyle(color: AppColors.accentVioletLight, fontWeight: FontWeight.w800)),
            onTap: () => Navigator.of(context).pop(_NewGameChoice(_time, _color, f.firebaseUid)),
          );
        },
      ),
    ));
    return out;
  }
}

class _Label extends StatelessWidget {
  const _Label(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(text, style: const TextStyle(color: AppColors.textSecondary, fontSize: 13, fontWeight: FontWeight.w600)),
      );
}

class _Choice extends StatelessWidget {
  const _Choice({required this.label, required this.selected, required this.onTap, this.hint, this.icon});

  final String label;
  final String? hint;
  final String? icon; // bidak FEN untuk ikon warna
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () {
        HapticFeedback.selectionClick();
        onTap();
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          color: selected ? AppColors.accentVioletSubtle : AppColors.surfaceCard,
          border: Border.all(color: selected ? AppColors.accentViolet : Colors.white.withValues(alpha: 0.08)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (icon != null) ...[
              ChessPieceGlyph(piece: icon!, size: 20),
              const SizedBox(width: 6),
            ] else if (hint == null) ...[
              const Icon(Icons.shuffle_rounded, size: 18, color: AppColors.textSecondary),
              const SizedBox(width: 6),
            ],
            Text(label,
                style: TextStyle(
                    color: selected ? AppColors.textWhite : AppColors.textSecondary,
                    fontWeight: FontWeight.w700,
                    fontSize: 14)),
            if (hint != null) ...[
              const SizedBox(width: 6),
              Text(hint!, style: const TextStyle(color: AppColors.textMuted, fontSize: 12)),
            ],
          ],
        ),
      ),
    );
  }
}

class _GameRow extends StatelessWidget {
  const _GameRow({
    required this.game,
    required this.player,
    required this.subtitle,
    required this.trailing,
    required this.onTap,
    this.title,
    this.highlight = false,
  });

  final ChessGame game;
  final ChessPlayer? player;
  final String? title;
  final String subtitle;
  final Widget trailing;
  final VoidCallback onTap;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    final p = player;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Ink(
          padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            color: AppColors.surfaceCard,
            border: Border.all(
              color: highlight ? AppColors.accentViolet.withValues(alpha: 0.6) : Colors.white.withValues(alpha: 0.06),
            ),
          ),
          child: Row(
            children: [
              if (p != null)
                FriendAvatar(url: p.avatarUrl, seed: p.uid, label: p.username, size: 40)
              else
                Container(
                  width: 40,
                  height: 40,
                  alignment: Alignment.center,
                  decoration: const BoxDecoration(shape: BoxShape.circle, color: AppColors.surfaceElevated),
                  child: const Icon(Icons.tag_rounded, color: AppColors.textSecondary, size: 20),
                ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title ?? p?.username ?? 'Lawan',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: AppColors.textWhite, fontSize: 14.5, fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: highlight ? AppColors.accentVioletLight : AppColors.textSecondary,
                        fontSize: 12.5,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              trailing,
            ],
          ),
        ),
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.label,
    required this.onTap,
    this.icon,
    this.primary = false,
  });

  final String label;
  final IconData? icon;
  final VoidCallback? onTap;
  final bool primary;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: onTap == null ? 0.5 : 1,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Ink(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              gradient: primary
                  ? const LinearGradient(colors: [AppColors.accentVioletDark, AppColors.accentVioletLight])
                  : null,
              color: primary ? null : AppColors.surfaceElevated,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (icon != null) ...[
                  Icon(icon, size: 18, color: Colors.white),
                  const SizedBox(width: 8),
                ],
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ============================================================================
// Komponen lobby
// ============================================================================

class _ActionTile extends StatelessWidget {
  const _ActionTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.primary = false,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;
  final bool primary;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: onTap == null ? 0.5 : 1,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: onTap,
          child: Ink(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              gradient: primary
                  ? const LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [AppColors.accentVioletLight, AppColors.accentVioletDark],
                    )
                  : null,
              color: primary ? null : AppColors.surfaceCard,
              border: primary ? null : Border.all(color: Colors.white.withValues(alpha: 0.06)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 36,
                  height: 36,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(11),
                    color: primary ? Colors.white.withValues(alpha: 0.2) : AppColors.surfaceElevated,
                  ),
                  child: Icon(icon, size: 20, color: Colors.white),
                ),
                const SizedBox(height: 12),
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  maxLines: 2,
                  style: TextStyle(
                    color: primary ? Colors.white.withValues(alpha: 0.8) : AppColors.textSecondary,
                    fontSize: 12,
                    height: 1.3,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _LobbyTabs extends StatelessWidget {
  const _LobbyTabs({
    required this.index,
    required this.myBadge,
    required this.liveCount,
    required this.onChanged,
  });

  final int index;
  final int myBadge;
  final int liveCount;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    Widget seg(int i, String label, Widget? badge) {
      final sel = index == i;
      return Expanded(
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => onChanged(i),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOutCubic,
            height: 40,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(11),
              color: sel ? AppColors.surfaceElevated : Colors.transparent,
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    color: sel ? AppColors.textWhite : AppColors.textSecondary,
                    fontWeight: FontWeight.w800,
                    fontSize: 14,
                  ),
                ),
                if (badge != null) ...[const SizedBox(width: 7), badge],
              ],
            ),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        color: AppColors.surfaceCard,
        border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
      ),
      child: Row(
        children: [
          seg(
            0,
            'Permainanku',
            myBadge > 0 ? _CountBadge(count: myBadge, color: AppColors.accentViolet) : null,
          ),
          seg(
            1,
            'Tonton',
            liveCount > 0
                ? Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const _LiveDot(),
                      const SizedBox(width: 5),
                      Text(
                        '$liveCount',
                        style: const TextStyle(color: Color(0xFFFF4D6A), fontWeight: FontWeight.w800, fontSize: 12.5),
                      ),
                    ],
                  )
                : null,
          ),
        ],
      ),
    );
  }
}

class _CountBadge extends StatelessWidget {
  const _CountBadge({required this.count, required this.color});
  final int count;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minWidth: 20),
      height: 20,
      padding: const EdgeInsets.symmetric(horizontal: 6),
      alignment: Alignment.center,
      decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(10)),
      child: Text(
        count > 99 ? '99+' : '$count',
        style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w800),
      ),
    );
  }
}

/// Titik merah "live" yang berdenyut pelan.
class _LiveDot extends StatefulWidget {
  const _LiveDot();

  @override
  State<_LiveDot> createState() => _LiveDotState();
}

class _LiveDotState extends State<_LiveDot> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1100))..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: Tween<double>(begin: 0.35, end: 1).animate(_c),
      child: Container(
        width: 8,
        height: 8,
        decoration: const BoxDecoration(color: Color(0xFFFF4D6A), shape: BoxShape.circle),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title, required this.count, this.accent});
  final String title;
  final int count;
  final Color? accent;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 2, bottom: 10),
      child: Row(
        children: [
          Text(
            title,
            style: const TextStyle(color: AppColors.textWhite, fontSize: 15, fontWeight: FontWeight.w800),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              color: (accent ?? AppColors.textSecondary).withValues(alpha: 0.16),
            ),
            child: Text(
              '$count',
              style: TextStyle(
                color: accent ?? AppColors.textSecondary,
                fontSize: 11.5,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.text, required this.color, this.filled = false, this.icon});
  final String text;
  final Color color;
  final bool filled;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final fg = filled ? Colors.white : color;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        color: filled ? color : color.withValues(alpha: 0.14),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 13, color: fg),
            const SizedBox(width: 4),
          ],
          Text(text, style: TextStyle(color: fg, fontWeight: FontWeight.w800, fontSize: 12)),
        ],
      ),
    );
  }
}

class _IncomingCard extends StatelessWidget {
  const _IncomingCard({
    required this.game,
    required this.subtitle,
    required this.busy,
    required this.onOpen,
    required this.onAccept,
    required this.onDecline,
  });

  final ChessGame game;
  final String subtitle;
  final bool busy;
  final VoidCallback onOpen;
  final VoidCallback onAccept;
  final VoidCallback onDecline;

  @override
  Widget build(BuildContext context) {
    final p = game.creator;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onOpen,
        child: Ink(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [AppColors.accentViolet.withValues(alpha: 0.16), AppColors.surfaceCard],
            ),
            border: Border.all(color: AppColors.accentViolet.withValues(alpha: 0.45)),
          ),
          child: Column(
            children: [
              Row(
                children: [
                  if (p != null)
                    FriendAvatar(url: p.avatarUrl, seed: p.uid, label: p.username, size: 44)
                  else
                    const SizedBox(width: 44, height: 44),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text.rich(
                          TextSpan(children: [
                            TextSpan(
                              text: p?.username ?? 'Seseorang',
                              style: const TextStyle(fontWeight: FontWeight.w800),
                            ),
                            const TextSpan(
                              text: ' menantangmu',
                              style: TextStyle(color: AppColors.textSecondary, fontWeight: FontWeight.w500),
                            ),
                          ]),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: AppColors.textWhite, fontSize: 14.5),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          subtitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: AppColors.textSecondary, fontSize: 12.5),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: _ActionButton(
                      icon: Icons.close_rounded,
                      label: 'Tolak',
                      onTap: busy ? null : onDecline,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _ActionButton(
                      icon: Icons.check_rounded,
                      label: 'Terima',
                      primary: true,
                      onTap: busy ? null : onAccept,
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
}

class _LiveCard extends StatelessWidget {
  const _LiveCard({required this.game, required this.timeLabel, required this.onTap});

  final ChessGame game;
  final String timeLabel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final g = game;
    Widget side(ChessPlayer? p, String fallback, String piece, bool toMove) {
      return Expanded(
        child: Column(
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  padding: const EdgeInsets.all(2),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: toMove ? AppColors.accentViolet : Colors.transparent,
                      width: 2,
                    ),
                  ),
                  child: p != null
                      ? FriendAvatar(url: p.avatarUrl, seed: p.uid, label: p.username, size: 44)
                      : Container(
                          width: 44,
                          height: 44,
                          decoration: const BoxDecoration(shape: BoxShape.circle, color: AppColors.surfaceElevated),
                        ),
                ),
                Positioned(
                  right: -4,
                  bottom: -4,
                  child: Container(
                    padding: const EdgeInsets.all(1),
                    decoration: const BoxDecoration(shape: BoxShape.circle, color: AppColors.surfaceElevated),
                    child: ChessPieceGlyph(piece: piece, size: 18),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              p?.username ?? fallback,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.textWhite, fontSize: 13, fontWeight: FontWeight.w700),
            ),
          ],
        ),
      );
    }

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Ink(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            color: AppColors.surfaceCard,
            border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
          ),
          child: Column(
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(6),
                      color: const Color(0xFFFF4D6A).withValues(alpha: 0.16),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _LiveDot(),
                        SizedBox(width: 5),
                        Text(
                          'LIVE',
                          style: TextStyle(
                            color: Color(0xFFFF4D6A),
                            fontSize: 11,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 0.8,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '$timeLabel · langkah ke-${(g.ply ~/ 2) + 1}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
                    ),
                  ),
                  const _Pill(text: 'Tonton', color: AppColors.accentVioletLight, icon: Icons.visibility_rounded),
                ],
              ),
              const SizedBox(height: 14),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  side(g.white, 'Putih', 'K', g.turn == 'w'),
                  const Padding(
                    padding: EdgeInsets.only(top: 14),
                    child: Text(
                      'VS',
                      style: TextStyle(
                        color: AppColors.textMuted,
                        fontSize: 13,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1,
                      ),
                    ),
                  ),
                  side(g.black, 'Hitam', 'k', g.turn == 'b'),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({
    required this.title,
    required this.message,
    this.icon,
    this.glyph,
    this.actionLabel,
    this.onAction,
  });

  final String title;
  final String message;
  final IconData? icon;
  final String? glyph;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 26, 20, 22),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        color: AppColors.surfaceCard.withValues(alpha: 0.6),
        border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
      ),
      child: Column(
        children: [
          Container(
            width: 56,
            height: 56,
            alignment: Alignment.center,
            decoration: const BoxDecoration(shape: BoxShape.circle, color: AppColors.surfaceElevated),
            child: glyph != null
                ? ChessPieceGlyph(piece: glyph!, size: 34)
                : Icon(icon ?? Icons.info_outline_rounded, size: 26, color: AppColors.textSecondary),
          ),
          const SizedBox(height: 14),
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppColors.textWhite, fontSize: 15.5, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 6),
          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppColors.textSecondary, fontSize: 13, height: 1.45),
          ),
          if (actionLabel != null) ...[
            const SizedBox(height: 16),
            _ActionButton(label: actionLabel!, primary: true, onTap: onAction),
          ],
        ],
      ),
    );
  }
}

/// Tanda tangan pembuat fitur catur, di bagian paling bawah lobby.
class _ChessSignature extends StatelessWidget {
  const _ChessSignature();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(width: 36, height: 1, color: Colors.white.withValues(alpha: 0.12)),
        const SizedBox(height: 12),
        Text(
          '♞  Catur Zenime',
          style: TextStyle(
            color: AppColors.textSecondary.withValues(alpha: 0.85),
            fontSize: 12.5,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.4,
          ),
        ),
        const SizedBox(height: 4),
        const Text(
          'Dibuat oleh Dayynime · 27 Oktober 2026',
          style: TextStyle(
            color: AppColors.textMuted,
            fontSize: 11.5,
            fontStyle: FontStyle.italic,
          ),
        ),
      ],
    );
  }
}

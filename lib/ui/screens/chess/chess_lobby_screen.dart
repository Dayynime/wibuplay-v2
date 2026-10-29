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
      if (!_inGame && !(_rt?.isJoined ?? false)) _load(silent: true);
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

  Future<void> _load({bool silent = false}) async {
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

  @override
  Widget build(BuildContext context) {
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
          padding: EdgeInsets.fromLTRB(16, 8, 16, 32 + MediaQuery.paddingOf(context).bottom),
          children: [
            _hero(),
            const SizedBox(height: 14),
            _joinRow(),
            const SizedBox(height: 22),
            ..._sections(),
          ],
        ),
      ),
    );
  }

  Widget _hero() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF2A3142), AppColors.surfaceCard],
        ),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const ChessPieceGlyph(piece: 'N', size: 44),
              const SizedBox(width: 6),
              const ChessPieceGlyph(piece: 'k', size: 44),
              const SizedBox(width: 12),
              const Expanded(
                child: Text(
                  'Main catur 1 lawan 1 dengan temanmu. Langkah dicek server, jadi aman dari curang.',
                  style: TextStyle(color: AppColors.textSecondary, fontSize: 13, height: 1.4),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: _ActionButton(
                  icon: Icons.group_rounded,
                  label: 'Tantang teman',
                  primary: true,
                  onTap: _busy ? null : () => _newGame(friend: true),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _ActionButton(
                  icon: Icons.tag_rounded,
                  label: 'Buat room',
                  onTap: _busy ? null : () => _newGame(friend: false),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _joinRow() {
    return Row(
      children: [
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
              fontWeight: FontWeight.w700,
              letterSpacing: 3,
            ),
            decoration: InputDecoration(
              counterText: '',
              hintText: 'Kode room',
              hintStyle: const TextStyle(color: AppColors.textMuted, letterSpacing: 0, fontWeight: FontWeight.w500),
              filled: true,
              fillColor: AppColors.surfaceCard,
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: const BorderSide(color: AppColors.accentViolet),
              ),
            ),
          ),
        ),
        const SizedBox(width: 10),
        SizedBox(
          height: 50,
          child: _ActionButton(icon: Icons.login_rounded, label: 'Masuk', onTap: _busy ? null : _join),
        ),
      ],
    );
  }

  List<Widget> _sections() {
    final l = _lobby;
    if (l == null) {
      if (_error != null) {
        return [
          const SizedBox(height: 30),
          Center(child: Text(_error!, textAlign: TextAlign.center, style: const TextStyle(color: AppColors.textSecondary))),
          const SizedBox(height: 10),
          Center(child: TextButton(onPressed: _load, child: const Text('Coba lagi'))),
        ];
      }
      return const [
        SizedBox(height: 40),
        Center(child: CircularProgressIndicator(color: AppColors.accentViolet)),
      ];
    }
    if (l.isEmpty) {
      return const [
        SizedBox(height: 24),
        Text(
          'Belum ada permainan. Tantang teman, atau buat room lalu bagikan kodenya.',
          textAlign: TextAlign.center,
          style: TextStyle(color: AppColors.textSecondary, fontSize: 14, height: 1.4),
        ),
      ];
    }
    final uid = ref.read(authUserProvider).valueOrNull?.uid ?? '';
    final out = <Widget>[];

    void section(String title, List<ChessGame> games, Widget Function(ChessGame) row) {
      if (games.isEmpty) return;
      out.add(Padding(
        padding: const EdgeInsets.only(bottom: 8, left: 2),
        child: Text(title, style: const TextStyle(color: AppColors.textWhite, fontSize: 15, fontWeight: FontWeight.w800)),
      ));
      for (final g in games) {
        out.add(row(g));
        out.add(const SizedBox(height: 8));
      }
      out.add(const SizedBox(height: 14));
    }

    section('Tantangan masuk', l.incoming, (g) => _GameRow(
          game: g,
          player: g.creator,
          subtitle: '${_timeLabel(g)} · ${_colorLabel(g, uid)}',
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                tooltip: 'Tolak',
                onPressed: _busy ? null : () => _run(() => _repo.decline(g.id), openAfter: false),
                icon: const Icon(Icons.close_rounded, color: AppColors.textSecondary),
              ),
              _ActionButton(
                label: 'Terima',
                primary: true,
                compact: true,
                onTap: _busy ? null : () => _run(() => _repo.accept(g.id)),
              ),
            ],
          ),
          onTap: () => _open(g),
        ));

    section('Menunggu lawan', l.waiting, (g) => _GameRow(
          game: g,
          player: g.invitee,
          title: g.invitee == null ? 'Room ${g.code ?? ''}' : null,
          subtitle: g.invitee == null ? '${_timeLabel(g)} · bagikan kodenya' : '${_timeLabel(g)} · belum diterima',
          trailing: const Icon(Icons.chevron_right_rounded, color: AppColors.textMuted),
          onTap: () => _open(g),
        ));

    section('Sedang main', l.active, (g) {
      final opp = g.opponentOf(uid);
      return _GameRow(
        game: g,
        player: opp,
        subtitle: g.isMyTurn ? 'Giliranmu · ${_timeLabel(g)}' : 'Giliran lawan · ${_timeLabel(g)}',
        highlight: g.isMyTurn,
        trailing: const Icon(Icons.chevron_right_rounded, color: AppColors.textMuted),
        onTap: () => _open(g),
      );
    });

    section('Riwayat', l.recent, (g) {
      final opp = g.opponentOf(uid);
      final o = g.outcomeFor(g.myColor);
      final (label, color) = switch (o) {
        'win' => ('Menang', AppColors.successGreen),
        'loss' => ('Kalah', AppColors.accentVioletLight),
        'draw' => ('Remis', AppColors.textSecondary),
        _ => ('Batal', AppColors.textMuted),
      };
      return _GameRow(
        game: g,
        player: opp,
        subtitle: '${_timeLabel(g)} · ${chessEndText(g)}',
        trailing: Text(label, style: TextStyle(color: color, fontWeight: FontWeight.w800, fontSize: 13)),
        onTap: () => _open(g),
      );
    });

    return out;
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
    this.compact = false,
  });

  final String label;
  final IconData? icon;
  final VoidCallback? onTap;
  final bool primary;
  final bool compact;

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
            padding: EdgeInsets.symmetric(horizontal: compact ? 14 : 16, vertical: compact ? 9 : 13),
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
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: compact ? 13 : 14,
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

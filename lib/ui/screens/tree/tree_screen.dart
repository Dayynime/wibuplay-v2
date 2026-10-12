import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/models/account_models.dart' show formatZCoin;
import '../../../data/models/friend_models.dart';
import '../../../data/models/tree_models.dart';
import '../../../data/repository/tree_repository.dart';
import '../../../providers.dart';
import '../../app_routes.dart';
import '../../components/friend_avatar.dart';
import '../store/coin_screen.dart';
import '../store/premium_screen.dart';
import 'tree_scene.dart';

const Color _kGold = Color(0xFFFFC53D);
const Color _kLeaf = Color(0xFF22C55E);
const Color _kWater = Color(0xFF38BDF8);
const Color _kAmber = Color(0xFFF59E0B);
const Color _kGlass = Color(0x73101622);
const Color _kGlassBorder = Color(0x26FFFFFF);
const Color _kSheet = Color(0xFF121826);
const List<Shadow> _kTextShadow = [
  Shadow(color: Color(0x99000000), blurRadius: 6, offset: Offset(0, 1)),
];

/// Pohon ZCoin layar penuh: pemandangan game di belakang, HUD melayang di
/// atasnya. Buah tumbuh pakai jam server, tap buah buat panen jadi ZCoin.
class TreeScreen extends ConsumerStatefulWidget {
  const TreeScreen({super.key});

  @override
  ConsumerState<TreeScreen> createState() => _TreeScreenState();
}

class _TreeScreenState extends ConsumerState<TreeScreen> with SingleTickerProviderStateMixin {
  final TreeSceneController _scene = TreeSceneController();
  final GlobalKey _sceneKey = GlobalKey();
  final GlobalKey _coinKey = GlobalKey();
  late final TreeRepository _repo;
  late final AnimationController _lvlCtrl;

  TreeState? _tree;
  String? _error;
  bool _loading = true;
  bool _upgrading = false;
  int? _balance;
  int _shownLevel = 1;

  Duration _offset = Duration.zero;
  Timer? _clock;
  DateTime _lastAutoRefresh = DateTime.fromMillisecondsSinceEpoch(0);

  int _pending = 0;
  int _inFlight = 0;
  Timer? _debounce;

  String? _toastMsg;
  bool _toastWarn = false;
  int _toastId = 0;
  Timer? _toastTimer;

  String? get _uid => ref.read(authUserProvider).valueOrNull?.uid;

  @override
  void initState() {
    super.initState();
    _repo = ref.read(treeRepositoryProvider);
    _lvlCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 1900));
    _load();
    _clock = Timer.periodic(const Duration(seconds: 1), (_) => _onClock());
  }

  @override
  void dispose() {
    _clock?.cancel();
    _debounce?.cancel();
    _toastTimer?.cancel();
    if (_pending > 0) {
      final n = _pending;
      _pending = 0;
      unawaited(_repo.harvest(n).then((_) {}, onError: (_) {}));
    }
    _lvlCtrl.dispose();
    _scene.dispose();
    super.dispose();
  }

  DateTime get _serverNow => DateTime.now().toUtc().add(_offset);

  // ================================================================ data

  Future<void> _load({bool silent = false}) async {
    if (!silent) {
      setState(() {
        _loading = _tree == null;
        _error = null;
      });
    }
    try {
      final tree = await _repo.get();
      if (!mounted) return;
      _apply(tree);
    } on TreeException catch (e) {
      if (!mounted) return;
      if (_tree == null) {
        setState(() {
          _error = e.message;
          _loading = false;
        });
      } else if (!silent) {
        _toast(e.message, warn: true);
      }
    }
  }

  void _apply(TreeState tree) {
    setState(() {
      _tree = tree;
      _loading = false;
      _error = null;
      _offset = tree.serverNow.difference(DateTime.now().toUtc());
    });
    final visible = tree.fruits - _pending - _inFlight;
    _scene.sync(visible < 0 ? 0 : visible, tree.capacity, tree.level);
  }

  void _onClock() {
    final tree = _tree;
    if (!mounted || tree == null) return;
    final next = tree.nextFruitAt;
    if (next != null &&
        !_serverNow.isBefore(next) &&
        DateTime.now().difference(_lastAutoRefresh) > const Duration(seconds: 5) &&
        _inFlight == 0 &&
        _pending == 0) {
      _lastAutoRefresh = DateTime.now();
      _load(silent: true);
    }
    setState(() {});
  }

  void _updateCoinTarget() {
    if (!mounted) return;
    final sceneBox = _sceneKey.currentContext?.findRenderObject() as RenderBox?;
    final coinBox = _coinKey.currentContext?.findRenderObject() as RenderBox?;
    if (sceneBox == null || coinBox == null || !sceneBox.hasSize || !coinBox.hasSize) return;
    final global = coinBox.localToGlobal(coinBox.size.center(Offset.zero));
    _scene.coinTarget = sceneBox.globalToLocal(global);
  }

  void _toast(String msg, {bool warn = false}) {
    if (!mounted) return;
    _toastTimer?.cancel();
    setState(() {
      _toastMsg = msg;
      _toastWarn = warn;
      _toastId++;
    });
    _toastTimer = Timer(const Duration(milliseconds: 2800), () {
      if (mounted) setState(() => _toastMsg = null);
    });
  }

  // ================================================================ aksi

  int _picksAllowed(TreeState tree) {
    final room = tree.coinsLeftToday;
    if (room <= 0) return 0;
    final maxFruits = (room / tree.coinsPerFruit).ceil();
    final left = maxFruits - _pending - _inFlight;
    return left < 0 ? 0 : left;
  }

  void _capReached(TreeState tree) {
    HapticFeedback.heavyImpact();
    _toast('Batas ${tree.dailyCap} ZCoin hari ini sudah tercapai. Balik lagi besok ya!', warn: true);
  }

  void _onFruitTap(int slot) {
    final tree = _tree;
    if (tree == null || _upgrading) return;
    if (_picksAllowed(tree) <= 0) {
      _capReached(tree);
      return;
    }
    if (!_scene.pick(slot, '+${tree.coinsPerFruit}')) return;
    HapticFeedback.selectionClick();
    _pending++;
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 450), _flush);
  }

  void _harvestAll() {
    final tree = _tree;
    if (tree == null || _upgrading) return;
    final allowed = _picksAllowed(tree);
    if (allowed <= 0) {
      _capReached(tree);
      return;
    }
    final n = _scene.pickAll('+${tree.coinsPerFruit}', allowed);
    if (n == 0) return;
    HapticFeedback.mediumImpact();
    _pending += n;
    _debounce?.cancel();
    _flush();
  }

  Future<void> _flush() async {
    if (_pending == 0 || _inFlight > 0) return;
    final count = _pending;
    _pending = 0;
    _inFlight = count;
    try {
      final r = await _repo.harvest(count);
      if (!mounted) return;
      _inFlight = 0;
      _balance = r.balance;
      _apply(r.tree);
      final uid = _uid;
      if (uid != null) ref.invalidate(coinBalanceProvider(uid));
      if (r.harvested < count) {
        _toast('Cuma ${r.harvested} buah yang kepanen, batas ZCoin harian sudah penuh.', warn: true);
      }
    } on TreeException catch (e) {
      _inFlight = 0;
      if (!mounted) return;
      _toast(e.message, warn: true);
      await _load(silent: true);
    } finally {
      _inFlight = 0;
      if (mounted && _pending > 0) unawaited(_flush());
    }
  }

  Future<void> _upgrade() async {
    final tree = _tree;
    if (tree == null || tree.isMaxLevel || _upgrading) return;
    final uid = _uid;
    final balance = _balance ?? (uid == null ? null : ref.read(coinBalanceProvider(uid)).valueOrNull);
    final ok = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: _kSheet,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (_) => _UpgradeSheet(tree: tree, balance: balance),
    );
    if (ok != true || !mounted) return;
    _debounce?.cancel();
    await _flush();
    if (!mounted) return;
    setState(() => _upgrading = true);
    try {
      final r = await _repo.upgrade();
      if (!mounted) return;
      _balance = r.balance;
      _apply(r.tree);
      _scene.celebrate();
      HapticFeedback.heavyImpact();
      setState(() => _shownLevel = r.tree.level);
      _lvlCtrl.forward(from: 0);
      if (uid != null) ref.invalidate(coinBalanceProvider(uid));
    } on TreeException catch (e) {
      _toast(e.message, warn: true);
    } finally {
      if (mounted) setState(() => _upgrading = false);
    }
  }

  Future<void> _openWater() async {
    final uid = _uid;
    if (uid == null || _tree == null) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: _kSheet,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (_) => _WaterSheet(uid: uid),
    );
    if (mounted) await _load(silent: true);
  }

  void _openInfo() {
    final tree = _tree;
    if (tree == null) return;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: _kSheet,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (_) => _InfoSheet(tree: tree),
    );
  }

  void _openCoins() => Navigator.of(context).push<void>(fadeRoute(const CoinScreen()));

  // ================================================================ UI

  @override
  Widget build(BuildContext context) {
    final uid = ref.watch(authUserProvider).valueOrNull?.uid;
    final providerBalance = uid == null ? null : ref.watch(coinBalanceProvider(uid)).valueOrNull;
    final balance = _balance ?? providerBalance;
    final tree = _tree;
    final shown = tree == null ? 0 : tree.fruits - _pending - _inFlight;
    final fruitsShown = shown < 0 ? 0 : shown;

    WidgetsBinding.instance.addPostFrameCallback((_) => _updateCoinTarget());

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
        statusBarBrightness: Brightness.dark,
        systemNavigationBarColor: Color(0xFF173D22),
        systemNavigationBarIconBrightness: Brightness.light,
      ),
      child: Scaffold(
        backgroundColor: const Color(0xFF0E1424),
        body: Stack(
          children: [
            Positioned.fill(
              child: TreeScene(key: _sceneKey, controller: _scene, onFruitTap: _onFruitTap),
            ),
            const Positioned(
              top: 0,
              left: 0,
              right: 0,
              height: 200,
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Color(0x80000000), Color(0x00000000)],
                    ),
                  ),
                ),
              ),
            ),
            const Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              height: 230,
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.bottomCenter,
                      end: Alignment.topCenter,
                      colors: [Color(0x99000000), Color(0x00000000)],
                    ),
                  ),
                ),
              ),
            ),
            SafeArea(
              child: Column(
                children: [
                  _topBar(balance, tree),
                  const SizedBox(height: 12),
                  if (tree != null) _statusCard(tree, fruitsShown),
                  const SizedBox(height: 10),
                  _toastArea(),
                  const Spacer(),
                  if (tree != null) _hint(tree, fruitsShown),
                  const SizedBox(height: 14),
                  if (tree != null) _bottomBar(tree, fruitsShown),
                  const SizedBox(height: 14),
                ],
              ),
            ),
            if (uid == null)
              const _CenterCard(icon: Icons.lock_outline, text: 'Login dulu buat main Pohon ZCoin.')
            else if (_loading && tree == null)
              const Center(child: CircularProgressIndicator(color: _kLeaf))
            else if (tree == null)
              _CenterCard(
                icon: Icons.cloud_off_outlined,
                text: _error ?? 'Gagal memuat pohon',
                action: TextButton(onPressed: _load, child: const Text('Coba lagi')),
              ),
            Positioned.fill(child: _levelUpOverlay()),
          ],
        ),
      ),
    );
  }

  Widget _topBar(int? balance, TreeState? tree) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      child: Row(
        children: [
          _GlassIconButton(
            icon: Icons.arrow_back_rounded,
            onTap: () => Navigator.of(context).maybePop(),
          ),
          const SizedBox(width: 8),
          if (tree != null) _LevelBadge(tree: tree, onTap: _openInfo),
          const Spacer(),
          _CoinPill(value: balance, iconKey: _coinKey, onTap: _openCoins),
          const SizedBox(width: 8),
          _GlassIconButton(icon: Icons.info_outline_rounded, onTap: tree == null ? null : _openInfo),
        ],
      ),
    );
  }

  Widget _statusCard(TreeState tree, int fruitsShown) {
    final next = tree.nextFruitAt;
    var progress = 1.0;
    var timeText = 'Panen dulu!';
    if (next != null) {
      var remaining = next.difference(_serverNow);
      if (remaining.isNegative) remaining = Duration.zero;
      final total = tree.intervalSec <= 0 ? 1 : tree.intervalSec;
      progress = (1 - remaining.inSeconds / total).clamp(0.0, 1.0);
      timeText = remaining == Duration.zero ? 'Matang!' : _fmtCountdown(remaining);
    }
    final full = next == null;
    final ringColor = full ? _kAmber : _kLeaf;
    final cap = tree.dailyCap <= 0 ? 1 : tree.dailyCap;

    return _Glass(
      radius: 22,
      padding: const EdgeInsets.fromLTRB(10, 10, 16, 10),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 48,
            height: 48,
            child: Stack(
              alignment: Alignment.center,
              children: [
                SizedBox.expand(
                  child: CircularProgressIndicator(
                    value: progress,
                    strokeWidth: 4,
                    strokeCap: StrokeCap.round,
                    backgroundColor: const Color(0x33FFFFFF),
                    valueColor: AlwaysStoppedAnimation(ringColor),
                  ),
                ),
                Text(
                  '$fruitsShown/${tree.capacity}',
                  style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w800),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                full ? 'POHON PENUH' : 'BUAH BERIKUTNYA',
                style: TextStyle(
                  color: full ? _kAmber : const Color(0xB3FFFFFF),
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.1,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                timeText,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  fontFeatures: [FontFeature.tabularFigures()],
                  shadows: _kTextShadow,
                ),
              ),
            ],
          ),
          Container(
            width: 1,
            height: 34,
            margin: const EdgeInsets.symmetric(horizontal: 14),
            color: const Color(0x33FFFFFF),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'HARI INI',
                style: TextStyle(
                  color: Color(0xB3FFFFFF),
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.1,
                ),
              ),
              const SizedBox(height: 3),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Image.asset('assets/images/ic_zcoin_badge.png', width: 14, height: 14),
                  const SizedBox(width: 4),
                  Text(
                    '${tree.coinsToday}/${tree.dailyCap}',
                    style: const TextStyle(color: _kGold, fontSize: 14, fontWeight: FontWeight.w800),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              SizedBox(
                width: 64,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: (tree.coinsToday / cap).clamp(0.0, 1.0),
                    minHeight: 4,
                    backgroundColor: const Color(0x33FFFFFF),
                    valueColor: const AlwaysStoppedAnimation(_kGold),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _toastArea() {
    final msg = _toastMsg;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 260),
        transitionBuilder: (child, anim) => FadeTransition(
          opacity: anim,
          child: SlideTransition(
            position: Tween(begin: const Offset(0, -0.4), end: Offset.zero).animate(anim),
            child: child,
          ),
        ),
        child: msg == null
            ? const SizedBox.shrink(key: ValueKey('toast-none'))
            : _Glass(
                key: ValueKey(_toastId),
                radius: 16,
                color: _toastWarn ? const Color(0xCC3A2608) : const Color(0xCC0F2A1B),
                borderColor: _toastWarn ? const Color(0x66F59E0B) : const Color(0x6622C55E),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      _toastWarn ? Icons.info_outline_rounded : Icons.check_circle_rounded,
                      size: 18,
                      color: _toastWarn ? _kAmber : _kLeaf,
                    ),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        msg,
                        style: const TextStyle(color: Colors.white, fontSize: 13, height: 1.3),
                      ),
                    ),
                  ],
                ),
              ),
      ),
    );
  }

  Widget _hint(TreeState tree, int fruitsShown) {
    final String text;
    final IconData icon;
    Color color = Colors.white;
    if (tree.isFull) {
      text = 'Pohon penuh! Panen biar berbuah lagi';
      icon = Icons.warning_amber_rounded;
      color = _kAmber;
    } else if (fruitsShown > 0) {
      text = 'Tap buahnya buat panen';
      icon = Icons.touch_app_outlined;
    } else {
      text = 'Sabar, buahnya lagi tumbuh...';
      icon = Icons.hourglass_bottom_rounded;
    }
    return IgnorePointer(
      child: _Glass(
        radius: 20,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 15, color: color),
            const SizedBox(width: 6),
            Text(text, style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w700)),
          ],
        ),
      ),
    );
  }

  Widget _bottomBar(TreeState tree, int fruitsShown) {
    final waterLeft = (tree.waterGiveLimit - tree.waterGivenToday).clamp(0, tree.waterGiveLimit);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          _SideAction(
            icon: Icons.water_drop_rounded,
            label: 'Siram',
            color: _kWater,
            badge: '$waterLeft',
            onTap: _openWater,
          ),
          _HarvestButton(
            count: fruitsShown,
            enabled: fruitsShown > 0 && !_upgrading,
            onTap: _harvestAll,
          ),
          _SideAction(
            icon: Icons.keyboard_double_arrow_up_rounded,
            label: tree.isMaxLevel ? 'Max' : 'Upgrade',
            color: _kLeaf,
            badge: tree.isMaxLevel ? null : formatZCoin(tree.upgradeCost ?? 0),
            badgeCoin: true,
            busy: _upgrading,
            onTap: tree.isMaxLevel || _upgrading ? null : _upgrade,
          ),
        ],
      ),
    );
  }

  Widget _levelUpOverlay() {
    return IgnorePointer(
      child: AnimatedBuilder(
        animation: _lvlCtrl,
        builder: (context, _) {
          final v = _lvlCtrl.value;
          if (v <= 0 || v >= 1) return const SizedBox.shrink();
          final appear = Curves.elasticOut.transform((v / 0.35).clamp(0.0, 1.0));
          final fade = v < 0.78 ? 1.0 : (1 - (v - 0.78) / 0.22).clamp(0.0, 1.0);
          return Opacity(
            opacity: fade,
            child: Center(
              child: Transform.scale(
                scale: 0.4 + 0.6 * appear,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ShaderMask(
                      shaderCallback: (r) => const LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [Color(0xFFFFF3B0), Color(0xFFFFC53D), Color(0xFFE07B00)],
                      ).createShader(r),
                      child: const Text(
                        'LEVEL UP!',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 44,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 2,
                          shadows: [Shadow(color: Color(0xAA000000), blurRadius: 14, offset: Offset(0, 4))],
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    _Glass(
                      radius: 20,
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                      child: Text(
                        'Pohon sekarang Lv.$_shownLevel',
                        style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w700),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  static String _fmtCountdown(Duration d) {
    String two(int n) => n.toString().padLeft(2, '0');
    final h = d.inHours;
    final m = d.inMinutes % 60;
    final s = d.inSeconds % 60;
    return h > 0 ? '${two(h)}:${two(m)}:${two(s)}' : '${two(m)}:${two(s)}';
  }
}

// ==================================================================== HUD widgets

class _Glass extends StatelessWidget {
  const _Glass({
    super.key,
    required this.child,
    this.radius = 18,
    this.padding = const EdgeInsets.all(10),
    this.color = _kGlass,
    this.borderColor = _kGlassBorder,
  });

  final Widget child;
  final double radius;
  final EdgeInsetsGeometry padding;
  final Color color;
  final Color borderColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: borderColor),
      ),
      child: child,
    );
  }
}

class _GlassIconButton extends StatelessWidget {
  const _GlassIconButton({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: _kGlass,
      shape: const CircleBorder(side: BorderSide(color: _kGlassBorder)),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: SizedBox(
          width: 42,
          height: 42,
          child: Icon(icon, color: Colors.white, size: 22),
        ),
      ),
    );
  }
}

class _LevelBadge extends StatelessWidget {
  const _LevelBadge({required this.tree, required this.onTap});

  final TreeState tree;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final progress = tree.maxLevel <= 1 ? 1.0 : (tree.level - 1) / (tree.maxLevel - 1);
    return GestureDetector(
      onTap: onTap,
      child: _Glass(
        radius: 22,
        padding: const EdgeInsets.fromLTRB(4, 4, 12, 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0xFF4ADE80), Color(0xFF15803D)],
                ),
                boxShadow: [BoxShadow(color: Color(0x6622C55E), blurRadius: 10)],
              ),
              alignment: Alignment.center,
              child: Text(
                '${tree.level}',
                style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w900),
              ),
            ),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'POHON',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1,
                      ),
                    ),
                    if (tree.premium) ...[
                      const SizedBox(width: 5),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                        decoration: BoxDecoration(
                          color: const Color(0x33FFC53D),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.bolt_rounded, size: 11, color: _kGold),
                            Text(
                              formatTreeSpeed(tree.premiumSpeed),
                              style: const TextStyle(color: _kGold, fontSize: 9, fontWeight: FontWeight.w800),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 4),
                SizedBox(
                  width: 58,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(3),
                    child: LinearProgressIndicator(
                      value: progress,
                      minHeight: 4,
                      backgroundColor: const Color(0x33FFFFFF),
                      valueColor: const AlwaysStoppedAnimation(_kLeaf),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Saldo ZCoin: angka menghitung naik + ikon "mantul" tiap saldo bertambah.
class _CoinPill extends StatefulWidget {
  const _CoinPill({required this.value, required this.iconKey, required this.onTap});

  final int? value;
  final GlobalKey iconKey;
  final VoidCallback onTap;

  @override
  State<_CoinPill> createState() => _CoinPillState();
}

class _CoinPillState extends State<_CoinPill> with SingleTickerProviderStateMixin {
  late final AnimationController _bump =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 520));

  @override
  void didUpdateWidget(covariant _CoinPill old) {
    super.didUpdateWidget(old);
    final a = old.value;
    final b = widget.value;
    if (a != null && b != null && b > a) {
      // tunggu koin "sampai" dulu baru mantul
      Future<void>.delayed(const Duration(milliseconds: 350), () {
        if (mounted) _bump.forward(from: 0);
      });
    }
  }

  @override
  void dispose() {
    _bump.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final v = widget.value;
    return GestureDetector(
      onTap: widget.onTap,
      child: _Glass(
        radius: 22,
        padding: const EdgeInsets.fromLTRB(6, 5, 6, 5),
        borderColor: const Color(0x55FFC53D),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedBuilder(
              animation: _bump,
              builder: (context, child) {
                final k = _bump.value;
                final s = 1 + math.sin(k * math.pi) * 0.35;
                return Transform.scale(scale: s, child: child);
              },
              child: Image.asset(
                'assets/images/ic_zcoin_badge.png',
                key: widget.iconKey,
                width: 24,
                height: 24,
              ),
            ),
            const SizedBox(width: 6),
            if (v == null)
              const Text('-', style: TextStyle(color: _kGold, fontWeight: FontWeight.w800))
            else
              TweenAnimationBuilder<double>(
                tween: Tween(begin: v.toDouble(), end: v.toDouble()),
                duration: const Duration(milliseconds: 900),
                curve: Curves.easeOutCubic,
                builder: (context, x, _) => Text(
                  formatZCoin(x.round()),
                  style: const TextStyle(
                    color: _kGold,
                    fontWeight: FontWeight.w800,
                    fontSize: 14,
                    fontFeatures: [FontFeature.tabularFigures()],
                  ),
                ),
              ),
            const SizedBox(width: 6),
            Container(
              width: 20,
              height: 20,
              decoration: const BoxDecoration(color: _kGold, shape: BoxShape.circle),
              child: const Icon(Icons.add_rounded, size: 16, color: Color(0xFF3A2600)),
            ),
          ],
        ),
      ),
    );
  }
}

class _SideAction extends StatelessWidget {
  const _SideAction({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
    this.badge,
    this.badgeCoin = false,
    this.busy = false,
  });

  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback? onTap;
  final String? badge;
  final bool badgeCoin;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null || busy;
    return Opacity(
      opacity: enabled ? 1.0 : 0.5,
      child: _Pressable(
        onTap: onTap,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                Container(
                  width: 62,
                  height: 62,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [Color.lerp(color, Colors.white, 0.25)!, color, Color.lerp(color, Colors.black, 0.35)!],
                    ),
                    border: Border.all(color: const Color(0x55FFFFFF), width: 2),
                    boxShadow: [
                      BoxShadow(color: color.withValues(alpha: 0.45), blurRadius: 16, offset: const Offset(0, 4)),
                    ],
                  ),
                  child: busy
                      ? const Padding(
                          padding: EdgeInsets.all(18),
                          child: CircularProgressIndicator(strokeWidth: 2.6, color: Colors.white),
                        )
                      : Icon(icon, color: Colors.white, size: 28, shadows: _kTextShadow),
                ),
                if (badge != null)
                  Positioned(
                    top: -6,
                    right: -10,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: const Color(0xEE0B0E14),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: color.withValues(alpha: 0.7)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (badgeCoin) ...[
                            Image.asset('assets/images/ic_zcoin_badge.png', width: 11, height: 11),
                            const SizedBox(width: 3),
                          ],
                          Text(
                            badge!,
                            style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w800),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w800,
                shadows: _kTextShadow,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Tombol utama "PANEN": besar, emas, berdenyut saat ada buah.
class _HarvestButton extends StatefulWidget {
  const _HarvestButton({required this.count, required this.enabled, required this.onTap});

  final int count;
  final bool enabled;
  final VoidCallback onTap;

  @override
  State<_HarvestButton> createState() => _HarvestButtonState();
}

class _HarvestButtonState extends State<_HarvestButton> with SingleTickerProviderStateMixin {
  late final AnimationController _pulse =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1300));

  @override
  void initState() {
    super.initState();
    if (widget.enabled) _pulse.repeat();
  }

  @override
  void didUpdateWidget(covariant _HarvestButton old) {
    super.didUpdateWidget(old);
    if (widget.enabled && !_pulse.isAnimating) {
      _pulse.repeat();
    } else if (!widget.enabled && _pulse.isAnimating) {
      _pulse.stop();
      _pulse.value = 0;
    }
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final on = widget.enabled;
    final colors = on
        ? const [Color(0xFFFFE58A), Color(0xFFF7A614), Color(0xFFC2410C)]
        : const [Color(0xFF6B7280), Color(0xFF4B5563), Color(0xFF374151)];
    return _Pressable(
      onTap: on ? widget.onTap : null,
      child: SizedBox(
        width: 112,
        height: 112,
        child: Stack(
          clipBehavior: Clip.none,
          alignment: Alignment.center,
          children: [
            if (on)
              AnimatedBuilder(
                animation: _pulse,
                builder: (context, _) {
                  final k = _pulse.value;
                  return Container(
                    width: 92 + k * 26,
                    height: 92 + k * 26,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: _kGold.withValues(alpha: (1 - k) * 0.7),
                        width: 3,
                      ),
                    ),
                  );
                },
              ),
            Container(
              width: 92,
              height: 92,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  center: const Alignment(-0.3, -0.4),
                  radius: 0.95,
                  colors: colors,
                  stops: const [0, 0.55, 1],
                ),
                border: Border.all(color: const Color(0x99FFFFFF), width: 3),
                boxShadow: [
                  BoxShadow(
                    color: on ? const Color(0x88F7A614) : const Color(0x44000000),
                    blurRadius: 22,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.shopping_basket_rounded,
                    size: 34,
                    color: on ? const Color(0xFF5A2A00) : const Color(0xFFD1D5DB),
                  ),
                  Text(
                    'PANEN',
                    style: TextStyle(
                      color: on ? const Color(0xFF5A2A00) : const Color(0xFFD1D5DB),
                      fontSize: 13,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1.2,
                    ),
                  ),
                ],
              ),
            ),
            if (widget.count > 0)
              Positioned(
                top: 6,
                right: 6,
                child: Container(
                  constraints: const BoxConstraints(minWidth: 26),
                  height: 26,
                  padding: const EdgeInsets.symmetric(horizontal: 7),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: const Color(0xFFE4344A),
                    borderRadius: BorderRadius.circular(13),
                    border: Border.all(color: Colors.white, width: 2),
                  ),
                  child: Text(
                    '${widget.count}',
                    style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w900),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Efek tekan ala tombol game (mengecil sedikit saat ditekan).
class _Pressable extends StatefulWidget {
  const _Pressable({required this.child, required this.onTap});

  final Widget child;
  final VoidCallback? onTap;

  @override
  State<_Pressable> createState() => _PressableState();
}

class _PressableState extends State<_Pressable> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onTap != null;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: enabled ? (_) => setState(() => _down = true) : null,
      onTapCancel: enabled ? () => setState(() => _down = false) : null,
      onTapUp: enabled
          ? (_) {
              setState(() => _down = false);
              widget.onTap!();
            }
          : null,
      child: AnimatedScale(
        scale: _down ? 0.9 : 1,
        duration: const Duration(milliseconds: 110),
        curve: Curves.easeOut,
        child: widget.child,
      ),
    );
  }
}

class _CenterCard extends StatelessWidget {
  const _CenterCard({required this.icon, required this.text, this.action});

  final IconData icon;
  final String text;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: _Glass(
          radius: 22,
          color: const Color(0xCC101622),
          padding: const EdgeInsets.all(22),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: Colors.white70, size: 40),
              const SizedBox(height: 12),
              Text(
                text,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white, fontSize: 14),
              ),
              if (action != null) ...[const SizedBox(height: 8), action!],
            ],
          ),
        ),
      ),
    );
  }
}

// ==================================================================== sheets

class _SheetHandle extends StatelessWidget {
  const _SheetHandle();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        width: 40,
        height: 4,
        margin: const EdgeInsets.only(top: 10, bottom: 14),
        decoration: BoxDecoration(color: const Color(0x55FFFFFF), borderRadius: BorderRadius.circular(2)),
      ),
    );
  }
}

class _StatRow extends StatelessWidget {
  const _StatRow({required this.icon, required this.label, required this.value, this.next, this.color = _kLeaf});

  final IconData icon;
  final String label;
  final String value;
  final String? next;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF1A2232),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Text(label, style: const TextStyle(color: Color(0xFFB5BCC9), fontSize: 13)),
          ),
          Text(
            value,
            style: TextStyle(
              color: next == null ? Colors.white : const Color(0xFF8A93A3),
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
          ),
          if (next != null) ...[
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 6),
              child: Icon(Icons.arrow_forward_rounded, size: 14, color: Color(0xFF8A93A3)),
            ),
            Text(next!, style: TextStyle(color: color, fontSize: 13, fontWeight: FontWeight.w800)),
          ],
        ],
      ),
    );
  }
}

class _UpgradeSheet extends StatelessWidget {
  const _UpgradeSheet({required this.tree, required this.balance});

  final TreeState tree;
  final int? balance;

  @override
  Widget build(BuildContext context) {
    final next = tree.next;
    final cost = tree.upgradeCost ?? 0;
    final enough = balance == null || balance! >= cost;
    String mins(int sec) => formatTreeMinutes((sec / 60).round());

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const _SheetHandle(),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _LevelOrb(level: tree.level, dim: true),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 14),
                  child: Icon(Icons.double_arrow_rounded, color: _kLeaf, size: 28),
                ),
                _LevelOrb(level: tree.level + 1),
              ],
            ),
            const SizedBox(height: 10),
            const Text(
              'Upgrade Pohon',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 16),
            if (next != null) ...[
              _StatRow(
                icon: Icons.timer_outlined,
                label: '1 buah tiap',
                value: mins(tree.intervalSec),
                next: mins(next.intervalSec),
              ),
              _StatRow(
                icon: Icons.inventory_2_outlined,
                label: 'Maks buah',
                value: '${tree.capacity}',
                next: '${next.capacity}',
              ),
              _StatRow(
                icon: Icons.paid_outlined,
                label: 'ZCoin per buah',
                value: '${tree.coinsPerFruit}',
                next: '${next.coinsPerFruit}',
              ),
            ],
            const SizedBox(height: 8),
            if (!enough)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Text(
                  'ZCoin kamu ${formatZCoin(balance ?? 0)}, belum cukup.',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Color(0xFFFF6B6B), fontSize: 13),
                ),
              ),
            _BigButton(
              colors: const [Color(0xFF4ADE80), Color(0xFF16A34A)],
              onTap: enough ? () => Navigator.of(context).pop(true) : null,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text(
                    'UPGRADE',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w900,
                      fontSize: 15,
                      letterSpacing: 1,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Image.asset('assets/images/ic_zcoin_badge.png', width: 18, height: 18),
                  const SizedBox(width: 4),
                  Text(
                    formatZCoin(cost),
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 15),
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

class _LevelOrb extends StatelessWidget {
  const _LevelOrb({required this.level, this.dim = false});

  final int level;
  final bool dim;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: dim ? 56 : 70,
      height: dim ? 56 : 70,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: dim
              ? const [Color(0xFF3B4556), Color(0xFF242C3A)]
              : const [Color(0xFF4ADE80), Color(0xFF15803D)],
        ),
        boxShadow: dim ? null : const [BoxShadow(color: Color(0x6622C55E), blurRadius: 18)],
      ),
      alignment: Alignment.center,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('LV', style: TextStyle(color: Colors.white70, fontSize: 10, fontWeight: FontWeight.w800)),
          Text(
            '$level',
            style: TextStyle(color: Colors.white, fontSize: dim ? 20 : 26, fontWeight: FontWeight.w900),
          ),
        ],
      ),
    );
  }
}

class _BigButton extends StatelessWidget {
  const _BigButton({required this.colors, required this.onTap, required this.child});

  final List<Color> colors;
  final VoidCallback? onTap;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: onTap == null ? 0.45 : 1.0,
      child: _Pressable(
        onTap: onTap,
        child: Container(
          height: 54,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            gradient: LinearGradient(colors: colors),
            boxShadow: [BoxShadow(color: colors.last.withValues(alpha: 0.4), blurRadius: 14, offset: const Offset(0, 4))],
          ),
          child: child,
        ),
      ),
    );
  }
}

class _InfoSheet extends StatelessWidget {
  const _InfoSheet({required this.tree});

  final TreeState tree;

  @override
  Widget build(BuildContext context) {
    final speed = formatTreeSpeed(tree.premiumSpeed);
    return SafeArea(
      top: false,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.8),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const _SheetHandle(),
              const Text(
                'Info Pohon',
                style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 4),
              Text(
                'Total ZCoin dari pohon: ${formatZCoin(tree.totalCoins)}',
                style: const TextStyle(color: Color(0xFFB5BCC9), fontSize: 13),
              ),
              const SizedBox(height: 14),
              _StatRow(icon: Icons.park_rounded, label: 'Level', value: '${tree.level} / ${tree.maxLevel}'),
              _StatRow(
                icon: Icons.timer_outlined,
                label: '1 buah tiap',
                value: formatTreeMinutes((tree.intervalSec / 60).round()),
              ),
              _StatRow(icon: Icons.inventory_2_outlined, label: 'Maks buah di pohon', value: '${tree.capacity}'),
              _StatRow(
                icon: Icons.paid_outlined,
                label: 'ZCoin per buah',
                value: '+${tree.coinsPerFruit}',
                color: _kGold,
              ),
              _StatRow(
                icon: Icons.today_rounded,
                label: 'Batas ZCoin per hari',
                value: '${tree.coinsToday}/${tree.dailyCap}',
                color: _kGold,
              ),
              _StatRow(
                icon: Icons.water_drop_rounded,
                label: 'Siram teman',
                value: '+${tree.waterBonusMin} mnt • ${tree.waterGiveLimit}x/hari',
                color: _kWater,
              ),
              _StatRow(
                icon: Icons.bolt_rounded,
                label: 'Bonus Premium',
                value: tree.premium ? 'Aktif $speed' : '$speed lebih cepat',
                color: _kGold,
              ),
              const SizedBox(height: 8),
              const Text(
                'Buah tumbuh sendiri walau app ditutup. Kalau pohon penuh, pertumbuhan '
                'berhenti sampai dipanen. Batas ZCoin harian reset tiap tengah malam WIB.',
                style: TextStyle(color: Color(0xFF8A93A3), fontSize: 12, height: 1.45),
              ),
              if (!tree.premium) ...[
                const SizedBox(height: 14),
                _BigButton(
                  colors: const [Color(0xFFFFD54F), Color(0xFFF59E0B)],
                  onTap: () {
                    Navigator.of(context).pop();
                    Navigator.of(context).push<void>(fadeRoute(const PremiumScreen()));
                  },
                  child: Text(
                    'Tumbuh $speed lebih cepat dengan Premium',
                    style: const TextStyle(color: Color(0xFF3A2600), fontWeight: FontWeight.w800),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Bottom sheet daftar teman + tombol siram.
class _WaterSheet extends ConsumerStatefulWidget {
  const _WaterSheet({required this.uid});

  final String uid;

  @override
  ConsumerState<_WaterSheet> createState() => _WaterSheetState();
}

class _WaterSheetState extends ConsumerState<_WaterSheet> {
  List<FriendDisplay>? _friends;
  TreeWaterStatus? _status;
  String? _error;
  final Set<String> _busy = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final results = await Future.wait<Object>([
        ref.read(friendRepositoryProvider).getLists(widget.uid),
        ref.read(treeRepositoryProvider).waterStatus(),
      ]);
      if (!mounted) return;
      setState(() {
        _friends = (results[0] as FriendLists).friends;
        _status = results[1] as TreeWaterStatus;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e is TreeException ? e.message : 'Gagal memuat daftar teman');
    }
  }

  Future<void> _water(FriendDisplay f) async {
    final status = _status;
    if (status == null || _busy.contains(f.firebaseUid)) return;
    setState(() => _busy.add(f.firebaseUid));
    try {
      final bonus = await ref.read(treeRepositoryProvider).water(f.firebaseUid);
      if (!mounted) return;
      HapticFeedback.lightImpact();
      setState(() {
        _status = TreeWaterStatus(
          watered: {...status.watered, f.firebaseUid},
          givenToday: status.givenToday + 1,
          giveLimit: status.giveLimit,
          bonusMin: status.bonusMin,
        );
      });
      _snack('Pohon ${f.username} disiram! Buahnya tumbuh $bonus menit lebih cepat');
    } on TreeException catch (e) {
      _snack(e.message);
    } finally {
      if (mounted) setState(() => _busy.remove(f.firebaseUid));
    }
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(msg), behavior: SnackBarBehavior.floating));
  }

  @override
  Widget build(BuildContext context) {
    final status = _status;
    final friends = _friends;
    final maxH = MediaQuery.sizeOf(context).height * 0.75;

    Widget body;
    if (_error != null) {
      body = Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_error!, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white70)),
            TextButton(onPressed: _load, child: const Text('Coba lagi')),
          ],
        ),
      );
    } else if (friends == null || status == null) {
      body = const Padding(
        padding: EdgeInsets.all(40),
        child: Center(child: CircularProgressIndicator(color: _kWater)),
      );
    } else if (friends.isEmpty) {
      body = const Padding(
        padding: EdgeInsets.all(28),
        child: Text(
          'Belum punya teman. Tambah teman dulu biar bisa saling siram pohon.',
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.white70),
        ),
      );
    } else {
      body = ListView.separated(
        shrinkWrap: true,
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
        itemCount: friends.length,
        separatorBuilder: (_, __) => const SizedBox(height: 8),
        itemBuilder: (context, i) {
          final f = friends[i];
          final done = status.watered.contains(f.firebaseUid);
          final busy = _busy.contains(f.firebaseUid);
          final canWater = !done && status.left > 0;
          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: const Color(0xFF1A2232),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              children: [
                FriendAvatar(url: f.avatarUrl, seed: f.firebaseUid, label: f.username, size: 40),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    f.username,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                  ),
                ),
                if (done)
                  const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.check_circle_rounded, color: _kLeaf, size: 18),
                      SizedBox(width: 4),
                      Text('Disiram', style: TextStyle(color: _kLeaf, fontSize: 12)),
                    ],
                  )
                else
                  FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF0EA5E9),
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      visualDensity: VisualDensity.compact,
                    ),
                    onPressed: canWater && !busy ? () => _water(f) : null,
                    icon: busy
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : const Icon(Icons.water_drop_rounded, size: 16),
                    label: const Text('Siram'),
                  ),
              ],
            ),
          );
        },
      );
    }

    return SafeArea(
      top: false,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxH),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const _SheetHandle(),
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 0, 16, 4),
              child: Text(
                'Siram pohon teman',
                style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w800),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
              child: Text(
                status == null
                    ? 'Tiap siraman bikin buah temanmu tumbuh lebih cepat.'
                    : 'Sisa jatah hari ini ${status.left}/${status.giveLimit} • '
                        'tiap siraman +${status.bonusMin} mnt buat pohon temanmu',
                style: const TextStyle(color: Color(0xFFB5BCC9), fontSize: 13),
              ),
            ),
            Flexible(child: body),
          ],
        ),
      ),
    );
  }
}

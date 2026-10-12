import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lottie/lottie.dart';

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

  // ---------- dekorasi & toko
  TreeLook _look = const TreeLook();
  bool _identityLoaded = false;
  ShopData? _shop;
  bool _shopOpen = false;
  bool _shopBusy = false;
  String? _shopError;
  String _shopTab = TreeSlot.tree;
  String? _selectedId;

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
    final look = tree.look;
    if (look != null) _look = look;
    setState(() {
      _tree = tree;
      _loading = false;
      _error = null;
      _offset = tree.serverNow.difference(DateTime.now().toUtc());
    });
    final visible = tree.fruits - _pending - _inFlight;
    _scene.sync(visible < 0 ? 0 : visible, tree.capacity, tree.level);
    _scene.setLook(_sceneLook());
    if (!_identityLoaded) {
      _identityLoaded = true;
      _loadIdentity();
    }
  }

  /// Tag clan (bendera) & username (papan nama) buat dekorasi.
  Future<void> _loadIdentity() async {
    final uid = _uid;
    if (uid == null) return;
    final chat = ref.read(chatRepositoryProvider);
    try {
      final tags = await chat.getClanTagsForUids([uid]);
      _scene.clanTag = tags[uid];
    } catch (_) {}
    try {
      final prof = await chat.getProfile(uid);
      _scene.username = prof?.username;
    } catch (_) {}
  }

  // ================================================================ toko

  ShopItem? _itemById(String? id) {
    final shop = _shop;
    if (id == null || shop == null) return null;
    for (final it in shop.items) {
      if (it.id == id) return it;
    }
    return null;
  }

  /// Look yang digambar: dekorasi terpasang + item yang sedang di-preview.
  TreeLook _sceneLook() {
    final item = _shopOpen ? _itemById(_selectedId) : null;
    if (item == null) return _look;
    return _look.withItem(item.id, item.slot, asset: item.asset);
  }

  Future<void> _openShop() async {
    HapticFeedback.selectionClick();
    setState(() {
      _shopOpen = true;
      _selectedId = null;
      _shopError = null;
    });
    try {
      final data = await _repo.shop();
      if (!mounted) return;
      setState(() {
        _shop = data;
        _look = data.look;
      });
      _scene.setLook(_sceneLook());
    } on TreeException catch (e) {
      if (mounted) setState(() => _shopError = e.message);
    }
  }

  void _closeShop() {
    setState(() {
      _shopOpen = false;
      _selectedId = null;
    });
    _scene.setLook(_sceneLook());
  }

  void _selectItem(ShopItem item) {
    HapticFeedback.selectionClick();
    setState(() => _selectedId = _selectedId == item.id ? null : item.id);
    _scene.setLook(_sceneLook());
  }

  Future<void> _buy(ShopItem item) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _kSheet,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        title: Text('Beli ${item.name}?', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
        content: Row(
          children: [
            Image.asset('assets/images/ic_zcoin_badge.png', width: 20, height: 20),
            const SizedBox(width: 6),
            Text(
              '${formatZCoin(item.price)} ZCoin',
              style: const TextStyle(color: _kGold, fontWeight: FontWeight.w800, fontSize: 16),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Batal', style: TextStyle(color: Color(0xFFB5BCC9))),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: const Color(0xFFF59E0B)),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Beli', style: TextStyle(color: Color(0xFF3A2600), fontWeight: FontWeight.w800)),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _shopBusy = true);
    try {
      final bal = await _repo.buy(item.id);
      final look = await _repo.equip(item.id, on: true);
      if (!mounted) return;
      final shop = _shop;
      setState(() {
        _balance = bal;
        _look = look;
        if (shop != null) {
          _shop = ShopData(items: shop.items, owned: {...shop.owned, item.id}, look: look);
        }
      });
      _scene.setLook(_sceneLook());
      _scene.celebrate();
      HapticFeedback.heavyImpact();
      final uid = _uid;
      if (uid != null) ref.invalidate(coinBalanceProvider(uid));
      _toast('${item.name} dibeli dan langsung dipasang!');
    } on TreeException catch (e) {
      _toast(e.message, warn: true);
    } finally {
      if (mounted) setState(() => _shopBusy = false);
    }
  }

  Future<void> _equip(ShopItem item, {required bool on}) async {
    setState(() => _shopBusy = true);
    try {
      final look = await _repo.equip(item.id, on: on);
      if (!mounted) return;
      final shop = _shop;
      setState(() {
        _look = look;
        if (shop != null) _shop = ShopData(items: shop.items, owned: shop.owned, look: look);
        if (!on) _selectedId = null;
      });
      _scene.setLook(_sceneLook());
      HapticFeedback.lightImpact();
      _toast(on ? '${item.name} dipasang' : '${item.name} dilepas');
    } on TreeException catch (e) {
      _toast(e.message, warn: true);
    } finally {
      if (mounted) setState(() => _shopBusy = false);
    }
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
                  if (tree != null && !_shopOpen) ...[
                    _statusCard(tree, fruitsShown),
                    const SizedBox(height: 8),
                    _hint(tree, fruitsShown),
                    const SizedBox(height: 8),
                  ],
                  _toastArea(),
                  const Spacer(),
                  if (tree != null && !_shopOpen) ...[
                    Align(
                      alignment: Alignment.centerRight,
                      child: Padding(
                        padding: const EdgeInsets.only(right: 16),
                        child: _ShopButton(onTap: _openShop),
                      ),
                    ),
                    const SizedBox(height: 10),
                    _bottomBar(tree, fruitsShown),
                    const SizedBox(height: 14),
                  ],
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
            if (_shopOpen && tree != null)
              Positioned(left: 0, right: 0, bottom: 0, child: _shopPanel(tree)),
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

  Widget _shopPanel(TreeState tree) {
    final shop = _shop;
    final bottomInset = MediaQuery.paddingOf(context).bottom;
    final items = shop == null ? const <ShopItem>[] : shop.items.where((e) => e.slot == _shopTab).toList();
    final selected = _itemById(_selectedId);

    return Container(
      padding: EdgeInsets.fromLTRB(0, 6, 0, 12 + bottomInset),
      decoration: const BoxDecoration(
        color: Color(0xF2101622),
        borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
        border: Border(top: BorderSide(color: Color(0x33FFC53D))),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 4, 6, 0),
            child: Row(
              children: [
                const Icon(Icons.storefront_rounded, color: _kGold),
                const SizedBox(width: 8),
                const Text(
                  'Toko Dekorasi',
                  style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w800),
                ),
                const Spacer(),
                IconButton(
                  onPressed: _closeShop,
                  icon: const Icon(Icons.close_rounded, color: Colors.white70),
                ),
              ],
            ),
          ),
          SizedBox(
            height: 36,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 14),
              children: [
                for (final (slot, label) in _kShopTabs)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: _TabChip(
                      label: label,
                      active: _shopTab == slot,
                      onTap: () {
                        HapticFeedback.selectionClick();
                        setState(() {
                          _shopTab = slot;
                          _selectedId = null;
                        });
                        _scene.setLook(_sceneLook());
                      },
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 156,
            child: shop == null
                ? (_shopError != null
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 24),
                              child: Text(
                                _shopError!,
                                textAlign: TextAlign.center,
                                style: const TextStyle(color: Colors.white70, fontSize: 13),
                              ),
                            ),
                            TextButton(onPressed: _openShop, child: const Text('Coba lagi')),
                          ],
                        ),
                      )
                    : const Center(child: CircularProgressIndicator(color: _kGold)))
                : items.isEmpty
                    ? const Center(
                        child: Text('Belum ada item di sini', style: TextStyle(color: Colors.white54)),
                      )
                    : ListView.separated(
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.symmetric(horizontal: 14),
                        itemCount: items.length,
                        separatorBuilder: (_, __) => const SizedBox(width: 10),
                        itemBuilder: (context, i) {
                          final it = items[i];
                          return _ShopCard(
                            item: it,
                            owned: shop.owned.contains(it.id),
                            equipped: _look.isEquipped(it.id, it.slot),
                            selected: _selectedId == it.id,
                            onTap: () => _selectItem(it),
                          );
                        },
                      ),
          ),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: _shopAction(tree, shop, selected),
          ),
        ],
      ),
    );
  }

  Widget _shopAction(TreeState tree, ShopData? shop, ShopItem? item) {
    if (shop == null) return const SizedBox(height: 54);
    if (item == null) {
      return const SizedBox(
        height: 54,
        child: Center(
          child: Text(
            'Tap item buat lihat preview di pohonmu',
            style: TextStyle(color: Color(0xFFB5BCC9), fontSize: 13),
          ),
        ),
      );
    }
    final owned = shop.owned.contains(item.id);
    final equipped = _look.isEquipped(item.id, item.slot);
    final until = item.availableUntil;
    final sub = <String>[
      if (item.description.isNotEmpty) item.description,
      if (until != null) 'Terbatas s/d ${_fmtDate(until)}',
    ].join(' • ');

    Widget button;
    if (owned) {
      button = _BigButton(
        colors: equipped
            ? const [Color(0xFF4B5563), Color(0xFF374151)]
            : const [Color(0xFF4ADE80), Color(0xFF16A34A)],
        onTap: _shopBusy ? null : () => _equip(item, on: !equipped),
        child: Text(
          equipped ? 'LEPAS' : 'PAKAI',
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, letterSpacing: 1),
        ),
      );
    } else if (item.premiumOnly && !tree.premium) {
      button = _BigButton(
        colors: const [Color(0xFFFFD54F), Color(0xFFF59E0B)],
        onTap: () => Navigator.of(context).push<void>(fadeRoute(const PremiumScreen())),
        child: const Text(
          'KHUSUS PREMIUM',
          style: TextStyle(color: Color(0xFF3A2600), fontWeight: FontWeight.w900, letterSpacing: 1),
        ),
      );
    } else {
      button = _BigButton(
        colors: const [Color(0xFFFFD54F), Color(0xFFF59E0B)],
        onTap: _shopBusy ? null : () => _buy(item),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text(
              'BELI',
              style: TextStyle(color: Color(0xFF3A2600), fontWeight: FontWeight.w900, letterSpacing: 1),
            ),
            const SizedBox(width: 10),
            Image.asset('assets/images/ic_zcoin_badge.png', width: 18, height: 18),
            const SizedBox(width: 4),
            Text(
              formatZCoin(item.price),
              style: const TextStyle(color: Color(0xFF3A2600), fontWeight: FontWeight.w900),
            ),
          ],
        ),
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (sub.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              sub,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Color(0xFFB5BCC9), fontSize: 12),
            ),
          ),
        button,
      ],
    );
  }

  static String _fmtDate(DateTime d) {
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'Mei', 'Jun', 'Jul', 'Agu', 'Sep', 'Okt', 'Nov', 'Des'];
    final w = d.toUtc().add(const Duration(hours: 7)).subtract(const Duration(minutes: 1));
    return '${w.day} ${months[w.month - 1]}';
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

  Future<void> _visit(FriendDisplay f) async {
    await Navigator.of(context).push<void>(
      fadeRoute(TreeVisitScreen(friendUid: f.firebaseUid, username: f.username, avatarUrl: f.avatarUrl)),
    );
    if (mounted) await _load();
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
          return Material(
            color: const Color(0xFF1A2232),
            borderRadius: BorderRadius.circular(16),
            child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: () => _visit(f),
            child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              children: [
                FriendAvatar(url: f.avatarUrl, seed: f.firebaseUid, label: f.username, size: 40),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        f.username,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                      ),
                      const Text(
                        'Tap buat lihat pohonnya',
                        style: TextStyle(color: Color(0xFF8A93A3), fontSize: 11),
                      ),
                    ],
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
            ),
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


// ==================================================================== toko: widgets

const List<(String, String)> _kShopTabs = [
  (TreeSlot.tree, 'Pohon'),
  (TreeSlot.fruit, 'Buah'),
  (TreeSlot.treeDeco, 'Hiasan'),
  (TreeSlot.ground, 'Tanah'),
  (TreeSlot.pet, 'Pet'),
  (TreeSlot.effect, 'Efek'),
];

Color _rarityColor(String r) => switch (r) {
      'rare' => const Color(0xFF3B82F6),
      'epic' => const Color(0xFFA855F7),
      'legendary' => const Color(0xFFF59E0B),
      _ => const Color(0xFF9CA3AF),
    };

String _rarityLabel(String r) => switch (r) {
      'rare' => 'Langka',
      'epic' => 'Epik',
      'legendary' => 'Legendaris',
      _ => 'Biasa',
    };

(IconData, Color) _itemIcon(String id) => switch (id) {
      'tree_sakura' => (Icons.local_florist_rounded, const Color(0xFFF9A8D4)),
      'tree_autumn' => (Icons.eco_rounded, const Color(0xFFFB923C)),
      'tree_snow' => (Icons.ac_unit_rounded, const Color(0xFFBAE6FD)),
      'tree_neon' => (Icons.bolt_rounded, const Color(0xFF67E8F9)),
      'tree_gold' => (Icons.workspace_premium_rounded, const Color(0xFFFFD54F)),
      'fruit_apple' => (Icons.circle, const Color(0xFFEF4444)),
      'fruit_peach' => (Icons.circle, const Color(0xFFFDA4AF)),
      'fruit_star' => (Icons.star_rounded, const Color(0xFFFFD54F)),
      'fruit_candy' => (Icons.bubble_chart_rounded, const Color(0xFFF472B6)),
      'fruit_lantern' => (Icons.emoji_objects_rounded, const Color(0xFFF87171)),
      'fruit_crystal' => (Icons.diamond_rounded, const Color(0xFF67E8F9)),
      'fruit_pumpkin' => (Icons.circle, const Color(0xFFF97316)),
      'deco_lights' => (Icons.lightbulb_rounded, const Color(0xFFFDE68A)),
      'deco_nest' => (Icons.egg_rounded, const Color(0xFFBFE3F2)),
      'deco_lanterns' => (Icons.emoji_objects_rounded, const Color(0xFFEF4444)),
      'deco_swing' => (Icons.chair_rounded, const Color(0xFFD6B37A)),
      'deco_clanflag' => (Icons.flag_rounded, const Color(0xFFE4344A)),
      'deco_treehouse' => (Icons.cottage_rounded, const Color(0xFFD97706)),
      'ground_fence' => (Icons.fence_rounded, const Color(0xFFD6A06A)),
      'ground_bench' => (Icons.chair_rounded, const Color(0xFFB07A44)),
      'ground_sign' => (Icons.signpost_rounded, const Color(0xFFD6A06A)),
      'ground_stonelantern' => (Icons.wb_incandescent_rounded, const Color(0xFFD1D5DB)),
      'ground_mushroom' => (Icons.grass_rounded, const Color(0xFFC084FC)),
      'ground_torii' => (Icons.temple_buddhist_rounded, const Color(0xFFEF4444)),
      'ground_pond' => (Icons.water_rounded, const Color(0xFF38BDF8)),
      'ground_pumpkin' => (Icons.sentiment_very_satisfied_rounded, const Color(0xFFF97316)),
      'pet_bird' => (Icons.flutter_dash_rounded, const Color(0xFF60A5FA)),
      'pet_slime' => (Icons.bubble_chart_rounded, const Color(0xFF34D399)),
      'pet_cat' => (Icons.pets_rounded, const Color(0xFFF4A261)),
      'pet_kitsune' => (Icons.whatshot_rounded, const Color(0xFFF97316)),
      'fx_goldflies' => (Icons.auto_awesome_rounded, const Color(0xFFFFC53D)),
      'fx_petals' => (Icons.filter_vintage_rounded, const Color(0xFFF9A8D4)),
      'fx_fuji' => (Icons.landscape_rounded, const Color(0xFF93C5FD)),
      'fx_aurora' => (Icons.waves_rounded, const Color(0xFF34D399)),
      'fx_fireworks' => (Icons.celebration_rounded, const Color(0xFFF472B6)),
      'fx_bats' => (Icons.nights_stay_rounded, const Color(0xFFA78BFA)),
      _ => (Icons.auto_awesome_rounded, const Color(0xFFFFFFFF)),
    };

class _ShopButton extends StatelessWidget {
  const _ShopButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return _Pressable(
      onTap: onTap,
      child: _Glass(
        radius: 18,
        borderColor: const Color(0x66FFC53D),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.storefront_rounded, color: _kGold, size: 20),
            SizedBox(width: 6),
            Text(
              'Toko',
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }
}

class _TabChip extends StatelessWidget {
  const _TabChip({required this.label, required this.active, required this.onTap});

  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 16),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: active ? _kGold : const Color(0xFF1A2232),
          borderRadius: BorderRadius.circular(18),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: active ? const Color(0xFF3A2600) : Colors.white70,
            fontWeight: FontWeight.w800,
            fontSize: 13,
          ),
        ),
      ),
    );
  }
}

class _ShopCard extends StatelessWidget {
  const _ShopCard({
    required this.item,
    required this.owned,
    required this.equipped,
    required this.selected,
    required this.onTap,
  });

  final ShopItem item;
  final bool owned;
  final bool equipped;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final rc = _rarityColor(item.rarity);
    final (icon, ic) = _itemIcon(item.id);
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        width: 112,
        padding: const EdgeInsets.fromLTRB(8, 10, 8, 8),
        decoration: BoxDecoration(
          color: const Color(0xFF1A2232),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: selected ? rc : const Color(0x1AFFFFFF), width: selected ? 2 : 1),
          boxShadow: selected ? [BoxShadow(color: rc.withValues(alpha: 0.35), blurRadius: 14)] : null,
        ),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Column(
              children: [
                Container(
                  width: 54,
                  height: 54,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(colors: [rc.withValues(alpha: 0.45), rc.withValues(alpha: 0.08)]),
                    border: Border.all(color: rc.withValues(alpha: 0.6)),
                  ),
                  child: item.asset == null
                      ? Icon(icon, color: ic, size: 28)
                      : ClipOval(
                          child: Lottie.network(
                            item.asset!.url,
                            fit: BoxFit.contain,
                            errorBuilder: (context, error, stack) => Icon(icon, color: ic, size: 28),
                          ),
                        ),
                ),
                const SizedBox(height: 6),
                Text(
                  item.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 12),
                ),
                Text(
                  _rarityLabel(item.rarity),
                  style: TextStyle(color: rc, fontSize: 10, fontWeight: FontWeight.w700),
                ),
                const Spacer(),
                if (equipped)
                  const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.check_circle_rounded, size: 14, color: _kLeaf),
                      SizedBox(width: 3),
                      Text('Dipakai', style: TextStyle(color: _kLeaf, fontSize: 11, fontWeight: FontWeight.w800)),
                    ],
                  )
                else if (owned)
                  const Text('Dimiliki', style: TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.w700))
                else
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Image.asset('assets/images/ic_zcoin_badge.png', width: 13, height: 13),
                      const SizedBox(width: 3),
                      Text(
                        formatZCoin(item.price),
                        style: const TextStyle(color: _kGold, fontSize: 12, fontWeight: FontWeight.w800),
                      ),
                    ],
                  ),
              ],
            ),
            if (item.premiumOnly)
              const Positioned(
                top: -4,
                left: -2,
                child: Icon(Icons.workspace_premium_rounded, size: 18, color: _kGold),
              ),
            if (item.limited)
              Positioned(
                top: -4,
                right: -2,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                  decoration: BoxDecoration(
                    color: const Color(0xFFEA580C),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Text(
                    'Terbatas',
                    style: TextStyle(color: Colors.white, fontSize: 8, fontWeight: FontWeight.w800),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ==================================================================== kunjungi pohon teman

/// Lihat pohon teman (lengkap dengan dekorasinya) dan siram dari sini.
class TreeVisitScreen extends ConsumerStatefulWidget {
  const TreeVisitScreen({super.key, required this.friendUid, required this.username, this.avatarUrl});

  final String friendUid;
  final String username;
  final String? avatarUrl;

  @override
  ConsumerState<TreeVisitScreen> createState() => _TreeVisitScreenState();
}

class _TreeVisitScreenState extends ConsumerState<TreeVisitScreen> {
  final TreeSceneController _scene = TreeSceneController();
  late final TreeRepository _repo;
  TreeVisit? _v;
  String? _error;
  bool _watering = false;
  String? _toastMsg;
  Timer? _toastTimer;

  @override
  void initState() {
    super.initState();
    _repo = ref.read(treeRepositoryProvider);
    _scene.username = widget.username;
    _load();
    ref.read(chatRepositoryProvider).getClanTagsForUids([widget.friendUid]).then(
      (tags) => _scene.clanTag = tags[widget.friendUid],
      onError: (_) {},
    );
  }

  @override
  void dispose() {
    _toastTimer?.cancel();
    _scene.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final v = await _repo.visit(widget.friendUid);
      if (!mounted) return;
      setState(() {
        _v = v;
        _error = null;
      });
      _scene.sync(v.fruits, v.capacity, v.level);
      _scene.setLook(v.look);
    } on TreeException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  void _toast(String msg) {
    _toastTimer?.cancel();
    setState(() => _toastMsg = msg);
    _toastTimer = Timer(const Duration(milliseconds: 2800), () {
      if (mounted) setState(() => _toastMsg = null);
    });
  }

  Future<void> _water() async {
    if (_watering) return;
    setState(() => _watering = true);
    try {
      final bonus = await _repo.water(widget.friendUid);
      if (!mounted) return;
      HapticFeedback.mediumImpact();
      _scene.celebrate();
      _toast('Pohon ${widget.username} disiram! Buahnya tumbuh $bonus menit lebih cepat');
      await _load();
    } on TreeException catch (e) {
      _toast(e.message);
    } finally {
      if (mounted) setState(() => _watering = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final v = _v;
    final canWater = v != null && !v.wateredByMe && v.waterReceivedToday < v.waterReceiveLimit && !_watering;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
        systemNavigationBarColor: Color(0xFF173D22),
        systemNavigationBarIconBrightness: Brightness.light,
      ),
      child: Scaffold(
        backgroundColor: const Color(0xFF0E1424),
        body: Stack(
          children: [
            Positioned.fill(
              child: TreeScene(
                controller: _scene,
                onFruitTap: (_) => _toast('Ini pohon ${widget.username}, buahnya cuma bisa dipanen pemiliknya'),
              ),
            ),
            const Positioned(
              top: 0,
              left: 0,
              right: 0,
              height: 180,
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
            SafeArea(
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                    child: Row(
                      children: [
                        _GlassIconButton(
                          icon: Icons.arrow_back_rounded,
                          onTap: () => Navigator.of(context).maybePop(),
                        ),
                        const SizedBox(width: 8),
                        Flexible(
                          child: _Glass(
                            radius: 22,
                            padding: const EdgeInsets.fromLTRB(4, 4, 14, 4),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                FriendAvatar(
                                  url: widget.avatarUrl,
                                  seed: widget.friendUid,
                                  label: widget.username,
                                  size: 34,
                                ),
                                const SizedBox(width: 8),
                                Flexible(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(
                                        'Pohon ${widget.username}',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 13),
                                      ),
                                      Text(
                                        v == null ? '...' : 'Lv.${v.level} • ${v.fruits}/${v.capacity} buah',
                                        style: const TextStyle(color: Color(0xB3FFFFFF), fontSize: 11),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 250),
                    child: _toastMsg == null
                        ? const SizedBox.shrink()
                        : Padding(
                            key: ValueKey(_toastMsg),
                            padding: const EdgeInsets.symmetric(horizontal: 24),
                            child: _Glass(
                              radius: 16,
                              color: const Color(0xCC0F2A1B),
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                              child: Text(_toastMsg!, style: const TextStyle(color: Colors.white, fontSize: 13)),
                            ),
                          ),
                  ),
                  const Spacer(),
                  if (v != null) ...[
                    _Glass(
                      radius: 18,
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                      child: Text(
                        'Disiram hari ini ${v.waterReceivedToday}/${v.waterReceiveLimit}',
                        style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Opacity(
                      opacity: canWater || _watering ? 1.0 : 0.55,
                      child: _Pressable(
                        onTap: canWater ? _water : null,
                        child: Container(
                          width: 96,
                          height: 96,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: const RadialGradient(
                              center: Alignment(-0.3, -0.4),
                              colors: [Color(0xFFBAE6FD), Color(0xFF38BDF8), Color(0xFF0369A1)],
                              stops: [0, 0.55, 1],
                            ),
                            border: Border.all(color: const Color(0x99FFFFFF), width: 3),
                            boxShadow: const [BoxShadow(color: Color(0x8838BDF8), blurRadius: 22, offset: Offset(0, 6))],
                          ),
                          child: _watering
                              ? const Padding(
                                  padding: EdgeInsets.all(30),
                                  child: CircularProgressIndicator(strokeWidth: 3, color: Colors.white),
                                )
                              : Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(
                                      v.wateredByMe ? Icons.check_rounded : Icons.water_drop_rounded,
                                      color: Colors.white,
                                      size: 34,
                                    ),
                                    Text(
                                      v.wateredByMe ? 'DISIRAM' : 'SIRAM',
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.w900,
                                        fontSize: 12,
                                        letterSpacing: 1,
                                      ),
                                    ),
                                  ],
                                ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 18),
                  ],
                ],
              ),
            ),
            if (v == null)
              _error == null
                  ? const Center(child: CircularProgressIndicator(color: _kLeaf))
                  : _CenterCard(
                      icon: Icons.cloud_off_outlined,
                      text: _error!,
                      action: TextButton(onPressed: _load, child: const Text('Coba lagi')),
                    ),
          ],
        ),
      ),
    );
  }
}

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../data/models/account_models.dart' show formatZCoin;
import '../../../data/models/friend_models.dart';
import '../../../data/models/tree_models.dart';
import '../../../data/repository/tree_repository.dart';
import '../../../providers.dart';
import '../../app_routes.dart';
import '../../components/friend_avatar.dart';
import '../store/premium_screen.dart';
import 'tree_scene.dart';

const Color _kGold = Color(0xFFFFC53D);
const Color _kLeaf = Color(0xFF22C55E);

/// Pohon ZCoin: buah tumbuh pakai jam server, tap buah buat panen jadi ZCoin,
/// upgrade level, Premium tumbuh lebih cepat, siram pohon teman.
class TreeScreen extends ConsumerStatefulWidget {
  const TreeScreen({super.key});

  @override
  ConsumerState<TreeScreen> createState() => _TreeScreenState();
}

class _TreeScreenState extends ConsumerState<TreeScreen> {
  final TreeSceneController _scene = TreeSceneController();

  TreeState? _tree;
  String? _error;
  bool _loading = true;
  bool _upgrading = false;
  int? _balance;

  /// selisih jam server - jam HP (countdown pakai jam server).
  Duration _offset = Duration.zero;
  Timer? _clock;
  DateTime _lastAutoRefresh = DateTime.fromMillisecondsSinceEpoch(0);

  /// Buah yang sudah di-tap tapi belum dikirim ke server.
  int _pending = 0;

  /// Buah yang sedang dikirim ke server.
  int _inFlight = 0;
  Timer? _debounce;

  late final TreeRepository _repo;
  String? get _uid => ref.read(authUserProvider).valueOrNull?.uid;

  @override
  void initState() {
    super.initState();
    _repo = ref.read(treeRepositoryProvider);
    _load();
    _clock = Timer.periodic(const Duration(seconds: 1), (_) => _onClock());
  }

  @override
  void dispose() {
    _clock?.cancel();
    _debounce?.cancel();
    // kirim sisa panen yang belum terkirim
    if (_pending > 0) {
      final n = _pending;
      _pending = 0;
      unawaited(_repo.harvest(n).then((_) {}, onError: (_) {}));
    }
    _scene.dispose();
    super.dispose();
  }

  DateTime get _serverNow => DateTime.now().toUtc().add(_offset);

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
        _toast(e.message);
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
    if (next != null && !_serverNow.isBefore(next)) {
      // buah berikutnya sudah matang -> ambil state terbaru dari server
      if (DateTime.now().difference(_lastAutoRefresh) > const Duration(seconds: 5) &&
          _inFlight == 0 &&
          _pending == 0) {
        _lastAutoRefresh = DateTime.now();
        _load(silent: true);
      }
    }
    setState(() {}); // update countdown
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(msg), behavior: SnackBarBehavior.floating));
  }

  /// Sisa buah yang masih boleh dipetik hari ini (perkiraan lokal; server tetap
  /// yang menentukan).
  int _picksAllowed(TreeState tree) {
    final room = tree.coinsLeftToday;
    if (room <= 0) return 0;
    final maxFruits = (room / tree.coinsPerFruit).ceil();
    final left = maxFruits - _pending - _inFlight;
    return left < 0 ? 0 : left;
  }

  void _onFruitTap(int slot) {
    final tree = _tree;
    if (tree == null || _upgrading) return;
    if (_picksAllowed(tree) <= 0) {
      _toast('Batas ${tree.dailyCap} ZCoin dari pohon hari ini sudah tercapai. Balik lagi besok ya!');
      return;
    }
    if (!_scene.pick(slot, '+${tree.coinsPerFruit}')) return;
    _pending++;
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 450), _flush);
  }

  void _harvestAll() {
    final tree = _tree;
    if (tree == null || _upgrading) return;
    final allowed = _picksAllowed(tree);
    if (allowed <= 0) {
      _toast('Batas ${tree.dailyCap} ZCoin dari pohon hari ini sudah tercapai. Balik lagi besok ya!');
      return;
    }
    final n = _scene.pickAll('+${tree.coinsPerFruit}', allowed);
    if (n == 0) return;
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
        _toast('Cuma ${r.harvested} buah yang kepanen, batas ZCoin harian sudah penuh.');
      }
    } on TreeException catch (e) {
      _inFlight = 0;
      if (!mounted) return;
      _toast(e.message);
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
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => _UpgradeDialog(tree: tree, balance: balance),
    );
    if (ok != true || !mounted) return;
    // kirim dulu panen yang tertunda supaya hitungan buah tidak bentrok
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
      if (uid != null) ref.invalidate(coinBalanceProvider(uid));
      _toast('Pohon naik ke Lv.${r.tree.level}!');
    } on TreeException catch (e) {
      _toast(e.message);
    } finally {
      if (mounted) setState(() => _upgrading = false);
    }
  }

  Future<void> _openWater() async {
    final uid = _uid;
    final tree = _tree;
    if (uid == null || tree == null) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surfaceDark,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => _WaterSheet(uid: uid),
    );
  }

  // ------------------------------------------------------------------ UI

  @override
  Widget build(BuildContext context) {
    final uid = ref.watch(authUserProvider).valueOrNull?.uid;
    final providerBalance = uid == null ? null : ref.watch(coinBalanceProvider(uid)).valueOrNull;
    final balance = _balance ?? providerBalance;

    return Scaffold(
      backgroundColor: AppColors.backgroundDark,
      body: SafeArea(
        child: Column(
          children: [
            _TopBar(balance: balance),
            Expanded(child: _body(uid)),
          ],
        ),
      ),
    );
  }

  Widget _body(String? uid) {
    if (uid == null) {
      return const _Message(
        icon: Icons.lock_outline,
        text: 'Login dulu buat main Pohon ZCoin.',
      );
    }
    if (_loading && _tree == null) {
      return const Center(child: CircularProgressIndicator(color: _kLeaf));
    }
    final tree = _tree;
    if (tree == null) {
      return _Message(
        icon: Icons.cloud_off_outlined,
        text: _error ?? 'Gagal memuat pohon',
        action: TextButton(onPressed: _load, child: const Text('Coba lagi')),
      );
    }

    final shown = tree.fruits - _pending - _inFlight;
    final fruitsShown = shown < 0 ? 0 : shown;

    return RefreshIndicator(
      color: _kLeaf,
      onRefresh: () => _load(silent: true),
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
        children: [
          _sceneCard(tree, fruitsShown),
          const SizedBox(height: 12),
          _growthCard(tree),
          const SizedBox(height: 12),
          _dailyCard(tree),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _ActionButton(
                  icon: Icons.shopping_basket_outlined,
                  label: 'Panen Semua',
                  sub: fruitsShown > 0 ? '$fruitsShown buah' : 'Belum ada buah',
                  color: _kGold,
                  enabled: fruitsShown > 0 && !_upgrading,
                  onTap: _harvestAll,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _ActionButton(
                  icon: Icons.upgrade_rounded,
                  label: tree.isMaxLevel ? 'Level Max' : 'Upgrade',
                  sub: tree.isMaxLevel ? 'Lv.${tree.level}' : '${formatZCoin(tree.upgradeCost ?? 0)} ZCoin',
                  color: _kLeaf,
                  enabled: !tree.isMaxLevel && !_upgrading,
                  busy: _upgrading,
                  onTap: _upgrade,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _waterCard(tree),
          const SizedBox(height: 12),
          _premiumCard(tree),
        ],
      ),
    );
  }

  Widget _sceneCard(TreeState tree, int fruitsShown) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: SizedBox(
        height: 360,
        child: Stack(
          children: [
            Positioned.fill(
              child: TreeScene(controller: _scene, onFruitTap: _onFruitTap),
            ),
            Positioned(
              left: 12,
              top: 12,
              child: _Chip(
                icon: Icons.park_rounded,
                text: 'Lv.${tree.level}',
                color: _kLeaf,
              ),
            ),
            Positioned(
              right: 12,
              top: 12,
              child: _Chip(
                icon: Icons.circle,
                text: '$fruitsShown/${tree.capacity}',
                color: _kGold,
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 12,
              child: IgnorePointer(
                child: Center(
                  child: _Chip(
                    icon: tree.isFull ? Icons.warning_amber_rounded : Icons.touch_app_outlined,
                    text: tree.isFull
                        ? 'Pohon penuh! Panen biar berbuah lagi'
                        : fruitsShown > 0
                            ? 'Tap buahnya buat panen'
                            : 'Sabar, buahnya lagi tumbuh...',
                    color: tree.isFull ? AppColors.warningAmber : Colors.white,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _growthCard(TreeState tree) {
    final next = tree.nextFruitAt;
    Widget content;
    if (next == null) {
      content = const Row(
        children: [
          Icon(Icons.pause_circle_outline, color: AppColors.warningAmber),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              'Pohon berhenti berbuah karena penuh. Panen dulu biar tumbuh lagi.',
              style: TextStyle(color: AppColors.textWhite, fontSize: 13),
            ),
          ),
        ],
      );
    } else {
      var remaining = next.difference(_serverNow);
      if (remaining.isNegative) remaining = Duration.zero;
      final total = tree.intervalSec <= 0 ? 1 : tree.intervalSec;
      final progress = (1 - remaining.inSeconds / total).clamp(0.0, 1.0);
      content = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text(
                'Buah berikutnya',
                style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
              ),
              const Spacer(),
              Text(
                remaining == Duration.zero ? 'Matang!' : _fmtCountdown(remaining),
                style: const TextStyle(
                  color: AppColors.textWhite,
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 8,
              backgroundColor: AppColors.surfaceElevated,
              valueColor: const AlwaysStoppedAnimation(_kLeaf),
            ),
          ),
        ],
      );
    }
    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          content,
          const SizedBox(height: 10),
          Text(
            '1 buah tiap ${formatTreeMinutes((tree.intervalSec / 60).round())}'
            ' • +${tree.coinsPerFruit} ZCoin/buah • maks ${tree.capacity} buah',
            style: const TextStyle(color: AppColors.textMuted, fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget _dailyCard(TreeState tree) {
    final cap = tree.dailyCap <= 0 ? 1 : tree.dailyCap;
    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Image.asset('assets/images/ic_zcoin_badge.png', width: 18, height: 18),
              const SizedBox(width: 8),
              const Text(
                'ZCoin dari pohon hari ini',
                style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
              ),
              const Spacer(),
              Text(
                '${tree.coinsToday}/${tree.dailyCap}',
                style: const TextStyle(color: _kGold, fontSize: 15, fontWeight: FontWeight.w700),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: (tree.coinsToday / cap).clamp(0.0, 1.0),
              minHeight: 8,
              backgroundColor: AppColors.surfaceElevated,
              valueColor: const AlwaysStoppedAnimation(_kGold),
            ),
          ),
        ],
      ),
    );
  }

  Widget _waterCard(TreeState tree) {
    final left = (tree.waterGiveLimit - tree.waterGivenToday).clamp(0, tree.waterGiveLimit);
    return _Card(
      onTap: _openWater,
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: const Color(0x2238BDF8),
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(Icons.water_drop_rounded, color: Color(0xFF38BDF8)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Siram pohon teman',
                  style: TextStyle(color: AppColors.textWhite, fontSize: 15, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 2),
                Text(
                  'Sisa jatah $left/${tree.waterGiveLimit} • tiap siraman +${tree.waterBonusMin} mnt\n'
                  'Pohonmu disiram teman hari ini: ${tree.waterReceivedToday}/${tree.waterReceiveLimit}',
                  style: const TextStyle(color: AppColors.textSecondary, fontSize: 12, height: 1.35),
                ),
              ],
            ),
          ),
          const Icon(Icons.chevron_right, color: AppColors.textMuted),
        ],
      ),
    );
  }

  Widget _premiumCard(TreeState tree) {
    final speed = formatTreeSpeed(tree.premiumSpeed);
    if (tree.premium) {
      return _Card(
        child: Row(
          children: [
            Image.asset('assets/images/ic_premium_badge.png', width: 22, height: 22),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Premium aktif: pohonmu tumbuh $speed lebih cepat',
                style: const TextStyle(color: AppColors.textWhite, fontSize: 13),
              ),
            ),
            const Icon(Icons.bolt_rounded, color: _kGold),
          ],
        ),
      );
    }
    return _Card(
      onTap: () => Navigator.of(context).push<void>(fadeRoute(const PremiumScreen())),
      child: Row(
        children: [
          Image.asset('assets/images/ic_premium_badge.png', width: 22, height: 22),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Pakai Premium biar pohon tumbuh $speed lebih cepat',
              style: const TextStyle(color: AppColors.textWhite, fontSize: 13),
            ),
          ),
          const Icon(Icons.chevron_right, color: AppColors.textMuted),
        ],
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

// ==================================================================== widgets

class _TopBar extends StatelessWidget {
  const _TopBar({required this.balance});

  final int? balance;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 4, 16, 8),
      child: Row(
        children: [
          IconButton(
            onPressed: () => Navigator.of(context).maybePop(),
            icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
          ),
          const Text(
            'Pohon ZCoin',
            style: TextStyle(color: Colors.white, fontSize: 19, fontWeight: FontWeight.w700),
          ),
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: AppColors.surfaceDark,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: const Color(0x33FFC53D)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Image.asset('assets/images/ic_zcoin_badge.png', width: 16, height: 16),
                const SizedBox(width: 6),
                Text(
                  balance == null ? '-' : formatZCoin(balance!),
                  style: const TextStyle(color: _kGold, fontWeight: FontWeight.w700, fontSize: 13),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({required this.child, this.onTap});

  final Widget child;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surfaceDark,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Padding(padding: const EdgeInsets.all(14), child: child),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.icon, required this.text, required this.color});

  final IconData icon;
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0x99000000),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 6),
          Text(
            text,
            style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.icon,
    required this.label,
    required this.sub,
    required this.color,
    required this.enabled,
    required this.onTap,
    this.busy = false,
  });

  final IconData icon;
  final String label;
  final String sub;
  final Color color;
  final bool enabled;
  final bool busy;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: enabled || busy ? 1 : 0.45,
      child: Material(
        color: AppColors.surfaceDark,
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          onTap: enabled ? onTap : null,
          borderRadius: BorderRadius.circular(18),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: color.withValues(alpha: 0.35)),
            ),
            child: Row(
              children: [
                busy
                    ? SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(strokeWidth: 2.4, color: color),
                      )
                    : Icon(icon, color: color),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        label,
                        style: const TextStyle(
                          color: AppColors.textWhite,
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                        ),
                      ),
                      Text(
                        sub,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: color, fontSize: 12),
                      ),
                    ],
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

class _Message extends StatelessWidget {
  const _Message({required this.icon, required this.text, this.action});

  final IconData icon;
  final String text;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: AppColors.textMuted, size: 42),
            const SizedBox(height: 12),
            Text(
              text,
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.textSecondary, fontSize: 14),
            ),
            if (action != null) ...[const SizedBox(height: 8), action!],
          ],
        ),
      ),
    );
  }
}

class _UpgradeDialog extends StatelessWidget {
  const _UpgradeDialog({required this.tree, required this.balance});

  final TreeState tree;
  final int? balance;

  @override
  Widget build(BuildContext context) {
    final next = tree.next;
    final cost = tree.upgradeCost ?? 0;
    final enough = balance == null || balance! >= cost;

    Widget row(String label, String from, String to) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 5),
          child: Row(
            children: [
              Expanded(
                child: Text(label, style: const TextStyle(color: AppColors.textSecondary, fontSize: 13)),
              ),
              Text(from, style: const TextStyle(color: AppColors.textMuted, fontSize: 13)),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 6),
                child: Icon(Icons.arrow_forward_rounded, size: 14, color: AppColors.textMuted),
              ),
              Text(
                to,
                style: const TextStyle(color: _kLeaf, fontSize: 13, fontWeight: FontWeight.w700),
              ),
            ],
          ),
        );

    return AlertDialog(
      backgroundColor: AppColors.surfaceDark,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      title: Text(
        'Upgrade ke Lv.${tree.level + 1}',
        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (next != null) ...[
            row(
              '1 buah tiap',
              formatTreeMinutes((tree.intervalSec / 60).round()),
              formatTreeMinutes((next.intervalSec / 60).round()),
            ),
            row('Maks buah', '${tree.capacity}', '${next.capacity}'),
            row('ZCoin/buah', '${tree.coinsPerFruit}', '${next.coinsPerFruit}'),
          ],
          const SizedBox(height: 12),
          Row(
            children: [
              Image.asset('assets/images/ic_zcoin_badge.png', width: 18, height: 18),
              const SizedBox(width: 8),
              Text(
                'Biaya ${formatZCoin(cost)} ZCoin',
                style: const TextStyle(color: _kGold, fontWeight: FontWeight.w700),
              ),
            ],
          ),
          if (!enough) ...[
            const SizedBox(height: 6),
            Text(
              'ZCoin kamu ${formatZCoin(balance ?? 0)}, belum cukup.',
              style: const TextStyle(color: AppColors.errorRed, fontSize: 12),
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Batal', style: TextStyle(color: AppColors.textSecondary)),
        ),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: _kLeaf),
          onPressed: enough ? () => Navigator.of(context).pop(true) : null,
          child: const Text('Upgrade'),
        ),
      ],
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
      body = _Message(
        icon: Icons.cloud_off_outlined,
        text: _error!,
        action: TextButton(onPressed: _load, child: const Text('Coba lagi')),
      );
    } else if (friends == null || status == null) {
      body = const Padding(
        padding: EdgeInsets.all(40),
        child: Center(child: CircularProgressIndicator(color: Color(0xFF38BDF8))),
      );
    } else if (friends.isEmpty) {
      body = const _Message(
        icon: Icons.group_outlined,
        text: 'Belum punya teman. Tambah teman dulu biar bisa saling siram pohon.',
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
              color: AppColors.surfaceVariantDark,
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
                    style: const TextStyle(color: AppColors.textWhite, fontWeight: FontWeight.w600),
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
            const SizedBox(height: 10),
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.textMuted,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 16, 16, 4),
              child: Text(
                'Siram pohon teman',
                style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
              child: Text(
                status == null
                    ? 'Tiap siraman bikin buah temanmu tumbuh lebih cepat.'
                    : 'Sisa jatah hari ini ${status.left}/${status.giveLimit} • '
                        'tiap siraman +${status.bonusMin} mnt buat pohon temanmu',
                style: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
              ),
            ),
            Flexible(child: body),
          ],
        ),
      ),
    );
  }
}

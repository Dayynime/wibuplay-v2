import 'dart:async';
import 'dart:math' as math;

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wibuplay/core/wp_video.dart';

import '../../../core/theme/app_colors.dart';
import '../../../data/repository/authed_function.dart';
import '../../../providers.dart';
import '../../components/app_toast.dart';
import '../../glass/glass.dart';
import '../chat/chat_mute.dart' show canChatMuteProvider;

// =================================================================== data

/// Satu danmaku: komentar yang melayang saat video di detik [tMs].
class DanmakuItem {
  const DanmakuItem({required this.id, required this.tMs, required this.body, required this.uid, this.color});

  final int id;
  final int tMs;
  final String body;
  final String? color;
  final String uid;

  /// Server mengirim bentuk ringkas: [id, t_ms, body, color, uid].
  static DanmakuItem? fromRow(dynamic r) {
    if (r is! List || r.length < 5) return null;
    final id = (r[0] as num?)?.toInt();
    final t = (r[1] as num?)?.toInt();
    final body = r[2];
    if (id == null || t == null || body is! String || body.isEmpty) return null;
    return DanmakuItem(id: id, tMs: t, body: body, color: r[3] as String?, uid: (r[4] as String?) ?? '');
  }

  Color get colorValue {
    final c = color;
    if (c == null || c.length != 7) return Colors.white;
    final v = int.tryParse(c.substring(1), radix: 16);
    return v == null ? Colors.white : Color(0xFF000000 | v);
  }
}

/// Warna pilihan (sama dengan server).
const List<String> kDanmakuColors = ['#FFFFFF', '#FF5C7A', '#FFD54A', '#4ADE80', '#22D3EE', '#C084FC'];

const List<String> _quick = ['PLOT TWIST 😱', 'wkwkwk 🤣', 'OP terbaik!!', 'SAD 😭', 'GG 🔥', 'Kawaii 😍'];

class _DanmakuApi {
  _DanmakuApi(this._dio);

  final Dio _dio;

  Future<dynamic> _call(Map<String, dynamic> body, String fallback) async {
    try {
      return await callAuthedFunction(_dio, 'danmaku', body);
    } on DioException catch (_) {
      throw Exception('Koneksi bermasalah, coba lagi');
    } catch (e) {
      final m = e.toString().replaceFirst('Exception: ', '').trim();
      if (m.toLowerCase().contains('unauthorized')) throw Exception('Login dulu untuk memakai danmaku');
      throw Exception(m.isEmpty || m.length > 200 ? fallback : m);
    }
  }

  Future<List<DanmakuItem>> list(String key) async {
    final d = await _call({'action': 'list', 'key': key}, 'Gagal memuat danmaku');
    final items = d is Map ? d['items'] : null;
    if (items is! List) return const [];
    return items.map(DanmakuItem.fromRow).whereType<DanmakuItem>().toList();
  }

  Future<DanmakuItem> send(String key, int tMs, String body, String? color) async {
    final d = await _call(
      {'action': 'send', 'key': key, 't_ms': tMs, 'body': body, if (color != null) 'color': color},
      'Gagal mengirim danmaku',
    );
    final it = DanmakuItem.fromRow(d is Map ? d['item'] : null);
    if (it == null) throw Exception('Gagal mengirim danmaku');
    return it;
  }

  Future<void> delete(int id) => _call({'action': 'delete', 'id': id}, 'Gagal menghapus danmaku');
}

/// Danmaku satu episode untuk satu layar player.
/// key: 'a:<episodeId>' (anime) / 'd:<slug>' (donghua).
class DanmakuController extends ChangeNotifier {
  DanmakuController(Dio dio) : _api = _DanmakuApi(dio);

  final _DanmakuApi _api;
  String? _key;
  int _gen = 0;
  List<DanmakuItem> _items = const [];

  /// Naik setiap daftar berubah (dipakai layer untuk hitung ulang jalur).
  int version = 0;

  String? get key => _key;
  List<DanmakuItem> get items => _items;

  /// Ganti episode. Aman dipanggil di build (pemuatan dijadwalkan).
  void setKey(String key) {
    if (key == _key) return;
    _key = key;
    final gen = ++_gen;
    _items = const [];
    version++;
    scheduleMicrotask(() async {
      try {
        final list = await _api.list(key);
        if (gen != _gen) return;
        list.sort((a, b) => a.tMs != b.tMs ? a.tMs.compareTo(b.tMs) : a.id.compareTo(b.id));
        _items = list;
        version++;
        notifyListeners();
      } catch (_) {
        // Belum login / jaringan: video tetap jalan tanpa danmaku.
      }
      if (gen == _gen) notifyListeners();
    });
  }

  /// Kirim. Return pesan error (null = sukses). Danmaku langsung ikut melayang.
  Future<String?> send(int tMs, String body, String? color) async {
    final key = _key;
    if (key == null) return 'Video belum siap';
    try {
      final it = await _api.send(key, tMs, body, color);
      if (key != _key) return null;
      _items = [..._items, it]..sort((a, b) => a.tMs != b.tMs ? a.tMs.compareTo(b.tMs) : a.id.compareTo(b.id));
      version++;
      notifyListeners();
      return null;
    } catch (e) {
      return e.toString().replaceFirst('Exception: ', '');
    }
  }

  Future<String?> delete(int id) async {
    try {
      await _api.delete(id);
      _items = _items.where((x) => x.id != id).toList();
      version++;
      notifyListeners();
      return null;
    } catch (e) {
      return e.toString().replaceFirst('Exception: ', '');
    }
  }
}

// =================================================================== setelan

class DanmakuSettings {
  const DanmakuSettings({this.enabled = true, this.opacity = 0.9, this.fontSize = 16});

  final bool enabled;
  final double opacity;
  final double fontSize;

  DanmakuSettings copyWith({bool? enabled, double? opacity, double? fontSize}) => DanmakuSettings(
        enabled: enabled ?? this.enabled,
        opacity: opacity ?? this.opacity,
        fontSize: fontSize ?? this.fontSize,
      );
}

class DanmakuSettingsNotifier extends StateNotifier<DanmakuSettings> {
  DanmakuSettingsNotifier() : super(const DanmakuSettings()) {
    _load();
  }

  static const _kOn = 'dm_on';
  static const _kOpacity = 'dm_opacity';
  static const _kSize = 'dm_size';

  Future<void> _load() async {
    try {
      final p = await SharedPreferences.getInstance();
      state = DanmakuSettings(
        enabled: p.getBool(_kOn) ?? true,
        opacity: (p.getDouble(_kOpacity) ?? 0.9).clamp(0.2, 1.0).toDouble(),
        fontSize: (p.getDouble(_kSize) ?? 16).clamp(12, 24).toDouble(),
      );
    } catch (_) {}
  }

  Future<void> _save() async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.setBool(_kOn, state.enabled);
      await p.setDouble(_kOpacity, state.opacity);
      await p.setDouble(_kSize, state.fontSize);
    } catch (_) {}
  }

  void setEnabled(bool v) {
    state = state.copyWith(enabled: v);
    _save();
  }

  void setOpacity(double v) {
    state = state.copyWith(opacity: v);
    _save();
  }

  void setFontSize(double v) {
    state = state.copyWith(fontSize: v);
    _save();
  }
}

final danmakuSettingsProvider =
    StateNotifierProvider<DanmakuSettingsNotifier, DanmakuSettings>((ref) => DanmakuSettingsNotifier());

// =================================================================== layer

/// Lapisan danmaku di atas video. Posisi teks dihitung dari posisi video,
/// jadi ikut berhenti saat pause dan langsung menyesuaikan saat seek.
class DanmakuLayer extends ConsumerStatefulWidget {
  const DanmakuLayer({super.key, required this.controller, required this.video, this.speed = 1.0});

  final DanmakuController controller;
  final WpVideoController video;

  /// Kecepatan putar video (danmaku ikut lebih cepat/lambat).
  final double speed;

  @override
  ConsumerState<DanmakuLayer> createState() => _DanmakuLayerState();
}

class _DanmakuLayerState extends ConsumerState<DanmakuLayer> with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  final _repaint = ValueNotifier<int>(0);

  int _basePos = 0;
  Duration _baseElapsed = Duration.zero;
  Duration _elapsed = Duration.zero;
  bool _playing = false;
  bool _enabled = true;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker((e) {
      _elapsed = e;
      if (_playing) _repaint.value++;
    });
    widget.video.addListener(_onVideo);
    widget.controller.addListener(_onItems);
    _onVideo();
  }

  @override
  void didUpdateWidget(covariant DanmakuLayer old) {
    super.didUpdateWidget(old);
    if (old.video != widget.video) {
      old.video.removeListener(_onVideo);
      widget.video.addListener(_onVideo);
      _onVideo();
    }
    if (old.controller != widget.controller) {
      old.controller.removeListener(_onItems);
      widget.controller.addListener(_onItems);
    }
  }

  @override
  void dispose() {
    _ticker.dispose();
    widget.video.removeListener(_onVideo);
    widget.controller.removeListener(_onItems);
    _repaint.dispose();
    super.dispose();
  }

  void _onItems() {
    _syncTicker();
    _repaint.value++;
  }

  void _onVideo() {
    final v = widget.video.value;
    _basePos = v.position.inMilliseconds;
    _baseElapsed = _elapsed;
    _playing = v.isPlaying && !v.isBuffering;
    _syncTicker();
    _repaint.value++;
  }

  /// Ticker cuma jalan saat perlu (danmaku nyala, ada isi, video main),
  /// supaya tidak memakan baterai.
  void _syncTicker() {
    final want = _enabled && _playing && widget.controller.items.isNotEmpty;
    if (want && !_ticker.isActive) {
      _baseElapsed = Duration.zero;
      _elapsed = Duration.zero;
      _ticker.start();
    } else if (!want && _ticker.isActive) {
      _basePos = _positionMs();
      _ticker.stop();
      _elapsed = Duration.zero;
      _baseElapsed = Duration.zero;
    }
  }

  /// Posisi video sekarang (diinterpolasi antar update dari player).
  int _positionMs() {
    if (!_playing) return _basePos;
    final dt = (_elapsed - _baseElapsed).inMilliseconds;
    // Update player paling lambat ~0,5 dtk; lebih dari itu jangan ditebak.
    return _basePos + (math.min(dt, 600) * widget.speed).round();
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(danmakuSettingsProvider);
    if (s.enabled != _enabled) {
      _enabled = s.enabled;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _syncTicker();
      });
    }
    if (!s.enabled) return const SizedBox.shrink();
    final myUid = ref.watch(authUserProvider).valueOrNull?.uid ?? '';
    return IgnorePointer(
      child: RepaintBoundary(
        child: CustomPaint(
          size: Size.infinite,
          painter: _DanmakuPainter(
            controller: widget.controller,
            position: _positionMs,
            repaint: _repaint,
            settings: s,
            myUid: myUid,
          ),
        ),
      ),
    );
  }
}

class _Slot {
  _Slot(this.item, this.lane, this.width, this.speed);

  final DanmakuItem item;
  final int lane;
  final double width;

  /// px per ms (posisi video).
  final double speed;
}

class _DanmakuPainter extends CustomPainter {
  _DanmakuPainter({
    required this.controller,
    required this.position,
    required Listenable repaint,
    required this.settings,
    required this.myUid,
  }) : super(repaint: repaint);

  final DanmakuController controller;
  final int Function() position;
  final DanmakuSettings settings;
  final String myUid;

  static const int _travelMs = 7000;

  // Cache jalur & teks (dibuat ulang saat daftar / ukuran / font berubah).
  static final Expando<_Layout> _layouts = Expando<_Layout>();

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty || controller.items.isEmpty) return;
    final layout = _layoutFor(size);
    final pos = position();
    final lineH = settings.fontSize * 1.45;

    canvas.save();
    canvas.clipRect(Offset.zero & size);
    // Cari slot yang tampil: t <= pos <= t + durasi (maks _travelMs * 2).
    final from = _lowerBound(layout.slots, pos - _travelMs * 2);
    for (var i = from; i < layout.slots.length; i++) {
      final s = layout.slots[i];
      if (s.item.tMs > pos) break;
      final x = size.width - (pos - s.item.tMs) * s.speed;
      if (x + s.width < 0) continue;
      final y = 6 + s.lane * lineH;
      final tp = layout.painters(s.item, settings, s.item.uid == myUid);
      if (s.item.uid == myUid && myUid.isNotEmpty) {
        final r = RRect.fromRectAndRadius(
          Rect.fromLTWH(x - 5, y - 1, s.width + 10, tp.$1.height + 2),
          const Radius.circular(6),
        );
        canvas.drawRRect(
          r,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.2
            ..color = Colors.white.withValues(alpha: 0.75 * settings.opacity),
        );
      }
      tp.$2.paint(canvas, Offset(x, y));
      tp.$1.paint(canvas, Offset(x, y));
    }
    canvas.restore();
    layout.prune(pos, _travelMs * 2);
  }

  int _lowerBound(List<_Slot> slots, int t) {
    var lo = 0;
    var hi = slots.length;
    while (lo < hi) {
      final mid = (lo + hi) >> 1;
      if (slots[mid].item.tMs < t) {
        lo = mid + 1;
      } else {
        hi = mid;
      }
    }
    return lo;
  }

  _Layout _layoutFor(Size size) {
    var l = _layouts[controller];
    if (l == null ||
        l.version != controller.version ||
        l.width != size.width ||
        l.height != size.height ||
        l.fontSize != settings.fontSize ||
        l.opacity != settings.opacity) {
      l = _Layout.build(controller, size, settings);
      _layouts[controller] = l;
    }
    return l;
  }

  @override
  bool shouldRepaint(covariant _DanmakuPainter old) =>
      old.controller != controller || old.settings != settings || old.myUid != myUid;
}

class _Layout {
  _Layout._(this.version, this.width, this.height, this.fontSize, this.opacity, this.slots);

  final int version;
  final double width;
  final double height;
  final double fontSize;
  final double opacity;
  final List<_Slot> slots;
  final Map<int, (TextPainter, TextPainter)> _cache = {};

  /// Jalur dipilih rakus berdasarkan perkiraan lebar teks, supaya tidak
  /// saling tabrak. Kalau semua jalur penuh, danmaku dilewati (seperti Bilibili).
  static _Layout build(DanmakuController c, Size size, DanmakuSettings s) {
    final lineH = s.fontSize * 1.45;
    // Danmaku memakai 3/4 tinggi video bagian atas (subtitle tetap terbaca).
    final lanes = math.max(1, ((size.height * 0.75 - 6) / lineH).floor());
    final laneLast = List<_Slot?>.filled(lanes, null);
    final slots = <_Slot>[];
    const gap = 24.0;
    for (final it in c.items) {
      final w = _estimateWidth(it.body, s.fontSize);
      final v = (size.width + w) / _DanmakuPainter._travelMs;
      for (var lane = 0; lane < lanes; lane++) {
        final prev = laneLast[lane];
        var ok = true;
        if (prev != null) {
          // Ekor yang lama sudah masuk layar + jarak, dan yang baru tidak menyusul.
          final tailIn = prev.item.tMs + (prev.width + gap) / prev.speed;
          final prevExit = prev.item.tMs + (size.width + prev.width) / prev.speed;
          final catchUp = prevExit - size.width / v;
          ok = it.tMs >= tailIn && it.tMs >= catchUp;
        }
        if (ok) {
          final slot = _Slot(it, lane, w, v);
          laneLast[lane] = slot;
          slots.add(slot);
          break;
        }
      }
    }
    return _Layout._(c.version, size.width, size.height, s.fontSize, s.opacity, slots);
  }

  static double _estimateWidth(String text, double fontSize) {
    var units = 0.0;
    for (final r in text.runes) {
      // Emoji & huruf lebar dihitung lebih lebar.
      units += r > 0x2E80 ? 1.15 : (r >= 0x41 && r <= 0x5A ? 0.68 : 0.56);
    }
    return units * fontSize;
  }

  (TextPainter, TextPainter) painters(DanmakuItem it, DanmakuSettings s, bool mine) {
    return _cache.putIfAbsent(it.id, () {
      final color = it.colorValue.withValues(alpha: s.opacity);
      final fill = TextPainter(
        text: TextSpan(
          text: it.body,
          style: TextStyle(color: color, fontSize: s.fontSize, fontWeight: FontWeight.w700, height: 1.2),
        ),
        textDirection: TextDirection.ltr,
        maxLines: 1,
      )..layout();
      final stroke = TextPainter(
        text: TextSpan(
          text: it.body,
          style: TextStyle(
            fontSize: s.fontSize,
            fontWeight: FontWeight.w700,
            height: 1.2,
            foreground: Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = 2.6
              ..color = Colors.black.withValues(alpha: 0.75 * s.opacity),
          ),
        ),
        textDirection: TextDirection.ltr,
        maxLines: 1,
      )..layout();
      return (fill, stroke);
    });
  }

  /// Buang cache teks yang sudah jauh dari posisi sekarang.
  void prune(int pos, int window) {
    if (_cache.length < 120) return;
    final keep = <int>{
      for (final s in slots)
        if (s.item.tMs > pos - window && s.item.tMs <= pos + 1000) s.item.id,
    };
    _cache.removeWhere((id, _) => !keep.contains(id));
  }
}

// =================================================================== tombol & sheet

/// Tombol "DM" di kontrol player.
class DanmakuToggleIcon extends ConsumerWidget {
  const DanmakuToggleIcon({super.key, required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final on = ref.watch(danmakuSettingsProvider.select((s) => s.enabled));
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: on ? AppColors.textWhite : Colors.white38, width: 1.4),
          color: on ? AppColors.accentViolet.withValues(alpha: 0.85) : Colors.transparent,
        ),
        child: Text(
          'DM',
          style: TextStyle(
            color: on ? Colors.white : Colors.white54,
            fontSize: 11,
            fontWeight: FontWeight.w900,
            letterSpacing: 0.5,
          ),
        ),
      ),
    );
  }
}

String _fmtTime(int ms) {
  final s = ms ~/ 1000;
  final h = s ~/ 3600;
  final m = (s % 3600) ~/ 60;
  final sec = s % 60;
  String two(int v) => v.toString().padLeft(2, '0');
  return h > 0 ? '$h:${two(m)}:${two(sec)}' : '${two(m)}:${two(sec)}';
}

/// Lembar danmaku: nyala/mati, transparansi, ukuran, kirim di detik ini,
/// dan daftar danmaku episode (hapus milik sendiri / oleh pemegang role).
Future<void> showDanmakuSheet(BuildContext context, {required DanmakuController controller, required int positionMs}) {
  return showGlassSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.surfaceDark,
    builder: (_) => _DanmakuSheet(controller: controller, positionMs: positionMs),
  );
}

class _DanmakuSheet extends ConsumerStatefulWidget {
  const _DanmakuSheet({required this.controller, required this.positionMs});

  final DanmakuController controller;
  final int positionMs;

  @override
  ConsumerState<_DanmakuSheet> createState() => _DanmakuSheetState();
}

class _DanmakuSheetState extends ConsumerState<_DanmakuSheet> {
  final _text = TextEditingController();
  String _color = kDanmakuColors.first;
  bool _sending = false;
  bool _showList = false;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _send([String? preset]) async {
    final body = (preset ?? _text.text).trim();
    if (body.isEmpty || _sending) return;
    setState(() => _sending = true);
    final err = await widget.controller.send(widget.positionMs, body, _color == kDanmakuColors.first ? null : _color);
    if (!mounted) return;
    setState(() => _sending = false);
    if (err != null) {
      showAppToast(context, err, kind: ToastKind.error);
      return;
    }
    HapticFeedback.lightImpact();
    if (!ref.read(danmakuSettingsProvider).enabled) {
      ref.read(danmakuSettingsProvider.notifier).setEnabled(true);
    }
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(danmakuSettingsProvider);
    final n = ref.read(danmakuSettingsProvider.notifier);
    final myUid = ref.watch(authUserProvider).valueOrNull?.uid ?? '';
    final staff = ref.watch(canChatMuteProvider).valueOrNull == true;

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(18, 16, 18, 12 + MediaQuery.viewInsetsOf(context).bottom),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                    decoration: BoxDecoration(color: AppColors.accentViolet, borderRadius: BorderRadius.circular(6)),
                    child: const Text('DM', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 12)),
                  ),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Text(
                      'Danmaku',
                      style: TextStyle(color: AppColors.textWhite, fontSize: 18, fontWeight: FontWeight.w800),
                    ),
                  ),
                  Switch(
                    value: s.enabled,
                    activeColor: AppColors.accentViolet,
                    onChanged: n.setEnabled,
                  ),
                ],
              ),
              const Text(
                'Komentar penonton lain melayang di video, pas di detik mereka kirim.',
                style: TextStyle(color: AppColors.textSecondary, fontSize: 12.5),
              ),
              if (s.enabled) ...[
                const SizedBox(height: 8),
                Row(
                  children: [
                    const SizedBox(width: 92, child: Text('Transparansi', style: TextStyle(color: AppColors.textSecondary, fontSize: 13))),
                    Expanded(
                      child: Slider(
                        value: s.opacity,
                        min: 0.2,
                        max: 1,
                        activeColor: AppColors.accentViolet,
                        onChanged: n.setOpacity,
                      ),
                    ),
                  ],
                ),
                Row(
                  children: [
                    const SizedBox(width: 92, child: Text('Ukuran teks', style: TextStyle(color: AppColors.textSecondary, fontSize: 13))),
                    Expanded(
                      child: Slider(
                        value: s.fontSize,
                        min: 12,
                        max: 24,
                        divisions: 6,
                        activeColor: AppColors.accentViolet,
                        onChanged: n.setFontSize,
                      ),
                    ),
                  ],
                ),
              ],
              const Divider(color: Color(0x22FFFFFF), height: 22),
              Text(
                'Kirim di ${_fmtTime(widget.positionMs)}',
                style: const TextStyle(color: AppColors.textWhite, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final q in _quick)
                    ActionChip(
                      label: Text(q, style: const TextStyle(color: AppColors.textWhite, fontSize: 12.5)),
                      backgroundColor: AppColors.surfaceCard,
                      side: BorderSide.none,
                      shape: const StadiumBorder(),
                      onPressed: _sending ? null : () => _send(q),
                    ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  for (final c in kDanmakuColors)
                    GestureDetector(
                      onTap: () => setState(() => _color = c),
                      child: Container(
                        width: 26,
                        height: 26,
                        margin: const EdgeInsets.only(right: 8),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: DanmakuItem(id: 0, tMs: 0, body: '', uid: '', color: c).colorValue,
                          border: Border.all(
                            color: _color == c ? AppColors.accentVioletLight : Colors.white24,
                            width: _color == c ? 3 : 1,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _text,
                      maxLength: 50,
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => _send(),
                      style: TextStyle(
                        color: DanmakuItem(id: 0, tMs: 0, body: '', uid: '', color: _color).colorValue,
                        fontWeight: FontWeight.w700,
                      ),
                      decoration: InputDecoration(
                        counterText: '',
                        isDense: true,
                        hintText: 'Tulis danmaku (maks 50)...',
                        hintStyle: const TextStyle(color: AppColors.textMuted, fontWeight: FontWeight.w400),
                        filled: true,
                        fillColor: AppColors.surfaceCard,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(22), borderSide: BorderSide.none),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filled(
                    onPressed: _sending ? null : () => _send(),
                    style: IconButton.styleFrom(backgroundColor: AppColors.accentViolet),
                    icon: _sending
                        ? const SizedBox.square(
                            dimension: 18,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : const Icon(Icons.send_rounded, color: Colors.white, size: 20),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              ListenableBuilder(
                listenable: widget.controller,
                builder: (context, _) {
                  final items = widget.controller.items;
                  final visible = items.where((i) => i.uid == myUid || staff).toList()
                    ..sort((a, b) => b.id.compareTo(a.id));
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      TextButton.icon(
                        onPressed: visible.isEmpty ? null : () => setState(() => _showList = !_showList),
                        icon: Icon(_showList ? Icons.expand_less_rounded : Icons.expand_more_rounded, size: 18),
                        label: Text(
                          staff
                              ? '${items.length} danmaku di episode ini · kelola'
                              : '${items.length} danmaku di episode ini${visible.isEmpty ? '' : ' · punyaku (${visible.length})'}',
                        ),
                      ),
                      if (_showList)
                        for (final it in visible.take(40))
                          ListTile(
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            leading: Text(
                              _fmtTime(it.tMs),
                              style: const TextStyle(color: AppColors.textMuted, fontFamily: 'monospace', fontSize: 12),
                            ),
                            title: Text(
                              it.body,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(color: it.colorValue, fontWeight: FontWeight.w600),
                            ),
                            trailing: IconButton(
                              icon: const Icon(Icons.delete_outline_rounded, color: AppColors.errorRed, size: 20),
                              onPressed: () async {
                                final err = await widget.controller.delete(it.id);
                                if (err != null && context.mounted) {
                                  showAppToast(context, err, kind: ToastKind.error);
                                }
                              },
                            ),
                          ),
                    ],
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

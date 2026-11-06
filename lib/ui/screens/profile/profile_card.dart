import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/theme/app_colors.dart';
import '../../../data/local/entities.dart';
import '../../../providers.dart';
import '../../components/app_toast.dart';
import '../../components/clan_tag_badge.dart';
import '../../components/net_image.dart';
import '../../components/profile_badges.dart';
import '../../components/rarity_chip.dart';
import '../../components/role_badges.dart';
import 'profile_screen.dart' show ProfileHeroAvatar, ProfileClanPill;

const String _mono = 'monospace';
const Color _cyan = Color(0xFF22D3EE);
const Color _magenta = Color(0xFFD946EF);

/// Buka kartu profil futuristik (kartu pemain) yang bisa disimpan / dibagikan.
/// [favorites], [animeCount], [episodeCount] diambil dari layar profil yang
/// memanggil (profil sendiri = data lokal, orang lain = data publik).
Future<void> showProfileCard(
  BuildContext context, {
  required String uid,
  required List<FavoriteEntity> favorites,
  required int animeCount,
  required int episodeCount,
}) {
  return Navigator.of(context).push<void>(
    PageRouteBuilder<void>(
      opaque: false,
      barrierColor: Colors.black.withValues(alpha: 0.88),
      transitionDuration: const Duration(milliseconds: 520),
      reverseTransitionDuration: const Duration(milliseconds: 260),
      pageBuilder: (_, __, ___) => _ProfileCardPage(
        uid: uid,
        favorites: favorites,
        animeCount: animeCount,
        episodeCount: episodeCount,
      ),
      transitionsBuilder: (_, anim, __, child) {
        // Masuk: kartu berputar dari samping (seperti kartu dibalik).
        final t = CurvedAnimation(parent: anim, curve: Curves.easeOutCubic);
        return FadeTransition(
          opacity: t,
          child: AnimatedBuilder(
            animation: t,
            builder: (_, c) => Transform(
              alignment: Alignment.center,
              transform: Matrix4.identity()
                ..setEntry(3, 2, 0.0012)
                ..rotateY((1 - t.value) * -1.1)
                ..scale(0.85 + 0.15 * t.value),
              child: c,
            ),
            child: child,
          ),
        );
      },
    ),
  );
}

class _ProfileCardPage extends ConsumerStatefulWidget {
  const _ProfileCardPage({
    required this.uid,
    required this.favorites,
    required this.animeCount,
    required this.episodeCount,
  });

  final String uid;
  final List<FavoriteEntity> favorites;
  final int animeCount;
  final int episodeCount;

  @override
  ConsumerState<_ProfileCardPage> createState() => _ProfileCardPageState();
}

class _ProfileCardPageState extends ConsumerState<_ProfileCardPage> with TickerProviderStateMixin {
  static const MethodChannel _gallery = MethodChannel('wibuplay/gallery');
  final _cardKey = GlobalKey();
  bool _busy = false;

  /// Kilau hologram & putaran garis neon (berulang).
  late final AnimationController _fx = AnimationController(vsync: this, duration: const Duration(seconds: 6))..repeat();

  /// Kemiringan 3D mengikuti jari; kembali lurus saat dilepas.
  Offset _tilt = Offset.zero;
  late final AnimationController _spring = AnimationController(vsync: this, duration: const Duration(milliseconds: 600))
    ..addListener(() {
      final t = Curves.elasticOut.transform(_spring.value);
      setState(() => _tilt = Offset.lerp(_springFrom, Offset.zero, t)!);
    });
  Offset _springFrom = Offset.zero;

  @override
  void dispose() {
    _fx.dispose();
    _spring.dispose();
    super.dispose();
  }

  void _onPan(DragUpdateDetails d) {
    _spring.stop();
    setState(() {
      _tilt = Offset(
        (_tilt.dx + d.delta.dx / 260).clamp(-0.35, 0.35),
        (_tilt.dy + d.delta.dy / 260).clamp(-0.35, 0.35),
      );
    });
  }

  void _onPanEnd(DragEndDetails _) {
    _springFrom = _tilt;
    _spring.forward(from: 0);
  }

  /// Gambar yang tampil di kartu dimuat dulu supaya tidak tertangkap kosong.
  Future<void> _precache(List<String> urls) async {
    await Future.wait(urls.where((u) => u.isNotEmpty).map(
          (u) => precacheImage(CachedNetworkImageProvider(u, headers: netImageHeaders), context)
              .catchError((Object _) {}),
        ));
    await Future<void>.delayed(const Duration(milliseconds: 350));
  }

  String? _backdrop() {
    final profile = ref.read(chatProfileProvider(widget.uid)).valueOrNull;
    final premium = ref.read(premiumProvider(widget.uid)).valueOrNull ?? false;
    final wp = ref.read(bannerWallpaperProvider(widget.uid)).valueOrNull;
    final b = resolveProfileBanner(wallpaper: wp, premium: premium, customUrl: profile?.bannerUrl);
    if (b != null && b.isNotEmpty) return b;
    for (final f in widget.favorites) {
      if (f.posterUrl.isNotEmpty) return f.posterUrl;
    }
    return null;
  }

  Future<Uint8List?> _capture() async {
    final profile = ref.read(chatProfileProvider(widget.uid)).valueOrNull;
    final bd = _backdrop();
    await _precache([
      if (profile?.avatarUrl != null) profile!.avatarUrl!,
      if (bd != null) bd,
      for (final f in widget.favorites.take(3)) f.posterUrl,
    ]);
    if (!mounted) return null;
    final boundary = _cardKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
    if (boundary == null) return null;
    final image = await boundary.toImage(pixelRatio: 3);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    return data?.buffer.asUint8List();
  }

  String get _fileName => 'zenime-kartu-${DateTime.now().millisecondsSinceEpoch}.png';

  Future<void> _save() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final bytes = await _capture();
      if (bytes == null || !mounted) return;
      bool ok = false;
      try {
        ok = await _gallery.invokeMethod<bool>('saveImage', {'bytes': bytes, 'name': _fileName}) ?? false;
      } catch (_) {}
      if (!mounted) return;
      if (ok) {
        HapticFeedback.mediumImpact();
        showAppToast(context, 'Kartu tersimpan di Galeri (Pictures/Zenime)', kind: ToastKind.success);
      } else {
        // Android lama / gagal simpan: pakai lembar bagikan (bisa pilih simpan).
        await _shareBytes(bytes);
      }
    } catch (_) {
      if (mounted) showAppToast(context, 'Gagal membuat gambar kartu', kind: ToastKind.error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _share() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final bytes = await _capture();
      if (bytes != null && mounted) await _shareBytes(bytes);
    } catch (_) {
      if (mounted) showAppToast(context, 'Gagal membagikan kartu', kind: ToastKind.error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _shareBytes(Uint8List bytes) async {
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/$_fileName');
    await file.writeAsBytes(bytes, flush: true);
    final number = ref.read(chatProfileProvider(widget.uid)).valueOrNull?.userNumber;
    await Share.shareXFiles(
      [XFile(file.path, mimeType: 'image/png')],
      text: number == null ? 'Yuk nonton anime bareng di Zenime!' : 'Tambah aku di Zenime: ID #$number',
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        child: Column(
          children: [
            Row(
              children: [
                const SizedBox(width: 16),
                const Icon(Icons.threesixty_rounded, color: Colors.white54, size: 16),
                const SizedBox(width: 6),
                const Expanded(
                  child: Text('Geser kartu untuk memiringkan', style: TextStyle(color: Colors.white54, fontSize: 12)),
                ),
                IconButton(
                  onPressed: () => Navigator.of(context).maybePop(),
                  icon: const Icon(Icons.close_rounded, color: Colors.white),
                ),
              ],
            ),
            Expanded(
              child: Center(
                child: GestureDetector(
                  onPanUpdate: _onPan,
                  onPanEnd: _onPanEnd,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 18),
                    child: FittedBox(
                      child: AnimatedBuilder(
                        animation: _fx,
                        builder: (_, __) => Transform(
                          alignment: Alignment.center,
                          transform: Matrix4.identity()
                            ..setEntry(3, 2, 0.0014)
                            ..rotateX(-_tilt.dy)
                            ..rotateY(_tilt.dx),
                          child: RepaintBoundary(
                            key: _cardKey,
                            child: ProfileCollectCard(
                              uid: widget.uid,
                              favorites: widget.favorites,
                              animeCount: widget.animeCount,
                              episodeCount: widget.episodeCount,
                              fx: _fx.value,
                              // Kilau ikut bergeser saat kartu dimiringkan.
                              shine: (_tilt.dx + _tilt.dy) * 1.4,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _busy ? null : _save,
                      icon: const Icon(Icons.download_rounded),
                      label: const Text('Simpan'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white,
                        side: const BorderSide(color: Color(0x66FFFFFF)),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: const StadiumBorder(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(30),
                        gradient: const LinearGradient(colors: [AppColors.accentViolet, _magenta]),
                        boxShadow: [BoxShadow(color: AppColors.accentViolet.withValues(alpha: 0.4), blurRadius: 16)],
                      ),
                      child: FilledButton.icon(
                        onPressed: _busy ? null : _share,
                        icon: _busy
                            ? const SizedBox.square(
                                dimension: 18,
                                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                              )
                            : const Icon(Icons.share_rounded),
                        label: const Text('Bagikan'),
                        style: FilledButton.styleFrom(
                          backgroundColor: Colors.transparent,
                          shadowColor: Colors.transparent,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: const StadiumBorder(),
                        ),
                      ),
                    ),
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

/// Kartu pemain futuristik: bingkai neon berputar, kilau hologram, grid
/// HUD, banner terpotong miring, avatar + level, statistik kaca, 3 anime
/// favorit, dan kode batang dekoratif. Lebar tetap 340.
/// [fx] 0..1 = fase animasi (kilau & neon), [shine] = geser kilau dari kemiringan.
class ProfileCollectCard extends ConsumerWidget {
  const ProfileCollectCard({
    super.key,
    required this.uid,
    required this.favorites,
    required this.animeCount,
    required this.episodeCount,
    this.fx = 0.15,
    this.shine = 0,
  });

  final String uid;
  final List<FavoriteEntity> favorites;
  final int animeCount;
  final int episodeCount;
  final double fx;
  final double shine;

  static const double width = 340;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(chatProfileProvider(uid)).valueOrNull;
    final premium = ref.watch(premiumProvider(uid)).valueOrNull ?? false;
    final wp = ref.watch(bannerWallpaperProvider(uid)).valueOrNull;
    final clanTag = ref.watch(userClanTagProvider(uid)).valueOrNull;
    final name = (profile?.username ?? '').trim().isEmpty ? 'Pengguna Zenime' : profile!.username;
    final number = profile?.userNumber;

    String? backdrop = resolveProfileBanner(wallpaper: wp, premium: premium, customUrl: profile?.bannerUrl);
    if (backdrop == null || backdrop.isEmpty) {
      for (final f in favorites) {
        if (f.posterUrl.isNotEmpty) {
          backdrop = f.posterUrl;
          break;
        }
      }
    }

    // Warna utama kartu: rarity wallpaper -> emas Premium -> merah Zenime.
    final Color primary = wp != null
        ? wp.rarity.color
        : premium
            ? const Color(0xFFFFC94D)
            : AppColors.accentViolet;
    final String tier = wp != null
        ? wp.rarity.label.toUpperCase()
        : premium
            ? 'PREMIUM'
            : 'MEMBER';
    final favs = favorites.where((f) => f.posterUrl.isNotEmpty).take(3).toList();
    final serial = number == null ? 'ZNM-??????' : 'ZNM-${number.toString().padLeft(6, '0')}';

    return Container(
      width: width,
      padding: const EdgeInsets.all(2.5),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        // Bingkai neon yang berputar.
        gradient: SweepGradient(
          colors: [primary, _cyan, _magenta, primary],
          transform: GradientRotation(fx * 2 * math.pi),
        ),
        boxShadow: [
          BoxShadow(color: primary.withValues(alpha: 0.45), blurRadius: 28, spreadRadius: 1),
          BoxShadow(color: _cyan.withValues(alpha: 0.18), blurRadius: 40),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(25.5),
        child: Stack(
          children: [
            // -------------------------------------------- latar + grid HUD
            const Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Color(0xFF0A0E1A), Color(0xFF120A1F), Color(0xFF07121A)],
                  ),
                ),
              ),
            ),
            Positioned.fill(child: CustomPaint(painter: _GridPainter(color: _cyan.withValues(alpha: 0.05)))),
            // -------------------------------------------- banner miring
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              height: 168,
              child: ClipPath(
                clipper: _SlantClipper(),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    if (backdrop != null && backdrop.isNotEmpty)
                      NetImage(backdrop)
                    else
                      DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(colors: [primary.withValues(alpha: 0.5), _magenta.withValues(alpha: 0.3)]),
                        ),
                      ),
                    DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [Colors.black.withValues(alpha: 0.35), Colors.transparent, const Color(0xFF0A0E1A)],
                          stops: const [0, 0.4, 1],
                        ),
                      ),
                    ),
                    CustomPaint(painter: _ScanlinePainter()),
                  ],
                ),
              ),
            ),
            // -------------------------------------------- isi
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Kepala: logo + jenis kartu + nomor seri.
                  Row(
                    children: [
                      ShaderMask(
                        shaderCallback: (r) => const LinearGradient(colors: [Colors.white, _cyan]).createShader(r),
                        child: const Text(
                          'ZENIME',
                          style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w900, letterSpacing: 4),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          border: Border.all(color: _cyan.withValues(alpha: 0.7)),
                          borderRadius: BorderRadius.circular(4),
                          color: Colors.black.withValues(alpha: 0.35),
                        ),
                        child: const Text(
                          'PLAYER CARD',
                          style: TextStyle(color: _cyan, fontSize: 8.5, fontWeight: FontWeight.w800, letterSpacing: 1.5, fontFamily: _mono),
                        ),
                      ),
                      const Spacer(),
                      if (wp != null)
                        BannerRarityBadge(rarity: wp.rarity)
                      else
                        Text(
                          serial,
                          style: const TextStyle(color: Colors.white70, fontSize: 10, fontFamily: _mono, letterSpacing: 1),
                        ),
                    ],
                  ),
                  const SizedBox(height: 50),
                  // Avatar + level, dengan halo neon di belakangnya.
                  Stack(
                    alignment: Alignment.center,
                    children: [
                      Container(
                        width: 118,
                        height: 118,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(color: primary.withValues(alpha: 0.55), blurRadius: 34, spreadRadius: 2),
                          ],
                        ),
                      ),
                      ProfileHeroAvatar(
                        uid: uid,
                        url: profile?.avatarUrl,
                        seed: uid,
                        label: name,
                        showXpRing: true,
                        leading: ProfileAchievementBadges.topXpChip(ref, uid),
                        trailing: ProfileAchievementBadges.topGiverChip(ref, uid),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  // Nama bergradien + clan + centang.
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (clanTag != null && clanTag.isNotEmpty) ...[
                        ClanTagBadge(text: clanTag, nameTag: true, height: 20),
                        const SizedBox(width: 6),
                      ],
                      Flexible(
                        child: ShaderMask(
                          shaderCallback: (r) => LinearGradient(colors: [Colors.white, Color.lerp(Colors.white, primary, 0.55)!]).createShader(r),
                          child: Text(
                            name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w900, letterSpacing: 0.3),
                          ),
                        ),
                      ),
                      const SizedBox(width: 5),
                      UserCheckBadge(firebaseUid: uid, isPremium: premium, size: 15),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(20),
                      color: Colors.white.withValues(alpha: 0.06),
                      border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
                    ),
                    child: Text(
                      number == null ? 'ID —' : 'ID #$number',
                      style: const TextStyle(color: Colors.white70, fontSize: 11.5, fontFamily: _mono, letterSpacing: 1.2),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    alignment: WrapAlignment.center,
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      ProfileClanPill(uid: uid),
                      RoleBadge(firebaseUid: uid, height: 22, rounded: true),
                    ],
                  ),
                  const SizedBox(height: 14),
                  // Statistik: panel kaca dengan garis neon di atas.
                  Row(
                    children: [
                      _statTile('$animeCount', 'ANIME', primary),
                      const SizedBox(width: 8),
                      _statTile('$episodeCount', 'EPISODE', _cyan),
                      const SizedBox(width: 8),
                      _statTile('${favorites.length}', 'FAVORIT', _magenta),
                    ],
                  ),
                  if (favs.isNotEmpty) ...[
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        Container(width: 3, height: 12, color: primary),
                        const SizedBox(width: 6),
                        const Text(
                          'TOP FAVORIT',
                          style: TextStyle(color: Colors.white70, fontSize: 10.5, fontWeight: FontWeight.w800, letterSpacing: 2, fontFamily: _mono),
                        ),
                        const SizedBox(width: 8),
                        Expanded(child: Container(height: 1, color: Colors.white.withValues(alpha: 0.1))),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        for (var i = 0; i < 3; i++) ...[
                          if (i > 0) const SizedBox(width: 8),
                          Expanded(child: i < favs.length ? _poster(favs[i], i, primary) : const SizedBox()),
                        ],
                      ],
                    ),
                  ],
                  const SizedBox(height: 14),
                  // Kaki: tier + ajakan + kode batang.
                  Container(
                    padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      color: Colors.white.withValues(alpha: 0.04),
                      border: Border.all(color: primary.withValues(alpha: 0.35)),
                    ),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(6),
                            gradient: LinearGradient(colors: [primary, Color.lerp(primary, _magenta, 0.5)!]),
                          ),
                          child: Text(
                            tier,
                            style: const TextStyle(color: Colors.black, fontSize: 9.5, fontWeight: FontWeight.w900, letterSpacing: 1),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            number == null ? 'Nonton bareng di Zenime' : 'Tambah aku · ID #$number',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(color: Colors.white, fontSize: 11.5, fontWeight: FontWeight.w700),
                          ),
                        ),
                        SizedBox(
                          width: 64,
                          height: 22,
                          child: CustomPaint(painter: _BarcodePainter(seed: uid, color: Colors.white70)),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            // -------------------------------------------- sudut HUD
            Positioned.fill(child: IgnorePointer(child: CustomPaint(painter: _CornerPainter(color: _cyan.withValues(alpha: 0.8))))),
            // -------------------------------------------- kilau hologram
            Positioned.fill(
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment(-1.6 + (fx * 3.2) + shine, -1),
                      end: Alignment(-0.6 + (fx * 3.2) + shine, 1),
                      colors: [
                        Colors.white.withValues(alpha: 0),
                        _cyan.withValues(alpha: 0.10),
                        Colors.white.withValues(alpha: 0.16),
                        _magenta.withValues(alpha: 0.10),
                        Colors.white.withValues(alpha: 0),
                      ],
                      stops: const [0.0, 0.35, 0.5, 0.65, 1.0],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  static Widget _statTile(String value, String label, Color accent) => Expanded(
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 9),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            color: Colors.white.withValues(alpha: 0.05),
            border: Border(
              top: BorderSide(color: accent, width: 2),
              left: BorderSide(color: Colors.white.withValues(alpha: 0.06)),
              right: BorderSide(color: Colors.white.withValues(alpha: 0.06)),
              bottom: BorderSide(color: Colors.white.withValues(alpha: 0.06)),
            ),
          ),
          child: Column(
            children: [
              Text(value, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w900)),
              const SizedBox(height: 1),
              Text(
                label,
                style: TextStyle(color: accent.withValues(alpha: 0.9), fontSize: 9, fontWeight: FontWeight.w800, letterSpacing: 1.5, fontFamily: _mono),
              ),
            ],
          ),
        ),
      );

  static Widget _poster(FavoriteEntity f, int i, Color accent) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(1.5),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(11),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [accent, _cyan.withValues(alpha: 0.6)],
              ),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(9.5),
              child: AspectRatio(
                aspectRatio: 2 / 3,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    NetImage(f.posterUrl),
                    Positioned(
                      left: 0,
                      top: 0,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                        color: Colors.black.withValues(alpha: 0.65),
                        child: Text(
                          '0${i + 1}',
                          style: TextStyle(color: i == 0 ? accent : Colors.white, fontSize: 10, fontWeight: FontWeight.w900, fontFamily: _mono),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            f.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: Colors.white70, fontSize: 10.5, fontWeight: FontWeight.w600),
          ),
        ],
      );
}

// ======================================================================= lukisan

/// Banner dengan potongan miring di bawah.
class _SlantClipper extends CustomClipper<Path> {
  @override
  Path getClip(Size s) => Path()
    ..lineTo(s.width, 0)
    ..lineTo(s.width, s.height - 34)
    ..lineTo(0, s.height)
    ..close();

  @override
  bool shouldReclip(covariant CustomClipper<Path> oldClipper) => false;
}

class _GridPainter extends CustomPainter {
  _GridPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = color
      ..strokeWidth = 1;
    const step = 18.0;
    for (double x = 0; x <= size.width; x += step) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), p);
    }
    for (double y = 0; y <= size.height; y += step) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), p);
    }
  }

  @override
  bool shouldRepaint(covariant _GridPainter old) => old.color != color;
}

class _ScanlinePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()..color = Colors.black.withValues(alpha: 0.12);
    for (double y = 0; y < size.height; y += 3) {
      canvas.drawRect(Rect.fromLTWH(0, y, size.width, 1), p);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Siku-siku HUD di keempat sudut kartu.
class _CornerPainter extends CustomPainter {
  _CornerPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = color
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    const m = 10.0;
    const l = 16.0;
    final w = size.width;
    final h = size.height;
    void corner(Offset a, Offset b, Offset c) => canvas.drawPath(
          Path()
            ..moveTo(a.dx, a.dy)
            ..lineTo(b.dx, b.dy)
            ..lineTo(c.dx, c.dy),
          p,
        );
    corner(const Offset(m, m + l), const Offset(m, m), const Offset(m + l, m));
    corner(Offset(w - m - l, m), Offset(w - m, m), Offset(w - m, m + l));
    corner(Offset(m, h - m - l), Offset(m, h - m), Offset(m + l, h - m));
    corner(Offset(w - m - l, h - m), Offset(w - m, h - m), Offset(w - m, h - m - l));
  }

  @override
  bool shouldRepaint(covariant _CornerPainter old) => old.color != color;
}

/// Kode batang dekoratif (pola dari uid, jadi tiap orang beda).
class _BarcodePainter extends CustomPainter {
  _BarcodePainter({required this.seed, required this.color});

  final String seed;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()..color = color;
    var h = seed.hashCode & 0x7fffffff;
    double x = 0;
    while (x < size.width) {
      h = (h * 1103515245 + 12345) & 0x7fffffff;
      final w = 1.0 + (h % 3);
      final gap = 1.0 + ((h >> 3) % 3);
      canvas.drawRect(Rect.fromLTWH(x, 0, math.min(w, size.width - x), size.height), p);
      x += w + gap;
    }
  }

  @override
  bool shouldRepaint(covariant _BarcodePainter old) => old.seed != seed || old.color != color;
}

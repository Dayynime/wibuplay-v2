import 'dart:io';
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

/// Buka kartu profil (gaya kartu koleksi) yang bisa disimpan / dibagikan.
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
      barrierColor: Colors.black.withValues(alpha: 0.85),
      transitionDuration: const Duration(milliseconds: 280),
      pageBuilder: (_, __, ___) => _ProfileCardPage(
        uid: uid,
        favorites: favorites,
        animeCount: animeCount,
        episodeCount: episodeCount,
      ),
      transitionsBuilder: (_, anim, __, child) => FadeTransition(
        opacity: anim,
        child: ScaleTransition(
          scale: Tween(begin: 0.92, end: 1.0).animate(CurvedAnimation(parent: anim, curve: Curves.easeOutBack)),
          child: child,
        ),
      ),
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

class _ProfileCardPageState extends ConsumerState<_ProfileCardPage> {
  static const MethodChannel _gallery = MethodChannel('wibuplay/gallery');
  final _cardKey = GlobalKey();
  bool _busy = false;

  /// Gambar yang tampil di kartu dimuat dulu supaya tidak tertangkap kosong.
  Future<void> _precache(List<String> urls) async {
    await Future.wait(urls.where((u) => u.isNotEmpty).map(
          (u) => precacheImage(CachedNetworkImageProvider(u, headers: netImageHeaders), context)
              .catchError((Object _) {}),
        ));
    await Future<void>.delayed(const Duration(milliseconds: 350));
  }

  Future<Uint8List?> _capture() async {
    final profile = ref.read(chatProfileProvider(widget.uid)).valueOrNull;
    await _precache([
      if (profile?.avatarUrl != null) profile!.avatarUrl!,
      if (_backdrop() != null) _backdrop()!,
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
            Align(
              alignment: Alignment.centerRight,
              child: IconButton(
                onPressed: () => Navigator.of(context).maybePop(),
                icon: const Icon(Icons.close_rounded, color: Colors.white),
              ),
            ),
            Expanded(
              child: Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: FittedBox(
                    child: RepaintBoundary(
                      key: _cardKey,
                      child: ProfileCollectCard(
                        uid: widget.uid,
                        favorites: widget.favorites,
                        animeCount: widget.animeCount,
                        episodeCount: widget.episodeCount,
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
                        backgroundColor: AppColors.accentViolet,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: const StadiumBorder(),
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

/// Kartu profil gaya kartu koleksi: banner, avatar + level, nama, clan,
/// role, statistik, dan 3 anime favorit. Ukuran tetap (340 lebar).
class ProfileCollectCard extends ConsumerWidget {
  const ProfileCollectCard({
    super.key,
    required this.uid,
    required this.favorites,
    required this.animeCount,
    required this.episodeCount,
  });

  final String uid;
  final List<FavoriteEntity> favorites;
  final int animeCount;
  final int episodeCount;

  static const double width = 340;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(chatProfileProvider(uid)).valueOrNull;
    final premium = ref.watch(premiumProvider(uid)).valueOrNull ?? false;
    final wp = ref.watch(bannerWallpaperProvider(uid)).valueOrNull;
    final clanTag = ref.watch(userClanTagProvider(uid)).valueOrNull;
    final name = (profile?.username ?? '').trim().isEmpty ? 'Pengguna Zenime' : profile!.username;

    String? backdrop = resolveProfileBanner(wallpaper: wp, premium: premium, customUrl: profile?.bannerUrl);
    if (backdrop == null || backdrop.isEmpty) {
      for (final f in favorites) {
        if (f.posterUrl.isNotEmpty) {
          backdrop = f.posterUrl;
          break;
        }
      }
    }

    // Bingkai kartu: warna rarity wallpaper, emas untuk Premium, ungu biasa.
    final List<Color> frame = wp != null
        ? [wp.rarity.color, wp.rarity.color.withValues(alpha: 0.4), wp.rarity.color]
        : premium
            ? const [Color(0xFFFFE08A), Color(0xFFB8860B), Color(0xFFFFE08A)]
            : [AppColors.accentVioletLight, AppColors.accentViolet, AppColors.accentVioletLight];
    final favs = favorites.where((f) => f.posterUrl.isNotEmpty).take(3).toList();

    return Container(
      width: width,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(26),
        gradient: LinearGradient(colors: frame, begin: Alignment.topLeft, end: Alignment.bottomRight),
        boxShadow: [BoxShadow(color: frame.first.withValues(alpha: 0.35), blurRadius: 24)],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(23),
        child: ColoredBox(
          color: AppColors.backgroundDark,
          child: Stack(
            children: [
              // ---------------------------------------------------- banner
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                height: 150,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    if (backdrop != null && backdrop.isNotEmpty)
                      NetImage(backdrop)
                    else
                      const ColoredBox(color: AppColors.surfaceVariantDark),
                    const DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [Color(0x33000000), Color(0x00000000), AppColors.backgroundDark],
                          stops: [0, 0.45, 1],
                        ),
                      ),
                    ),
                    const Positioned(
                      top: 12,
                      left: 14,
                      child: Text(
                        'ZENIME',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 3,
                        ),
                      ),
                    ),
                    if (wp != null)
                      Positioned(top: 10, right: 12, child: BannerRarityBadge(rarity: wp.rarity)),
                  ],
                ),
              ),
              // ---------------------------------------------------- isi
              Padding(
                padding: const EdgeInsets.only(top: 78, bottom: 16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ProfileHeroAvatar(
                      uid: uid,
                      url: profile?.avatarUrl,
                      seed: uid,
                      label: name,
                      showXpRing: true,
                      leading: ProfileAchievementBadges.topXpChip(ref, uid),
                      trailing: ProfileAchievementBadges.topGiverChip(ref, uid),
                    ),
                    const SizedBox(height: 10),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (clanTag != null && clanTag.isNotEmpty) ...[
                            ClanTagBadge(text: clanTag, nameTag: true, height: 20),
                            const SizedBox(width: 6),
                          ],
                          Flexible(
                            child: Text(
                              name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(color: AppColors.textWhite, fontSize: 21, fontWeight: FontWeight.w800),
                            ),
                          ),
                          const SizedBox(width: 5),
                          UserCheckBadge(firebaseUid: uid, isPremium: premium, size: 15),
                        ],
                      ),
                    ),
                    if (profile?.userNumber != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          'ID #${profile!.userNumber}',
                          style: const TextStyle(color: AppColors.textSecondary, fontSize: 12, letterSpacing: 1),
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
                    // ---------------------------------------------- statistik
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Row(
                        children: [
                          _stat('$animeCount', 'Anime'),
                          _divider(),
                          _stat('$episodeCount', 'Episode'),
                          _divider(),
                          _stat('${favorites.length}', 'Favorit'),
                        ],
                      ),
                    ),
                    if (favs.isNotEmpty) ...[
                      const SizedBox(height: 16),
                      const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 16),
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            'ANIME FAVORIT',
                            style: TextStyle(
                              color: AppColors.textMuted,
                              fontSize: 10.5,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 1.5,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            for (var i = 0; i < 3; i++) ...[
                              if (i > 0) const SizedBox(width: 8),
                              Expanded(child: i < favs.length ? _poster(favs[i]) : const SizedBox()),
                            ],
                          ],
                        ),
                      ),
                    ],
                    const SizedBox(height: 16),
                    Container(
                      margin: const EdgeInsets.symmetric(horizontal: 16),
                      padding: const EdgeInsets.symmetric(vertical: 9),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        color: frame.first.withValues(alpha: 0.12),
                        border: Border.all(color: frame.first.withValues(alpha: 0.35)),
                      ),
                      child: Center(
                        child: Text(
                          profile?.userNumber != null
                              ? 'Tambah aku di Zenime · ID #${profile!.userNumber}'
                              : 'Nonton anime bareng di Zenime',
                          style: const TextStyle(color: AppColors.textWhite, fontSize: 12, fontWeight: FontWeight.w700),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static Widget _stat(String value, String label) => Expanded(
        child: Column(
          children: [
            Text(value, style: const TextStyle(color: AppColors.textWhite, fontSize: 17, fontWeight: FontWeight.w800)),
            Text(label, style: const TextStyle(color: AppColors.textMuted, fontSize: 11)),
          ],
        ),
      );

  static Widget _divider() => Container(width: 1, height: 26, color: const Color(0x22FFFFFF));

  static Widget _poster(FavoriteEntity f) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: AspectRatio(aspectRatio: 2 / 3, child: NetImage(f.posterUrl)),
          ),
          const SizedBox(height: 4),
          Text(
            f.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: AppColors.textSecondary, fontSize: 10.5, fontWeight: FontWeight.w600),
          ),
        ],
      );
}

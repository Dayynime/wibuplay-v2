import 'dart:math' as math;

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/build_flags.dart';
import '../../../core/firebase_config.dart';
import '../../../core/theme/app_colors.dart';
import '../../../data/models/account_models.dart';
import '../../../data/models/chat_models.dart';
import '../../../providers.dart';
import '../../app_routes.dart';
import '../../components/net_image.dart';
import '../../components/role_badges.dart';
import '../admin/admin_screen.dart';
import '../auth/login_screen.dart';
import '../chat/chat_screen.dart';
import '../download/downloads_screen.dart';
import '../safety/safety_actions.dart';
import '../friends/friends_screen.dart';
import '../wallpaper/wallpaper_screen.dart';
import 'profile_screen.dart' show ProfileAvatar, showEditProfileSheet;
import '../../glass/glass.dart';

/// Halaman Pengaturan (dibuka dari ikon gear di pojok kanan atas Profil).
///
/// Susunan:
///   1. Kartu akun (banner, avatar, nama) + 3 stat cepat: Premium, ZCoin, Teman.
///   2. Pintasan: Wallpaper, Chat, Download, (Admin).
///   3. Grup Preferensi, Penyimpanan, Privasi.
///   4. Keluar / Hapus Akun, lalu info aplikasi kecil di bawah.
///
/// Semua bagian masuk dengan animasi bertahap (fade + geser naik), baris
/// mengecil sedikit saat ditekan, toggle & pemilih kualitas beranimasi.
class ProfileSettingsScreen extends ConsumerStatefulWidget {
  const ProfileSettingsScreen({super.key});

  @override
  ConsumerState<ProfileSettingsScreen> createState() => _ProfileSettingsScreenState();
}

class _ProfileSettingsScreenState extends ConsumerState<ProfileSettingsScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _intro = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  );

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (MediaQuery.of(context).disableAnimations) {
        _intro.value = 1;
      } else {
        _intro.forward();
      }
    });
  }

  @override
  void dispose() {
    _intro.dispose();
    super.dispose();
  }

  /// Bagian ke-[i] muncul sedikit setelah bagian sebelumnya.
  Widget _reveal(int i, Widget child) {
    final double start = math.min(i * 0.08, 0.6);
    final anim = CurvedAnimation(
      parent: _intro,
      curve: Interval(start, math.min(start + 0.45, 1.0), curve: Curves.easeOutCubic),
    );
    return FadeTransition(
      opacity: anim,
      child: SlideTransition(
        position: Tween<Offset>(begin: const Offset(0, 0.08), end: Offset.zero).animate(anim),
        child: child,
      ),
    );
  }

  // ---------------------------------------------------------------- actions

  Future<bool> _openLogin() async {
    final ok = await Navigator.of(context).push<bool>(fadeRoute(const LoginScreen()));
    return ok == true;
  }

  Future<void> _openChat() async {
    if (!FirebaseConfig.ready) {
      await _openLogin();
      return;
    }
    if (ref.read(authRepositoryProvider).currentUser == null) {
      final ok = await _openLogin();
      if (!ok || !mounted) return;
    }
    if (!mounted) return;
    await Navigator.of(context).push<void>(fadeRoute(const ChatScreen()));
  }

  void _push(Widget page) => Navigator.of(context).push<void>(fadeRoute(page));

  Future<void> _confirmSignOut() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surfaceDark,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        title: const Text('Keluar dari akun?', style: TextStyle(color: AppColors.textWhite)),
        content: const Text(
          'Kamu perlu masuk lagi untuk memakai Chat, Premium, dan fitur akun lainnya.',
          style: TextStyle(color: AppColors.textSecondary, height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Batal', style: TextStyle(color: AppColors.textSecondary)),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.accentViolet,
              shape: const StadiumBorder(),
            ),
            child: const Text('Keluar'),
          ),
        ],
      ),
    );
    if (confirmed == true) await ref.read(authRepositoryProvider).signOut();
  }

  /// Cache gambar di memori benar-benar dikosongkan (cache disk cover tidak disentuh).
  void _clearCache() {
    final cache = PaintingBinding.instance.imageCache;
    cache.clear();
    cache.clearLiveImages();
  }

  // ---------------------------------------------------------------- helpers

  String _displayName(User? user) {
    final name = user?.displayName;
    if (name != null && name.trim().isNotEmpty) return name.trim();
    final email = user?.email;
    if (email != null && email.contains('@')) return email.substring(0, email.indexOf('@'));
    return user == null ? 'Wibu Sejati' : 'Pengguna';
  }

  String _resolvedName(User? user, ChatProfile? profile, bool loading) {
    final zenime = profile?.username.trim() ?? '';
    if (zenime.isNotEmpty) return zenime;
    if (loading) return 'Pengguna Zenime';
    return _displayName(user);
  }

  static const List<String> _bulan = [
    'Jan', 'Feb', 'Mar', 'Apr', 'Mei', 'Jun', 'Jul', 'Agu', 'Sep', 'Okt', 'Nov', 'Des',
  ];

  /// Teks singkat sisa Premium untuk stat tile ("1171 hari", "Hari ini").
  String _premiumShort(PremiumStatus? p) {
    if (p?.isPremium != true) return 'Belum aktif';
    final at = DateTime.tryParse(p?.expiresAt ?? '')?.toLocal();
    if (at == null) return 'Aktif';
    if (at.isBefore(DateTime.now())) return 'Berakhir';
    final d = at.difference(DateTime.now()).inDays;
    return d == 0 ? 'Hari ini' : '$d hari';
  }

  String? _premiumUntil(PremiumStatus? p) {
    if (p?.isPremium != true) return null;
    final at = DateTime.tryParse(p?.expiresAt ?? '')?.toLocal();
    if (at == null) return null;
    return 's/d ${at.day} ${_bulan[at.month - 1]} ${at.year}';
  }

  // ------------------------------------------------------------------ build

  @override
  Widget build(BuildContext context) {
    final authUser = ref.watch(authUserProvider).valueOrNull;
    final user = (authUser != null && FirebaseConfig.ready) ? authUser : null;
    ChatProfile? profile;
    var profileLoading = false;
    PremiumStatus? premium;
    int? coins;
    if (user != null) {
      final async = ref.watch(chatProfileProvider(user.uid));
      profile = async.valueOrNull;
      profileLoading = async.isLoading;
      premium = ref.watch(premiumStatusProvider(user.uid)).valueOrNull;
      coins = ref.watch(coinBalanceProvider(user.uid)).valueOrNull;
    }
    // Punya role (developer/admin/moderator)? Cuma buat memunculkan pintasan
    // Panel Admin; role dicek ulang di server saat panelnya dibuka.
    final isStaff =
        user != null && ref.watch(roleInfoProvider(user.uid)).valueOrNull?.role.isStaff == true;
    final downloadCount = ref.watch(localStoreProvider.select((s) => s.downloads.length));
    final incomingRequests =
        user == null ? 0 : (ref.watch(incomingFriendRequestsProvider).valueOrNull ?? 0);
    final store = ref.watch(localStoreProvider);
    final isPremium = premium?.isPremium == true;

    final name = user == null ? '' : _resolvedName(user, profile, profileLoading);
    final avatar = user == null
        ? null
        : ((profile?.avatarUrl ?? '').isNotEmpty ? profile!.avatarUrl : user.photoURL);

    void editProfile() {
      if (user == null) return;
      showEditProfileSheet(
        context,
        user: user,
        profile: profile,
        fallbackName: name,
        fallbackAvatar: avatar,
        premium: isPremium,
      );
    }

    var i = 0;
    final sections = <Widget>[
      // ---------------------------------------------------------- Akun
      _reveal(
        i++,
        user == null
            ? _GuestHero(onLogin: _openLogin)
            : _AccountHero(
                uid: user.uid,
                name: name,
                email: user.email ?? '',
                avatarUrl: avatar,
                bannerUrl: isPremium ? profile?.bannerUrl : null,
                premium: isPremium,
                onEdit: editProfile,
                stats: [
                  _StatData(
                    icon: Icons.workspace_premium_rounded,
                    label: 'Premium',
                    value: _premiumShort(premium),
                    hint: _premiumUntil(premium),
                    highlight: isPremium,
                    onTap: () => openPremium(context),
                  ),
                  _StatData(
                    asset: 'assets/images/ic_zcoin_badge.png',
                    icon: Icons.monetization_on_outlined,
                    label: 'ZCoin',
                    count: coins,
                    value: coins == null ? '—' : null,
                    hint: 'Top up',
                    onTap: () => openCoin(context),
                  ),
                  _StatData(
                    icon: Icons.people_alt_rounded,
                    label: 'Teman',
                    value: incomingRequests > 0 ? '$incomingRequests baru' : 'Lihat',
                    hint: incomingRequests > 0 ? 'Permintaan' : 'Daftar teman',
                    badge: incomingRequests,
                    onTap: () => _push(const FriendsScreen()),
                  ),
                ],
              ),
      ),
      const SizedBox(height: 18),

      // ------------------------------------------------------ Pintasan
      _reveal(
        i++,
        _QuickActions(
          items: [
            _QuickItem(
              icon: Icons.wallpaper_rounded,
              label: 'Wallpaper',
              colors: const [Color(0xFFE4344A), Color(0xFFFF7A59)],
              onTap: () => _push(const WallpaperScreen()),
            ),
            _QuickItem(
              icon: Icons.forum_rounded,
              label: 'Chat Global',
              colors: const [Color(0xFF6366F1), Color(0xFF8B5CF6)],
              onTap: _openChat,
            ),
            _QuickItem(
              icon: Icons.download_rounded,
              label: 'Download',
              colors: const [Color(0xFF0EA5E9), Color(0xFF22D3EE)],
              badge: downloadCount,
              onTap: () => _push(const DownloadsScreen()),
            ),
            if (isStaff)
              _QuickItem(
                icon: Icons.shield_rounded,
                label: 'Admin',
                colors: const [Color(0xFFF59E0B), Color(0xFFF97316)],
                onTap: () => _push(const AdminScreen()),
              ),
          ],
        ),
      ),
      const SizedBox(height: 26),

      // ---------------------------------------------------- Preferensi
      _reveal(
        i++,
        _Section(
          label: 'Preferensi',
          children: [
            Consumer(
              builder: (context, ref, _) {
                final glass = ref.watch(glassSettingsProvider);
                return _SettingsRow(
                  icon: Icons.auto_awesome_rounded,
                  title: 'Liquid Glass',
                  subtitle: glass.enabled ? 'Efek kaca aktif' : 'Efek kaca mati',
                  trailing: _AnimatedToggle(
                    value: glass.enabled,
                    onChanged: (v) => ref.read(glassSettingsProvider).setEnabled(v),
                  ),
                  onTap: () => ref.read(glassSettingsProvider).setEnabled(!glass.enabled),
                );
              },
            ),
            _QualityRow(
              value: store.defaultQuality,
              onChanged: (q) => ref.read(localStoreProvider).setDefaultQuality(q),
            ),
            _SettingsRow(
              icon: Icons.fast_forward_rounded,
              title: 'Lewati Intro',
              subtitle: 'Lompat ke detik 90 saat mulai dari awal',
              trailing: _AnimatedToggle(
                value: store.autoSkipIntro,
                onChanged: (v) => ref.read(localStoreProvider).setAutoSkipIntro(v),
              ),
              onTap: () => ref.read(localStoreProvider).setAutoSkipIntro(!store.autoSkipIntro),
            ),
            _SettingsRow(
              icon: Icons.skip_next_rounded,
              title: 'Auto-Lanjut Episode',
              subtitle: 'Putar episode berikutnya saat outro',
              trailing: _AnimatedToggle(
                value: store.autoSkipOutro,
                onChanged: (v) => ref.read(localStoreProvider).setAutoSkipOutro(v),
              ),
              onTap: () => ref.read(localStoreProvider).setAutoSkipOutro(!store.autoSkipOutro),
            ),
          ],
        ),
      ),
      const SizedBox(height: 22),

      // --------------------------------------------------- Penyimpanan
      _reveal(
        i++,
        _Section(
          label: 'Penyimpanan',
          children: [
            _SettingsRow(
              icon: Icons.download_done_rounded,
              title: 'Download',
              subtitle: downloadCount == 0
                  ? 'Nonton offline · khusus Premium'
                  : '$downloadCount episode tersimpan',
              onTap: () => _push(const DownloadsScreen()),
            ),
            _CacheRow(onClear: _clearCache),
          ],
        ),
      ),
      const SizedBox(height: 22),

      // ------------------------------------------------------- Privasi
      _reveal(
        i++,
        _Section(
          label: 'Privasi & Keamanan',
          children: [
            if (user != null)
              _SettingsRow(
                icon: Icons.block_rounded,
                title: 'Pengguna Diblokir',
                onTap: () => _push(const BlockedUsersScreen()),
              ),
            _SettingsRow(
              icon: Icons.privacy_tip_outlined,
              title: 'Kebijakan Privasi',
              external: true,
              onTap: () => launchUrl(
                Uri.parse(BuildFlags.privacyUrl),
                mode: LaunchMode.externalApplication,
              ),
            ),
            _SettingsRow(
              icon: Icons.gavel_rounded,
              title: 'Ketentuan Layanan',
              external: true,
              onTap: () => launchUrl(
                Uri.parse(BuildFlags.termsUrl),
                mode: LaunchMode.externalApplication,
              ),
            ),
          ],
        ),
      ),

      // ---------------------------------------------------- Akun (aksi)
      if (user != null) ...[
        const SizedBox(height: 22),
        _reveal(
          i++,
          _Section(
            children: [
              _SettingsRow(
                icon: Icons.logout_rounded,
                title: 'Keluar',
                danger: true,
                showChevron: false,
                onTap: _confirmSignOut,
              ),
              _SettingsRow(
                icon: Icons.person_remove_outlined,
                title: 'Hapus Akun',
                subtitle: 'Permanen, semua data ikut terhapus',
                danger: true,
                onTap: () => startDeleteAccount(context, ref),
              ),
            ],
          ),
        ),
      ],

      const SizedBox(height: 30),
      _reveal(i++, const _AppFooter()),
    ];

    return GlassScaffold(
      backgroundColor: AppColors.backgroundDark,
      appBar: GlassAppBar(
        backgroundColor: AppColors.backgroundDark,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          onPressed: () => Navigator.of(context).maybePop(),
          tooltip: 'Kembali',
          icon: const Icon(Icons.arrow_back_rounded, color: AppColors.textWhite),
        ),
        title: const Text(
          'Pengaturan',
          style: TextStyle(
            color: AppColors.textWhite,
            fontSize: 18,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      body: ListView(
        physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
        padding: EdgeInsets.fromLTRB(16, 8, 16, 32 + MediaQuery.paddingOf(context).bottom),
        children: sections,
      ),
    );
  }
}

// =============================================================================
// Kartu akun
// =============================================================================

class _AccountHero extends StatelessWidget {
  const _AccountHero({
    required this.uid,
    required this.name,
    required this.email,
    required this.avatarUrl,
    required this.bannerUrl,
    required this.premium,
    required this.onEdit,
    required this.stats,
  });

  final String uid;
  final String name;
  final String email;
  final String? avatarUrl;
  final String? bannerUrl;
  final bool premium;
  final VoidCallback onEdit;
  final List<_StatData> stats;

  @override
  Widget build(BuildContext context) {
    final hasBanner = bannerUrl != null && bannerUrl!.isNotEmpty;
    return ClipRRect(
      borderRadius: BorderRadius.circular(26),
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(26),
          border: Border.all(color: Colors.white.withValues(alpha: 0.07)),
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF2A1520), AppColors.surfaceCard, AppColors.surfaceDark],
            stops: [0, 0.55, 1],
          ),
        ),
        child: Stack(
          children: [
            // Latar: banner Premium, atau cahaya crimson lembut.
            if (hasBanner)
              Positioned.fill(
                child: Opacity(opacity: 0.55, child: NetImage(bannerUrl!)),
              )
            else ...[
              const Positioned(top: -60, right: -40, child: _GlowOrb(size: 180, alpha: 0.30)),
              const Positioned(bottom: -70, left: -50, child: _GlowOrb(size: 160, alpha: 0.12)),
            ],
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      AppColors.backgroundDark.withValues(alpha: hasBanner ? 0.25 : 0),
                      AppColors.backgroundDark.withValues(alpha: hasBanner ? 0.92 : 0.35),
                    ],
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 18, 16, 14),
              child: Column(
                children: [
                  Row(
                    children: [
                      ProfileAvatar(
                        url: avatarUrl,
                        seed: uid,
                        label: name,
                        size: 58,
                        frameUid: uid,
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Flexible(
                                  child: Text(
                                    name,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      color: AppColors.textWhite,
                                      fontSize: 18,
                                      fontWeight: FontWeight.w800,
                                      letterSpacing: -0.2,
                                    ),
                                  ),
                                ),
                                if (premium) ...[
                                  const SizedBox(width: 6),
                                  const _PremiumPill(),
                                ],
                              ],
                            ),
                            const SizedBox(height: 3),
                            Text(
                              email,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: AppColors.textWhite.withValues(alpha: 0.55),
                                fontSize: 12.5,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      _Pressable(
                        onTap: onEdit,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(100),
                            border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.edit_rounded, size: 14, color: AppColors.textWhite),
                              SizedBox(width: 5),
                              Text(
                                'Edit',
                                style: TextStyle(
                                  color: AppColors.textWhite,
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      for (var k = 0; k < stats.length; k++) ...[
                        if (k > 0) const SizedBox(width: 8),
                        Expanded(child: _StatTile(data: stats[k])),
                      ],
                    ],
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

class _GuestHero extends StatelessWidget {
  const _GuestHero({required this.onLogin});

  final Future<bool> Function() onLogin;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(26),
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(26),
          border: Border.all(color: Colors.white.withValues(alpha: 0.07)),
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF2A1520), AppColors.surfaceCard],
          ),
        ),
        child: Stack(
          children: [
            const Positioned(top: -60, right: -40, child: _GlowOrb(size: 180, alpha: 0.30)),
            Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: AppColors.accentViolet.withValues(alpha: 0.16),
                      borderRadius: BorderRadius.circular(15),
                    ),
                    child: const Icon(Icons.person_rounded,
                        color: AppColors.accentVioletLight, size: 26),
                  ),
                  const SizedBox(height: 14),
                  const Text(
                    'Masuk ke Zenime',
                    style: TextStyle(
                      color: AppColors.textWhite,
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Simpan progres, ngobrol di Chat, dan buka fitur Premium.',
                    style: TextStyle(
                      color: AppColors.textWhite.withValues(alpha: 0.6),
                      fontSize: 13,
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 16),
                  _Pressable(
                    onTap: onLogin,
                    child: Container(
                      height: 46,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(100),
                        gradient: const LinearGradient(
                          colors: [AppColors.accentViolet, AppColors.accentVioletLight],
                        ),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.login_rounded, size: 18, color: Colors.white),
                          SizedBox(width: 8),
                          Text(
                            'Masuk',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                              fontSize: 14.5,
                            ),
                          ),
                        ],
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

class _GlowOrb extends StatelessWidget {
  const _GlowOrb({required this.size, required this.alpha});

  final double size;
  final double alpha;

  @override
  Widget build(BuildContext context) => IgnorePointer(
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: RadialGradient(
              colors: [
                AppColors.accentViolet.withValues(alpha: alpha),
                AppColors.accentViolet.withValues(alpha: 0),
              ],
            ),
          ),
        ),
      );
}

class _PremiumPill extends StatelessWidget {
  const _PremiumPill();

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(100),
          gradient: const LinearGradient(colors: [Color(0xFFF7C35F), Color(0xFFE89A2C)]),
        ),
        child: const Text(
          'PRO',
          style: TextStyle(
            color: Color(0xFF3A2200),
            fontSize: 9.5,
            fontWeight: FontWeight.w900,
            letterSpacing: 0.6,
          ),
        ),
      );
}

class _StatData {
  const _StatData({
    required this.icon,
    required this.label,
    required this.onTap,
    this.value,
    this.count,
    this.hint,
    this.asset,
    this.badge = 0,
    this.highlight = false,
  });

  final IconData icon;
  final String label;
  final String? value;

  /// Kalau diisi, angka ini dianimasikan naik (dipakai saldo ZCoin).
  final int? count;
  final String? hint;
  final String? asset;
  final int badge;
  final bool highlight;
  final VoidCallback onTap;
}

class _StatTile extends StatelessWidget {
  const _StatTile({required this.data});

  final _StatData data;

  static String _fmt(int n) {
    final s = n.toString();
    final b = StringBuffer();
    for (var i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) b.write('.');
      b.write(s[i]);
    }
    return b.toString();
  }

  @override
  Widget build(BuildContext context) {
    final accent = data.highlight ? const Color(0xFFF7C35F) : AppColors.accentVioletLight;
    final icon = data.asset != null
        ? ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: Image.asset(
              data.asset!,
              width: 18,
              height: 18,
              errorBuilder: (_, __, ___) => Icon(data.icon, size: 16, color: accent),
            ),
          )
        : Icon(data.icon, size: 16, color: accent);

    const valueStyle = TextStyle(
      color: AppColors.textWhite,
      fontSize: 14.5,
      fontWeight: FontWeight.w800,
      letterSpacing: -0.2,
    );

    return _Pressable(
      onTap: data.onTap,
      child: Container(
        padding: const EdgeInsets.fromLTRB(11, 10, 8, 10),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.22),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: data.highlight
                ? const Color(0xFFF7C35F).withValues(alpha: 0.28)
                : Colors.white.withValues(alpha: 0.07),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                icon,
                const Spacer(),
                if (data.badge > 0) const _PulseDot(),
              ],
            ),
            const SizedBox(height: 10),
            if (data.count != null)
              TweenAnimationBuilder<double>(
                tween: Tween(begin: 0, end: data.count!.toDouble()),
                duration: const Duration(milliseconds: 900),
                curve: Curves.easeOutCubic,
                builder: (_, v, __) => Text(
                  _fmt(v.round()),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: valueStyle,
                ),
              )
            else
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 250),
                child: Text(
                  data.value ?? '',
                  key: ValueKey(data.value),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: valueStyle,
                ),
              ),
            const SizedBox(height: 1),
            Text(
              data.hint ?? data.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: AppColors.textWhite.withValues(alpha: 0.5),
                fontSize: 10.5,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Titik merah berdenyut (tanda ada permintaan pertemanan baru).
class _PulseDot extends StatefulWidget {
  const _PulseDot();

  @override
  State<_PulseDot> createState() => _PulseDotState();
}

class _PulseDotState extends State<_PulseDot> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  )..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 14,
      height: 14,
      child: AnimatedBuilder(
        animation: _c,
        builder: (_, __) {
          final t = _c.value;
          return Stack(
            alignment: Alignment.center,
            children: [
              Container(
                width: 6 + 8 * t,
                height: 6 + 8 * t,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.accentViolet.withValues(alpha: 0.5 * (1 - t)),
                ),
              ),
              Container(
                width: 7,
                height: 7,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.accentViolet,
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

// =============================================================================
// Pintasan
// =============================================================================

class _QuickItem {
  const _QuickItem({
    required this.icon,
    required this.label,
    required this.colors,
    required this.onTap,
    this.badge = 0,
  });

  final IconData icon;
  final String label;
  final List<Color> colors;
  final VoidCallback onTap;
  final int badge;
}

class _QuickActions extends StatelessWidget {
  const _QuickActions({required this.items});

  final List<_QuickItem> items;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final it in items)
          Expanded(
            child: _Pressable(
              onTap: it.onTap,
              child: Column(
                children: [
                  Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Container(
                        width: 54,
                        height: 54,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(18),
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [
                              it.colors.first.withValues(alpha: 0.22),
                              it.colors.last.withValues(alpha: 0.10),
                            ],
                          ),
                          border: Border.all(color: it.colors.first.withValues(alpha: 0.28)),
                        ),
                        child: ShaderMask(
                          shaderCallback: (r) => LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: it.colors,
                          ).createShader(r),
                          child: Icon(it.icon, color: Colors.white, size: 25),
                        ),
                      ),
                      if (it.badge > 0)
                        Positioned(
                          top: -5,
                          right: -7,
                          child: Container(
                            constraints: const BoxConstraints(minWidth: 20),
                            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                            decoration: BoxDecoration(
                              color: AppColors.accentViolet,
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(color: AppColors.backgroundDark, width: 2),
                            ),
                            child: Text(
                              it.badge > 99 ? '99+' : '${it.badge}',
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 10,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    it.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

// =============================================================================
// Grup & baris
// =============================================================================

class _Section extends StatelessWidget {
  const _Section({required this.children, this.label});

  final String? label;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final rows = <Widget>[];
    for (var k = 0; k < children.length; k++) {
      if (k > 0) {
        rows.add(Container(
          height: 1,
          margin: const EdgeInsets.only(left: 62, right: 14),
          color: Colors.white.withValues(alpha: 0.05),
        ));
      }
      rows.add(children[k]);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (label != null)
          Padding(
            padding: const EdgeInsets.only(left: 6, bottom: 9),
            child: Text(
              label!.toUpperCase(),
              style: const TextStyle(
                color: AppColors.textMuted,
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.1,
              ),
            ),
          ),
        GlassSurface(
          borderRadius: BorderRadius.circular(20),
          blur: GlassBlur.thin,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: Material(
              type: MaterialType.transparency,
              child: Column(children: rows),
            ),
          ),
        ),
      ],
    );
  }
}

class _SettingsRow extends StatelessWidget {
  const _SettingsRow({
    required this.icon,
    required this.title,
    this.subtitle,
    this.trailing,
    this.onTap,
    this.external = false,
    this.danger = false,
    this.showChevron = true,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;
  final bool external;
  final bool danger;
  final bool showChevron;

  @override
  Widget build(BuildContext context) {
    final tint = danger ? AppColors.errorRed : AppColors.accentVioletLight;
    final trail = trailing ??
        (showChevron
            ? Icon(
                external ? Icons.north_east_rounded : Icons.chevron_right_rounded,
                color: AppColors.textMuted,
                size: external ? 17 : 22,
              )
            : null);

    return InkWell(
      onTap: onTap == null
          ? null
          : () {
              HapticFeedback.selectionClick();
              onTap!();
            },
      splashColor: tint.withValues(alpha: 0.08),
      highlightColor: Colors.white.withValues(alpha: 0.03),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: tint.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(11),
              ),
              child: Icon(icon, color: tint, size: 18),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: danger ? AppColors.errorRed : AppColors.textWhite,
                      fontSize: 14.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (subtitle != null)
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 220),
                      transitionBuilder: (c, a) => FadeTransition(opacity: a, child: c),
                      child: Padding(
                        key: ValueKey(subtitle),
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          subtitle!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: AppColors.textMuted, fontSize: 12),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            if (trail != null) ...[
              const SizedBox(width: 10),
              trail,
            ],
          ],
        ),
      ),
    );
  }
}

/// Kualitas video: pilihan tersegmen dengan indikator yang meluncur.
class _QualityRow extends StatelessWidget {
  const _QualityRow({required this.value, required this.onChanged});

  final String value;
  final ValueChanged<String> onChanged;

  static const List<String> _qualities = ['1080p', '720p', '480p', '360p'];

  @override
  Widget build(BuildContext context) {
    final found = _qualities.indexOf(value);
    final idx = found < 0 ? 1 : found;
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: AppColors.accentVioletLight.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(11),
                ),
                child: const Icon(Icons.high_quality_rounded,
                    color: AppColors.accentVioletLight, size: 18),
              ),
              const SizedBox(width: 14),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Kualitas Video',
                      style: TextStyle(
                        color: AppColors.textWhite,
                        fontSize: 14.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    SizedBox(height: 2),
                    Text(
                      'Dipakai saat memuat episode',
                      style: TextStyle(color: AppColors.textMuted, fontSize: 12),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            height: 38,
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.25),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
            ),
            child: LayoutBuilder(
              builder: (context, c) {
                final w = c.maxWidth / _qualities.length;
                return Stack(
                  children: [
                    AnimatedPositioned(
                      duration: const Duration(milliseconds: 320),
                      curve: Curves.easeOutBack,
                      left: w * idx,
                      top: 0,
                      bottom: 0,
                      width: w,
                      child: Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(9),
                          gradient: const LinearGradient(
                            colors: [AppColors.accentViolet, AppColors.accentVioletLight],
                          ),
                        ),
                      ),
                    ),
                    Row(
                      children: [
                        for (var k = 0; k < _qualities.length; k++)
                          Expanded(
                            child: GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onTap: () {
                                if (k == idx) return;
                                HapticFeedback.selectionClick();
                                onChanged(_qualities[k]);
                              },
                              child: Center(
                                child: AnimatedDefaultTextStyle(
                                  duration: const Duration(milliseconds: 200),
                                  style: TextStyle(
                                    color: k == idx ? Colors.white : AppColors.textSecondary,
                                    fontSize: 12.5,
                                    fontWeight: k == idx ? FontWeight.w800 : FontWeight.w600,
                                  ),
                                  child: Text(_qualities[k]),
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// Baris "Bersihkan Cache": tombolnya berubah jadi centang sebentar setelah ditekan.
class _CacheRow extends StatefulWidget {
  const _CacheRow({required this.onClear});

  final VoidCallback onClear;

  @override
  State<_CacheRow> createState() => _CacheRowState();
}

class _CacheRowState extends State<_CacheRow> {
  bool _done = false;

  Future<void> _run() async {
    if (_done) return;
    widget.onClear();
    HapticFeedback.lightImpact();
    setState(() => _done = true);
    await Future<void>.delayed(const Duration(milliseconds: 2200));
    if (mounted) setState(() => _done = false);
  }

  @override
  Widget build(BuildContext context) {
    return _SettingsRow(
      icon: Icons.cleaning_services_rounded,
      title: 'Bersihkan Cache',
      subtitle: _done ? 'Cache memori sudah dikosongkan' : 'Kosongkan cache gambar di memori',
      onTap: _run,
      trailing: AnimatedSwitcher(
        duration: const Duration(milliseconds: 300),
        transitionBuilder: (c, a) => ScaleTransition(scale: a, child: c),
        child: _done
            ? Container(
                key: const ValueKey('done'),
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  color: AppColors.successGreen.withValues(alpha: 0.16),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.check_rounded, color: AppColors.successGreen, size: 18),
              )
            : Container(
                key: const ValueKey('idle'),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(100),
                ),
                child: const Text(
                  'Bersihkan',
                  style: TextStyle(
                    color: AppColors.textWhite,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
      ),
    );
  }
}

/// Toggle berbentuk pil dengan knob yang meluncur & warna yang memudar.
class _AnimatedToggle extends StatelessWidget {
  const _AnimatedToggle({required this.value, required this.onChanged});

  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      toggled: value,
      button: true,
      child: GestureDetector(
        onTap: () {
          HapticFeedback.selectionClick();
          onChanged(!value);
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 260),
          curve: Curves.easeOutCubic,
          width: 48,
          height: 28,
          padding: const EdgeInsets.all(3),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(100),
            color: value ? AppColors.accentViolet : Colors.white.withValues(alpha: 0.10),
          ),
          child: AnimatedAlign(
            duration: const Duration(milliseconds: 260),
            curve: Curves.easeOutBack,
            alignment: value ? Alignment.centerRight : Alignment.centerLeft,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 260),
              width: 22,
              height: 22,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: value ? Colors.white : const Color(0xFFB7BCC6),
                boxShadow: const [
                  BoxShadow(color: Color(0x40000000), blurRadius: 4, offset: Offset(0, 1)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Efek tekan: mengecil sedikit lalu membal balik.
class _Pressable extends StatefulWidget {
  const _Pressable({required this.child, required this.onTap});

  final Widget child;
  final VoidCallback onTap;

  @override
  State<_Pressable> createState() => _PressableState();
}

class _PressableState extends State<_Pressable> {
  bool _down = false;

  void _set(bool v) {
    if (_down != v) setState(() => _down = v);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => _set(true),
      onTapCancel: () => _set(false),
      onTapUp: (_) => _set(false),
      onTap: () {
        HapticFeedback.selectionClick();
        widget.onTap();
      },
      child: AnimatedScale(
        scale: _down ? 0.95 : 1,
        duration: Duration(milliseconds: _down ? 90 : 220),
        curve: _down ? Curves.easeOut : Curves.easeOutBack,
        child: widget.child,
      ),
    );
  }
}

// =============================================================================
// Footer
// =============================================================================

class _AppFooter extends StatelessWidget {
  const _AppFooter();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: Image.asset(
            'assets/images/logo.jpg',
            width: 44,
            height: 44,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => const SizedBox(
              width: 44,
              height: 44,
              child: Icon(Icons.play_circle_outline, color: AppColors.accentViolet),
            ),
          ),
        ),
        const SizedBox(height: 10),
        FutureBuilder<PackageInfo>(
          future: PackageInfo.fromPlatform(),
          builder: (context, snap) => Text(
            'Zenime  ·  v${snap.data?.version ?? '—'}',
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        const SizedBox(height: 3),
        const Text(
          'Nonton Anime, Tenang & Modern',
          style: TextStyle(color: AppColors.textMuted, fontSize: 11.5),
        ),
        const SizedBox(height: 2),
        Text(
          'Powered by Dayynime v5 API',
          style: TextStyle(
            color: AppColors.accentViolet.withValues(alpha: 0.7),
            fontSize: 10.5,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

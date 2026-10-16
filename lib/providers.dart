import 'package:dio/dio.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/dio_client.dart';
import 'core/firebase_config.dart';
import 'data/api/anichin_network.dart';
import 'data/api/premium_token_manager.dart';
import 'data/models/anichin_models.dart';
import 'data/repository/anichin_repository.dart';
import 'data/api/api_service.dart';
import 'data/download/episode_download_manager.dart';
import 'data/local/local_store.dart';
import 'data/repository/account_repository.dart';
import 'data/repository/admin_repository.dart';
import 'data/repository/anime_repository.dart';
import 'data/repository/auth_repository.dart';
import 'data/repository/chat_repository.dart';
import 'data/repository/clan_repository.dart';
import 'data/repository/public_profile_repository.dart';
import 'data/repository/safety_repository.dart';
import 'data/repository/comment_repository.dart';
import 'data/repository/friend_repository.dart';
import 'data/repository/private_chat_repository.dart';
import 'data/models/friend_models.dart';
import 'data/models/public_profile_models.dart';
import 'data/models/account_models.dart';
import 'data/models/chat_models.dart';
import 'data/models/clan_models.dart';
import 'data/models/comment_models.dart';
import 'data/models/cuplix_item.dart';
import 'data/models/support_models.dart';
import 'data/models/xp_models.dart';
import 'data/repository/store_repository.dart';
import 'data/models/store_models.dart';
import 'data/repository/xp_repository.dart';
import 'data/repository/wallpaper_repository.dart';
import 'data/repository/avatar_frame_repository.dart';
import 'data/repository/gift_repository.dart';
import 'data/repository/notification_repository.dart';
import 'data/repository/home_bootstrap_repository.dart';
import 'data/repository/screen_data_repository.dart';
import 'core/screen_seed.dart';
import 'data/models/home_bootstrap.dart';
import 'data/repository/tree_repository.dart';
import 'data/supabase/supabase_client.dart';

/// Di-override di main() setelah LocalStore.open() selesai.
final localStoreProvider = ChangeNotifierProvider<LocalStore>(
  (ref) => throw UnimplementedError('localStoreProvider harus di-override di main()'),
);

/// Download episode offline (khusus Premium). Satu instance selama app hidup.
final episodeDownloadManagerProvider = Provider<EpisodeDownloadManager>(
  (ref) => EpisodeDownloadManager(ref.read(localStoreProvider)),
);

final dioProvider = Provider<Dio>((ref) => createDio());

final apiServiceProvider = Provider<ApiService>(
  (ref) => ApiService(ref.watch(dioProvider)),
);

/// Pakai `read` untuk store supaya repository tidak dibuat ulang tiap data lokal berubah.
final repositoryProvider = Provider<AnimeRepository>(
  (ref) => AnimeRepository(
    ref.watch(apiServiceProvider),
    ref.read(localStoreProvider),
    ref.watch(publicProfileRepositoryProvider),
  ),
);

/// Dio khusus Supabase Zenime (login + chat).
final supabaseDioProvider = Provider<Dio>((ref) => createSupabaseDio());

/// Sync favorit + riwayat tonton ke Supabase (port PublicProfileRepository.kt).
final publicProfileRepositoryProvider = Provider<PublicProfileRepository>(
  (ref) => PublicProfileRepository(ref.watch(supabaseDioProvider)),
);

/// Favorit/riwayat publik milik user lain (profil publik). Gagal = lempar error.
final publicProfileContentProvider =
    FutureProvider.autoDispose.family<PublicProfileContent, String>((ref, uid) {
  final repo = ref.watch(publicProfileRepositoryProvider);
  return viaScreenSeed<PublicProfileContent>(
      'content', uid, () => repo.getPublicContent(uid), () => repo.getPublicContent(uid));
});

/// Token premium bertanda tangan server (buat endpoint donghua).
final premiumTokenManagerProvider = Provider<PremiumTokenManager>(
  (ref) => PremiumTokenManager(ref.watch(supabaseDioProvider)),
);

/// Dio khusus API Anichin (donghua), base URL dari Remote Config `anichin_base_url`.
final anichinDioProvider = Provider<Dio>(
  (ref) => createAnichinDio(ref.watch(premiumTokenManagerProvider)),
);

final anichinRepositoryProvider = Provider<AnichinRepository>(
  (ref) => AnichinRepository(ref.watch(anichinDioProvider)),
);

/// 3 kartu donghua pertama buat section "Donghua" di Beranda (bento top 3).
/// Gagal / kosong -> section tidak tampil.
final donghuaHotProvider = FutureProvider.autoDispose<List<AnichinCard>>((ref) async {
  try {
    final res = await ref.watch(anichinRepositoryProvider).getHome();
    final seen = <String?>{};
    return res.results
        .expand((s) => s.cards)
        .where((c) => (c.slug ?? '').isNotEmpty && (c.thumbnail ?? '').isNotEmpty)
        .where((c) => seen.add(c.slug))
        .take(3)
        .toList();
  } catch (_) {
    return const [];
  }
});

final chatRepositoryProvider = Provider<ChatRepository>(
  (ref) => ChatRepository(ref.watch(supabaseDioProvider)),
);

final commentRepositoryProvider = Provider<CommentRepository>(
  (ref) => CommentRepository(ref.watch(supabaseDioProvider)),
);

/// Gift Premium (kirim hari premium ke user lain).
final giftRepositoryProvider = Provider<GiftRepository>(
  (ref) => GiftRepository(ref.watch(supabaseDioProvider)),
);

/// Top Giver sepanjang masa + clan & level tiap orang (carousel & halaman).
final topGiversProvider = FutureProvider<TopGiversData>((ref) async {
  final givers = await ref.watch(giftRepositoryProvider).topGivers();
  final uids = givers.map((g) => g.firebaseUid).where((u) => u.isNotEmpty).toList();
  if (uids.isEmpty) return TopGiversData(givers: givers);
  final clansF = ref.read(chatRepositoryProvider).getClanTagsForUids(uids)
      .catchError((_) => <String, String>{});
  final levelsF = ref.read(xpRepositoryProvider).getLevelsForUids(uids)
      .catchError((_) => <String, int>{});
  return TopGiversData(givers: givers, clanTags: await clansF, levels: await levelsF);
});

/// Pohon ZCoin (mini game idle, Edge Function `tree-game`).
final treeRepositoryProvider = Provider<TreeRepository>(
  (ref) => TreeRepository(ref.watch(supabaseDioProvider)),
);

/// Wallpaper Komentar (gacha spin, koleksi, panel admin).
final wallpaperRepositoryProvider = Provider<WallpaperRepository>(
  (ref) => WallpaperRepository(ref.watch(supabaseDioProvider)),
);

final avatarFrameRepositoryProvider = Provider<AvatarFrameRepository>(
  (ref) => AvatarFrameRepository(ref.watch(supabaseDioProvider)),
);

final xpRepositoryProvider = Provider<XpRepository>(
  (ref) => XpRepository(
    ref.watch(supabaseDioProvider),
    ref.watch(chatRepositoryProvider),
  ),
);

/// XP/level sendiri per uid. Gagal load dianggap "belum pernah dapat XP"
/// (null), bukan error. Di-invalidate setelah heartbeat sukses.
final myXpProvider = FutureProvider.family<UserXp?, String>((ref, uid) async {
  final repo = ref.watch(xpRepositoryProvider);
  Future<UserXp?> plain() async {
    try {
      return await repo.getMyXp(uid);
    } catch (_) {
      return null;
    }
  }

  return viaScreenSeed<UserXp?>('xp', uid,
      () => viaHomeBootstrap<UserXp?>(ref, uid, 'xp', (b) => b.xp, plain), plain);
});

final accountRepositoryProvider = Provider<AccountRepository>(
  (ref) => AccountRepository(ref.watch(supabaseDioProvider)),
);

/// Status Premium lengkap (is_premium + expires_at) per uid. Gagal cek = tidak premium.
final premiumStatusProvider = FutureProvider.family<PremiumStatus, String>((ref, uid) {
  final repo = ref.watch(accountRepositoryProvider);
  return viaScreenSeed<PremiumStatus>(
      'premium',
      uid,
      () => viaHomeBootstrap<PremiumStatus>(
          ref, uid, 'premium', (b) => b.premium, () => repo.getPremiumStatus(uid)),
      () => repo.getPremiumStatus(uid));
});

/// Status Premium per uid (gagal cek = tidak premium). Berbagi satu request
/// dengan [premiumStatusProvider] supaya Beranda tidak mengecek dua kali.
final premiumProvider = FutureProvider.family<bool, String>(
  (ref, uid) async => (await ref.watch(premiumStatusProvider(uid).future)).isPremium,
);

/// Kode akun + ID urut (kartu profil Beranda).
final profileIdentityProvider = FutureProvider.family<ProfileIdentity, String>((ref, uid) {
  final repo = ref.watch(accountRepositoryProvider);
  return viaHomeBootstrap<ProfileIdentity>(
      ref, uid, 'identity', (b) => b.identity, () => repo.getProfileIdentity(uid));
});

/// Saldo ZCoin per uid. Gagal = 0.
final coinBalanceProvider = FutureProvider.family<int, String>((ref, uid) {
  final repo = ref.watch(accountRepositoryProvider);
  return viaHomeBootstrap<int>(ref, uid, 'coins', (b) => b.coins, () => repo.getCoinBalance(uid));
});

final storeRepositoryProvider = Provider<StoreRepository>(
  (ref) => StoreRepository(ref.watch(supabaseDioProvider)),
);

/// Daftar paket Premium. Melempar kalau gagal (UI tampilkan coba lagi).
final premiumPackagesProvider = FutureProvider.autoDispose<List<PremiumPackage>>(
  (ref) => ref.watch(storeRepositoryProvider).getPremiumPackages(),
);

/// Daftar paket top up ZCoin. Melempar kalau gagal.
final coinPackagesProvider = FutureProvider.autoDispose<List<CoinPackage>>(
  (ref) => ref.watch(storeRepositoryProvider).getCoinPackages(),
);

/// Profil chat (username/avatar) per uid. Gagal = null.
final chatProfileProvider = FutureProvider.family<ChatProfile?, String>((ref, uid) async {
  final repo = ref.watch(chatRepositoryProvider);
  Future<ChatProfile?> plain() async {
    try {
      return await repo.getProfile(uid);
    } catch (_) {
      return null;
    }
  }

  return viaScreenSeed<ChatProfile?>('profile', uid,
      () => viaHomeBootstrap<ChatProfile?>(ref, uid, 'profile', (b) => b.profile, plain), plain);
});

/// Tanggal gabung Zenime per uid (Stat "Join Zenime" di profil). Gagal = null.
final joinDateProvider = FutureProvider.family<DateTime?, String>((ref, uid) async {
  if (uid.isEmpty) return null;
  final repo = ref.watch(chatRepositoryProvider);
  Future<DateTime?> plain() async {
    try {
      return await repo.getJoinDate(uid);
    } catch (_) {
      return null;
    }
  }

  return viaScreenSeed<DateTime?>('join', uid, plain, plain);
});

/// Status Premium user yang sedang login.
/// loading = belum tahu (auth / cek server belum selesai); belum login = false.
final myPremiumProvider = Provider<AsyncValue<bool>>((ref) {
  final auth = ref.watch(authUserProvider);
  if (auth.isLoading) return const AsyncLoading();
  final uid = auth.valueOrNull?.uid;
  if (uid == null || uid.isEmpty) return const AsyncData(false);
  return ref.watch(premiumProvider(uid));
});

/// Top 4 XP bulan ini buat slide carousel Beranda. Gagal = slide disembunyikan.
final heroTopXpProvider = FutureProvider.autoDispose<List<UserXpDisplay>>((ref) async {
  try {
    return await ref.watch(xpRepositoryProvider).getTopXpDisplay(limit: 4);
  } catch (_) {
    return const [];
  }
});

/// Top 4 clan buat slide carousel Beranda. Gagal = kolom clan kosong.
final heroTopClansProvider = FutureProvider.autoDispose<List<ClanSummary>>((ref) async {
  try {
    return await ref.watch(chatRepositoryProvider).getTopClans(limit: 4);
  } catch (_) {
    return const [];
  }
});

/// Panel Admin (role, ban akun/device). Aksi lewat Edge Function + Firebase ID Token.
final adminRepositoryProvider = Provider<AdminRepository>(
  (ref) => AdminRepository(ref.watch(supabaseDioProvider)),
);

final clanRepositoryProvider = Provider<ClanRepository>(
  (ref) => ClanRepository(
    ref.watch(supabaseDioProvider),
    ref.watch(chatRepositoryProvider),
  ),
);

/// Semua clan (urut level lalu XP) buat halaman Browse.
final allClansProvider = FutureProvider.autoDispose<List<Clan>>(
  (ref) => ref.watch(clanRepositoryProvider).browseClans(),
);

/// Clan yang diikuti user sekarang (null = belum gabung / belum login).
final myClanMembershipProvider = FutureProvider.autoDispose<ClanMember?>((ref) async {
  final uid = ref.watch(authUserProvider).valueOrNull?.uid;
  if (uid == null || uid.isEmpty) return null;
  return ref.watch(clanRepositoryProvider).getMyMembership(uid);
});

/// Relasi user dengan satu clan, menentukan tombol aksi di header.
enum ClanCta { login, join, pending, blockedOtherClan, member }

/// Semua data halaman detail clan.
class ClanDetailData {
  const ClanDetailData({
    required this.clan,
    required this.members,
    required this.levels,
    required this.premiumUids,
    required this.donations,
    required this.cta,
    required this.myUid,
    required this.myRole,
  });

  final Clan clan;
  final List<ClanMemberDisplay> members;
  final Map<String, int> levels;
  final Set<String> premiumUids;
  final List<ClanDonationEntry> donations;
  final ClanCta cta;
  final String myUid;

  /// Role user di clan INI (null kalau bukan member).
  final String? myRole;

  int get totalDonatedToday => donations.fold(0, (a, d) => a + d.amountToday);
}

final clanDetailProvider =
    FutureProvider.autoDispose.family<ClanDetailData, String>((ref, clanId) async {
  final repo = ref.watch(clanRepositoryProvider);
  final uid = ref.watch(authUserProvider).valueOrNull?.uid ?? '';

  final clan = await repo.getClan(clanId);
  // Daftar member wajib duluan (donasi, level, premium butuh uid-nya);
  // cek keanggotaan sendiri tidak saling butuh, jalan bareng.
  final membersF = repo.getMembers(clanId);
  final myMemF = uid.isEmpty
      ? Future<ClanMember?>.value(null)
      : repo.getMyMembership(uid).then<ClanMember?>((m) => m).catchError((_) => null);
  final members = await membersF;
  final myMem = await myMemF;

  ClanCta cta;
  String? myRole;
  if (uid.isEmpty) {
    cta = ClanCta.login;
  } else if (myMem == null) {
    cta = await repo.getMyJoinRequestPending(clanId) ? ClanCta.pending : ClanCta.join;
  } else if (myMem.clanId != clanId) {
    cta = ClanCta.blockedOtherClan;
  } else {
    cta = ClanCta.member;
    myRole = myMem.role;
  }

  final uids = members.map((m) => m.firebaseUid).toList();
  final xpRepo = ref.watch(xpRepositoryProvider);
  final donationsF = repo
      .getTodayDonations(clanId, roleByUid: {for (final m in members) m.firebaseUid: m.role})
      .catchError((_) => <ClanDonationEntry>[]);
  final levelsF = uids.isEmpty
      ? Future.value(<String, int>{})
      : xpRepo.getLevelsForUids(uids).catchError((_) => <String, int>{});
  final premiumF = uids.isEmpty
      ? Future.value(<String>{})
      : xpRepo.getPremiumUids(uids).catchError((_) => <String>{});

  return ClanDetailData(
    clan: clan,
    members: members,
    levels: await levelsF,
    premiumUids: await premiumF,
    donations: await donationsF,
    cta: cta,
    myUid: uid,
    myRole: myRole,
  );
});

/// Request join yang menunggu persetujuan (khusus officer ke atas).
final clanPendingRequestsProvider = FutureProvider.autoDispose
    .family<List<PendingJoinRequestDisplay>, String>(
  (ref, clanId) => ref.watch(clanRepositoryProvider).getPendingJoinRequests(clanId),
);

/// Top 3 donatur buat slide carousel Beranda. Gagal = slide disembunyikan.
final topSupportersProvider = FutureProvider.autoDispose<List<TopSupporter>>((ref) async {
  try {
    final all = await ref.watch(xpRepositoryProvider).getTopSupporters();
    return all.take(3).toList();
  } catch (_) {
    return const [];
  }
});

/// Daftar Top Support lengkap buat halaman Top Support. Melempar kalau gagal
/// (UI menampilkan error + coba lagi).
final topSupportersFullProvider = FutureProvider.autoDispose<List<TopSupporter>>(
  (ref) => ref.watch(xpRepositoryProvider).getTopSupporters(),
);

final xpLeaderboardProvider = FutureProvider.autoDispose<List<UserXpDisplay>>(
  (ref) => ref.watch(xpRepositoryProvider).getLeaderboardDisplay(),
);

final authRepositoryProvider = Provider<AuthRepository>((ref) {
  final repo = AuthRepository(
    ref.watch(chatRepositoryProvider),
    ref.watch(supabaseDioProvider),
  );
  ref.onDispose(repo.dispose);
  return repo;
});

/// User yang sedang login (null = belum login / email belum diverifikasi).
final authUserProvider = StreamProvider<User?>(
  (ref) => ref.watch(authRepositoryProvider).userStream,
);

/// Klip Cuplix untuk section "Cuplix" di Beranda (10 klip teratas). Gagal ->
/// list kosong, jadi section-nya saja yang hilang dan Beranda tetap jalan.
final homeCuplixProvider = FutureProvider.autoDispose<List<CuplixItem>>((ref) async {
  try {
    final (list, _) = await ref.watch(repositoryProvider).getCuplixScroll();
    return list.where((c) => c.thumbnailUrl.isNotEmpty).take(10).toList();
  } catch (_) {
    return const [];
  }
});

/// Tag clan satu user (null = belum gabung clan / gagal).
final userClanTagProvider = FutureProvider.autoDispose.family<String?, String>((ref, uid) async {
  if (uid.isEmpty) return null;
  final repo = ref.watch(chatRepositoryProvider);
  Future<String?> plain() async {
    try {
      final map = await repo.getClanTagsForUids([uid]);
      return map[uid];
    } catch (_) {
      return null;
    }
  }

  return viaScreenSeed<String?>('clan_tag', uid, plain, plain);
});

/// Komentar milik 1 user (tab Komentar di Profil). Gagal = error (UI tampil pesan).
final myCommentsProvider =
    FutureProvider.autoDispose.family<List<EpisodeComment>, String>(
  (ref, uid) => ref.watch(commentRepositoryProvider).getMyComments(uid),
);

/// Total komentar milik 1 user (stat di Profil). Gagal = null.
final myCommentCountProvider = FutureProvider.autoDispose.family<int?, String>((ref, uid) async {
  final repo = ref.watch(commentRepositoryProvider);
  Future<int?> plain() async {
    try {
      return await repo.getMyCommentCount(uid);
    } catch (_) {
      return null;
    }
  }

  return viaScreenSeed<int?>('comment_count', uid, plain, plain);
});

final friendRepositoryProvider = Provider<FriendRepository>(
  (ref) => FriendRepository(
    ref.watch(supabaseDioProvider),
    ref.watch(chatRepositoryProvider),
  ),
);

final privateChatRepositoryProvider = Provider<PrivateChatRepository>(
  (ref) => PrivateChatRepository(ref.watch(supabaseDioProvider)),
);

/// Jumlah permintaan pertemanan masuk yang belum direspon (badge di Profil).
/// Gagal / belum login = 0.
final incomingFriendRequestsProvider = FutureProvider.autoDispose<int>((ref) async {
  final uid = ref.watch(authUserProvider).valueOrNull?.uid;
  if (uid == null || uid.isEmpty) return 0;
  final repo = ref.watch(friendRepositoryProvider);
  return viaHomeBootstrap<int>(ref, uid, 'friend_requests', (b) => b.friendRequests, () async {
    try {
      return await repo.countIncomingRequests(uid);
    } catch (_) {
      return 0;
    }
  });
});

/// Data satu layar dalam satu request (Edge Function `screen-data`).
final screenDataRepositoryProvider = Provider<ScreenDataRepository>(
  (ref) => ScreenDataRepository(ref.watch(supabaseDioProvider)),
);

// ---------------------------------------------------------------------------
// Data awal Beranda dalam SATU request (Edge Function `home-bootstrap`).
//
// Alur buka app untuk akun sendiri:
//  1. Salinan terakhir di HP langsung ditampilkan (tanpa nunggu jaringan).
//  2. home-bootstrap diambil sekali; begitu datang, semua kartu ikut terbarui.
//  3. Setelah itu tiap provider kembali ke jalur lamanya sendiri (mis. saldo
//     di-invalidate setelah beli -> ambil saldo terbaru, bukan data awal).
// Kalau home-bootstrap gagal / belum dideploy, semua otomatis pakai jalur lama.

final homeBootstrapRepositoryProvider = Provider<HomeBootstrapRepository>(
  (ref) => HomeBootstrapRepository(ref.watch(supabaseDioProvider)),
);

/// Salinan terakhir di HP untuk akun yang login.
final cachedHomeBootstrapProvider = FutureProvider<HomeBootstrap?>((ref) async {
  final uid = ref.watch(authUserProvider.select((a) => a.valueOrNull?.uid));
  if (uid == null || uid.isEmpty) return null;
  return ref.watch(homeBootstrapRepositoryProvider).loadCache(uid);
});

/// Data segar dari server (null = gagal, pakai jalur lama).
final homeBootstrapProvider = FutureProvider<HomeBootstrap?>((ref) async {
  final uid = ref.watch(authUserProvider.select((a) => a.valueOrNull?.uid));
  if (uid == null || uid.isEmpty) return null;
  final repo = ref.watch(homeBootstrapRepositoryProvider);
  try {
    final b = await repo.fetch();
    if (b.uid != uid) return null;
    await repo.saveCache(b);
    return b;
  } catch (_) {
    return null;
  }
});

/// Bagian (field|uid) yang sudah memakai data segar home-bootstrap.
final Set<String> _homeBootstrapUsed = <String>{};

/// Ambil satu bagian data akun sendiri dari home-bootstrap (cache dulu, lalu
/// data segar). Untuk uid orang lain, atau setelah data awal terpakai, atau
/// kalau bagian itu kosong, langsung pakai [fallback] (jalur lama).
Future<T> viaHomeBootstrap<T>(
  Ref<Object?> ref,
  String uid,
  String field,
  T? Function(HomeBootstrap b) pick,
  Future<T> Function() fallback,
) async {
  final me = ref.watch(authUserProvider.select((a) => a.valueOrNull?.uid));
  final key = '$field|$uid';
  if (me == null || me.isEmpty || me != uid || _homeBootstrapUsed.contains(key)) {
    return fallback();
  }
  final fresh = ref.watch(homeBootstrapProvider);
  if (fresh.hasValue) {
    _homeBootstrapUsed.add(key);
    final b = fresh.value;
    final v = b == null ? null : pick(b);
    return v ?? await fallback();
  }
  // Data segar belum datang: tampilkan salinan terakhir kalau ada. Provider
  // ini otomatis jalan ulang begitu data segar tiba (karena di-watch).
  final cached = ref.watch(cachedHomeBootstrapProvider).valueOrNull;
  final c = cached == null ? null : pick(cached);
  if (c != null) return c;
  // Belum ada salinan: tunggu data segar. Kunci TIDAK ditandai di sini; begitu
  // data segar tiba provider jalan ulang lewat cabang hasValue di atas (tanpa
  // request tambahan) dan menandainya di sana.
  final b = await ref.watch(homeBootstrapProvider.future);
  final v = b == null ? null : pick(b);
  return v ?? await fallback();
}

// ---------------------------------------------------------------------------
// Notifikasi (lonceng + push), Edge Function `zenime-notify`.

final notificationRepositoryProvider = Provider<NotificationRepository>(
  (ref) => NotificationRepository(ref.watch(supabaseDioProvider)),
);

/// Jumlah notif belum dibaca (badge lonceng Beranda). Gagal = 0.
/// Pertama kali dari home-bootstrap (tanpa request tambahan); setelah itu
/// di-refresh lewat invalidate (push masuk, buka/tutup layar Notifikasi).
final unreadNotificationsProvider = FutureProvider<int>((ref) async {
  final uid = ref.watch(authUserProvider).valueOrNull?.uid;
  if (uid == null || uid.isEmpty) return 0;
  final repo = ref.watch(notificationRepositoryProvider);
  return viaHomeBootstrap<int>(ref, uid, 'unread', (b) => b.unread, () async {
    try {
      return await repo.unreadCount();
    } catch (_) {
      return 0;
    }
  });
});

// ---------------------------------------------------------------------------
// Keamanan: laporkan, blokir, hapus akun (Edge Function `zenime-safety`).

final safetyRepositoryProvider = Provider<SafetyRepository>(
  (ref) => SafetyRepository(ref.watch(supabaseDioProvider)),
);

/// Set uid yang diblokir user yang sedang login. Pesan dari uid ini
/// disembunyikan di Chat Global dan percakapan DM-nya ditutup.
final blockedUsersProvider =
    NotifierProvider<BlockedUsersNotifier, Set<String>>(BlockedUsersNotifier.new);

class BlockedUsersNotifier extends Notifier<Set<String>> {
  bool _loaded = false;

  @override
  Set<String> build() {
    // Ganti akun / logout -> daftar blokir dimuat ulang.
    ref.watch(authUserProvider.select((a) => a.valueOrNull?.uid));
    _loaded = false;
    Future.microtask(refresh);
    return const {};
  }

  bool get _loggedIn =>
      FirebaseConfig.ready && FirebaseAuth.instance.currentUser != null;

  Future<void> refresh() async {
    if (!_loggedIn) return;
    try {
      final list = await ref.read(safetyRepositoryProvider).listBlocks();
      state = list.map((e) => e.uid).toSet();
      _loaded = true;
    } catch (_) {
      // Gagal ambil daftar: biarkan state lama, coba lagi nanti.
    }
  }

  Future<void> ensureLoaded() async {
    if (!_loaded) await refresh();
  }

  Future<void> block(String uid) async {
    await ref.read(safetyRepositoryProvider).block(uid);
    state = {...state, uid};
  }

  Future<void> unblock(String uid) async {
    await ref.read(safetyRepositoryProvider).unblock(uid);
    state = {...state}..remove(uid);
  }
}

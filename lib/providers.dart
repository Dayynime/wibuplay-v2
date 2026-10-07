import 'package:dio/dio.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/dio_client.dart';
import 'data/api/api_service.dart';
import 'data/download/episode_download_manager.dart';
import 'data/local/local_store.dart';
import 'data/repository/account_repository.dart';
import 'data/repository/anime_repository.dart';
import 'data/repository/auth_repository.dart';
import 'data/repository/chat_repository.dart';
import 'data/repository/clan_repository.dart';
import 'data/repository/public_profile_repository.dart';
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
    FutureProvider.autoDispose.family<PublicProfileContent, String>(
  (ref, uid) => ref.watch(publicProfileRepositoryProvider).getPublicContent(uid),
);

final chatRepositoryProvider = Provider<ChatRepository>(
  (ref) => ChatRepository(ref.watch(supabaseDioProvider)),
);

final commentRepositoryProvider = Provider<CommentRepository>(
  (ref) => CommentRepository(ref.watch(supabaseDioProvider)),
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
  try {
    return await ref.watch(xpRepositoryProvider).getMyXp(uid);
  } catch (_) {
    return null;
  }
});

final accountRepositoryProvider = Provider<AccountRepository>(
  (ref) => AccountRepository(ref.watch(supabaseDioProvider)),
);

/// Status Premium lengkap (is_premium + expires_at) per uid. Gagal cek = tidak premium.
final premiumStatusProvider = FutureProvider.family<PremiumStatus, String>(
  (ref, uid) => ref.watch(accountRepositoryProvider).getPremiumStatus(uid),
);

/// Status Premium per uid (gagal cek = tidak premium). Berbagi satu request
/// dengan [premiumStatusProvider] supaya Beranda tidak mengecek dua kali.
final premiumProvider = FutureProvider.family<bool, String>(
  (ref, uid) async => (await ref.watch(premiumStatusProvider(uid).future)).isPremium,
);

/// Kode akun + ID urut (kartu profil Beranda).
final profileIdentityProvider = FutureProvider.family<ProfileIdentity, String>(
  (ref, uid) => ref.watch(accountRepositoryProvider).getProfileIdentity(uid),
);

/// Saldo ZCoin per uid. Gagal = 0.
final coinBalanceProvider = FutureProvider.family<int, String>(
  (ref, uid) => ref.watch(accountRepositoryProvider).getCoinBalance(uid),
);

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
  try {
    return await ref.watch(chatRepositoryProvider).getProfile(uid);
  } catch (_) {
    return null;
  }
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
  try {
    final map = await ref.watch(chatRepositoryProvider).getClanTagsForUids([uid]);
    return map[uid];
  } catch (_) {
    return null;
  }
});

/// Komentar milik 1 user (tab Komentar di Profil). Gagal = error (UI tampil pesan).
final myCommentsProvider =
    FutureProvider.autoDispose.family<List<EpisodeComment>, String>(
  (ref, uid) => ref.watch(commentRepositoryProvider).getMyComments(uid),
);

/// Total komentar milik 1 user (stat di Profil). Gagal = null.
final myCommentCountProvider = FutureProvider.autoDispose.family<int?, String>((ref, uid) async {
  try {
    return await ref.watch(commentRepositoryProvider).getMyCommentCount(uid);
  } catch (_) {
    return null;
  }
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
  try {
    return await ref.watch(friendRepositoryProvider).countIncomingRequests(uid);
  } catch (_) {
    return 0;
  }
});

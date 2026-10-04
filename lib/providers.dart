import 'package:dio/dio.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/dio_client.dart';
import 'data/api/api_service.dart';
import 'data/local/local_store.dart';
import 'data/repository/account_repository.dart';
import 'data/repository/anime_repository.dart';
import 'data/repository/auth_repository.dart';
import 'data/repository/chat_repository.dart';
import 'data/models/account_models.dart';
import 'data/models/chat_models.dart';
import 'data/models/clan_models.dart';
import 'data/models/support_models.dart';
import 'data/models/xp_models.dart';
import 'data/repository/xp_repository.dart';
import 'data/supabase/supabase_client.dart';

/// Di-override di main() setelah LocalStore.open() selesai.
final localStoreProvider = ChangeNotifierProvider<LocalStore>(
  (ref) => throw UnimplementedError('localStoreProvider harus di-override di main()'),
);

final dioProvider = Provider<Dio>((ref) => createDio());

final apiServiceProvider = Provider<ApiService>(
  (ref) => ApiService(ref.watch(dioProvider)),
);

/// Pakai `read` untuk store supaya repository tidak dibuat ulang tiap data lokal berubah.
final repositoryProvider = Provider<AnimeRepository>(
  (ref) => AnimeRepository(ref.watch(apiServiceProvider), ref.read(localStoreProvider)),
);

/// Dio khusus Supabase Zenime (login + chat).
final supabaseDioProvider = Provider<Dio>((ref) => createSupabaseDio());

final chatRepositoryProvider = Provider<ChatRepository>(
  (ref) => ChatRepository(ref.watch(supabaseDioProvider)),
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

/// Top 3 donatur buat slide carousel Beranda. Gagal = slide disembunyikan.
final topSupportersProvider = FutureProvider.autoDispose<List<TopSupporter>>((ref) async {
  try {
    final all = await ref.watch(xpRepositoryProvider).getTopSupporters();
    return all.take(3).toList();
  } catch (_) {
    return const [];
  }
});

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

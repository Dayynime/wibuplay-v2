import 'package:dio/dio.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/dio_client.dart';
import 'data/api/api_service.dart';
import 'data/local/local_store.dart';
import 'data/repository/anime_repository.dart';
import 'data/repository/auth_repository.dart';
import 'data/repository/chat_repository.dart';
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

/// Status Premium per uid (gagal cek = tidak premium).
final premiumProvider = FutureProvider.family<bool, String>(
  (ref, uid) => ref.watch(xpRepositoryProvider).isPremium(uid),
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

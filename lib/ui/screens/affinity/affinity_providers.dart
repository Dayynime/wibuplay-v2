import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/models/affinity_models.dart';
import '../../../data/repository/affinity_repository.dart';
import '../../../providers.dart';

final affinityRepositoryProvider = Provider<AffinityRepository>(
  (ref) => AffinityRepository(ref.watch(supabaseDioProvider)),
);

/// Semua afinitas milik [uid] (halaman Afinitas sendiri & publik).
final affinityListProvider = FutureProvider.autoDispose.family<AffinityList, String>((ref, uid) async {
  if (uid.isEmpty) return const AffinityList();
  return ref.watch(affinityRepositoryProvider).list(uid);
});

/// Versi aman untuk strip di profil: gagal / belum login = null (strip disembunyikan).
final affinityListSafeProvider = FutureProvider.autoDispose.family<AffinityList?, String>((ref, uid) async {
  if (uid.isEmpty) return null;
  if (ref.watch(authUserProvider).valueOrNull == null) return null;
  try {
    return await ref.watch(affinityRepositoryProvider).list(uid);
  } catch (_) {
    return null;
  }
});

final affinityDetailProvider = FutureProvider.autoDispose.family<AffinityDetail?, String>((ref, id) async {
  return ref.watch(affinityRepositoryProvider).detail(id);
});

final affinityIncomingProvider = FutureProvider.autoDispose<List<AffinityRequest>>((ref) async {
  if (ref.watch(authUserProvider).valueOrNull == null) return const [];
  return ref.watch(affinityRepositoryProvider).requests(incoming: true);
});

final affinityOutgoingProvider = FutureProvider.autoDispose<List<AffinityRequest>>((ref) async {
  if (ref.watch(authUserProvider).valueOrNull == null) return const [];
  return ref.watch(affinityRepositoryProvider).requests(incoming: false);
});

/// Muat ulang semua data afinitas yang mungkin berubah setelah satu aksi.
void refreshAffinity(WidgetRef ref, {String? uid, String? otherUid}) {
  if (uid != null) {
    ref.invalidate(affinityListProvider(uid));
    ref.invalidate(affinityListSafeProvider(uid));
  }
  if (otherUid != null) {
    ref.invalidate(affinityListProvider(otherUid));
    ref.invalidate(affinityListSafeProvider(otherUid));
  }
  ref.invalidate(affinityIncomingProvider);
  ref.invalidate(affinityOutgoingProvider);
}

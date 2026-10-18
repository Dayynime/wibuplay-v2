import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/local/entities.dart';
import '../../../data/repository/anime_repository.dart';
import '../../../providers.dart';

/// Port ProfileViewModel.favorites (StateFlow dari Room): daftar favorit,
/// terbaru dulu. Berubah otomatis saat LocalStore berubah.
final profileFavoritesProvider = Provider<List<FavoriteEntity>>(
  (ref) => ref.watch(localStoreProvider.select((s) => s.favorites)),
);

/// Port ProfileViewModel.watchHistory: riwayat tonton, terakhir ditonton dulu.
final profileHistoryProvider = Provider<List<WatchHistoryEntity>>(
  (ref) => ref.watch(localStoreProvider.select((s) => s.history)),
);

/// Port aksi ProfileViewModel: removeFavorite, deleteHistory, clearAllHistory.
class ProfileController {
  ProfileController(this._repository);

  final AnimeRepository _repository;

  Future<void> removeFavorite(String id) => _repository.removeFavorite(id);

  Future<void> deleteHistory(String id) => _repository.deleteHistory(id);

  Future<void> clearAllHistory() => _repository.clearAllHistory();
}

final profileControllerProvider = Provider<ProfileController>(
  (ref) => ProfileController(ref.read(repositoryProvider)),
);

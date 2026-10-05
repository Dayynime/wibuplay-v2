import 'anime_item.dart';

/// Port HomeSectionData. `slider` = daftar hero banner (maks 6 item).
class HomeSectionData {
  const HomeSectionData({
    this.slider = const [],
    this.hot = const [],
    this.popular = const [],
    this.newRelease = const [],
    this.random = const [],
    this.today = const [],
    this.update = const [],
    this.waiting = const [],
    this.updateLabels = const {},
  });

  final List<AnimeItem> slider;
  final List<AnimeItem> hot;
  final List<AnimeItem> popular;
  final List<AnimeItem> newRelease;
  final List<AnimeItem> random;
  final List<AnimeItem> today;
  final List<AnimeItem> update;

  /// "Paling Dinanti" (data/home/list -> waiting).
  final List<AnimeItem> waiting;

  /// idAnime -> "Episode N" untuk section Episode Baru.
  final Map<String, String> updateLabels;
}

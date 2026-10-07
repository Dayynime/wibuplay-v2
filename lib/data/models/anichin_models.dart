/// Model API Anichin (donghua). Port AnichinModels.kt.
///
/// Semua field nullable/default karena hasil scraping bisa bolong, dan tiap
/// response bisa menyelipkan field `error` kalau scrape-nya gagal.

String? _str(Object? v) => v is String ? v : null;

int? _int(Object? v) {
  if (v is int) return v;
  if (v is num) return v.toInt();
  if (v is String) return int.tryParse(v.trim());
  return null;
}

/// Kartu donghua (home, search, /anime, /genre/{slug}).
class AnichinCard {
  const AnichinCard({
    this.title,
    this.type,
    this.headline,
    this.eps,
    this.status,
    this.thumbnail,
    this.slug,
  });

  final String? title;
  final String? type;
  final String? headline;

  /// Cuma ada di kartu home.
  final int? eps;

  /// Cuma ada di search/anime/genre.
  final String? status;
  final String? thumbnail;
  final String? slug;

  factory AnichinCard.fromJson(Map<String, dynamic> j) => AnichinCard(
        title: _str(j['title']),
        type: _str(j['type']),
        headline: _str(j['headline']),
        eps: _int(j['eps']),
        status: _str(j['status']),
        thumbnail: _str(j['thumbnail']),
        slug: _str(j['slug']),
      );

  AnichinCard copyWith({String? slug}) => AnichinCard(
        title: title,
        type: type,
        headline: headline,
        eps: eps,
        status: status,
        thumbnail: thumbnail,
        slug: slug ?? this.slug,
      );
}

List<AnichinCard> _cards(Object? v) => (v is List ? v : const [])
    .whereType<Map>()
    .map((m) => AnichinCard.fromJson(Map<String, dynamic>.from(m)))
    .toList();

class AnichinHomeSection {
  const AnichinHomeSection({this.section, this.cards = const []});

  final String? section;
  final List<AnichinCard> cards;

  factory AnichinHomeSection.fromJson(Map<String, dynamic> j) =>
      AnichinHomeSection(section: _str(j['section']), cards: _cards(j['cards']));

  AnichinHomeSection withCards(List<AnichinCard> c) =>
      AnichinHomeSection(section: section, cards: c);
}

/// GET /  (?page=)
class AnichinHomeResponse {
  const AnichinHomeResponse({
    this.results = const [],
    this.page,
    this.total,
    this.source,
    this.error,
  });

  final List<AnichinHomeSection> results;
  final int? page;
  final int? total;
  final String? source;
  final String? error;

  factory AnichinHomeResponse.fromJson(Map<String, dynamic> j) => AnichinHomeResponse(
        results: (j['results'] is List ? j['results'] as List : const [])
            .whereType<Map>()
            .map((m) => AnichinHomeSection.fromJson(Map<String, dynamic>.from(m)))
            .toList(),
        page: _int(j['page']),
        total: _int(j['total']),
        source: _str(j['source']),
        error: _str(j['error']),
      );
}

/// GET /search/{query}, /anime, /genre/{slug}
class AnichinListResponse {
  const AnichinListResponse({
    this.results = const [],
    this.query,
    this.slug,
    this.page,
    this.total,
    this.source,
    this.error,
  });

  final List<AnichinCard> results;
  final String? query;
  final String? slug;
  final int? page;
  final int? total;
  final String? source;
  final String? error;

  factory AnichinListResponse.fromJson(Map<String, dynamic> j) => AnichinListResponse(
        results: _cards(j['results']),
        query: _str(j['query']),
        slug: _str(j['slug']),
        page: _int(j['page']),
        total: _int(j['total']),
        source: _str(j['source']),
        error: _str(j['error']),
      );
}

class AnichinGenre {
  const AnichinGenre({this.name, this.slug});

  final String? name;
  final String? slug;

  factory AnichinGenre.fromJson(Map<String, dynamic> j) =>
      AnichinGenre(name: _str(j['name']), slug: _str(j['slug']));
}

/// Referensi satu episode di daftar episode detail/episode.
class AnichinEpisodeRef {
  const AnichinEpisodeRef({
    required this.slug,
    this.name,
    this.subtitle,
    this.date,
    this.episode,
    this.thumbnail,
  });

  final String slug;
  final String? name;
  final String? subtitle;
  final String? date;
  final String? episode;
  final String? thumbnail;
}

class AnichinAnimeDetail {
  const AnichinAnimeDetail({
    required this.name,
    this.thumbnail,
    this.genres = const [],
    this.rating,
    this.sinopsis = '',
    this.episodes = const [],
    this.info = const {},
  });

  final String name;
  final String? thumbnail;
  final List<String> genres;
  final String? rating;
  final String sinopsis;
  final List<AnichinEpisodeRef> episodes;

  /// Sisa field info dari situs sumber (status, studio, tipe, dll),
  /// key-nya lowercase_underscore.
  final Map<String, String> info;
}

class AnichinPlayer {
  const AnichinPlayer({required this.name, required this.url});

  final String name;
  final String url;
}

class AnichinEpisodeDetail {
  const AnichinEpisodeDetail({
    required this.name,
    this.root,
    this.thumbnail,
    this.genres = const [],
    this.rating,
    this.sinopsis = '',
    this.episodes = const [],
    this.players = const [],
    this.info = const {},
  });

  final String name;

  /// Slug anime induknya (buat balik ke halaman detail).
  final String? root;
  final String? thumbnail;
  final List<String> genres;
  final String? rating;
  final String sinopsis;
  final List<AnichinEpisodeRef> episodes;

  /// Embed mirror (iframe), bukan link video langsung.
  final List<AnichinPlayer> players;
  final Map<String, String> info;
}

class AnichinMedia {
  const AnichinMedia({this.quality, this.url});

  final String? quality;
  final String? url;

  factory AnichinMedia.fromJson(Map<String, dynamic> j) =>
      AnichinMedia(quality: _str(j['quality']), url: _str(j['url']));
}

/// GET /video-source/{slug}
class AnichinVideoSource {
  const AnichinVideoSource({this.title, this.hls, this.medias = const []});

  final String? title;
  final String? hls;
  final List<AnichinMedia> medias;

  factory AnichinVideoSource.fromJson(Map<String, dynamic> j) => AnichinVideoSource(
        title: _str(j['title']),
        hls: _str(j['hls']),
        medias: (j['medias'] is List ? j['medias'] as List : const [])
            .whereType<Map>()
            .map((m) => AnichinMedia.fromJson(Map<String, dynamic>.from(m)))
            .toList(),
      );
}

/// Model film MovieBox (JSON dari server moviebox-flask).

/// movieId film di riwayat / favorit / nobar / mini player: `moviebox_<id>`.
const String kMbMovieIdPrefix = 'moviebox_';

/// episodeId film (riwayat, download, nobar): `moviebox:<id>`.
const String kMbEpisodePrefix = 'moviebox:';

bool isMbMovieId(String movieId) => movieId.startsWith(kMbMovieIdPrefix);
bool isMbEpisodeId(String episodeId) => episodeId.startsWith(kMbEpisodePrefix);

/// Id MovieBox asli dari movieId (`moviebox_123` -> `123`) atau episodeId.
String mbRawId(String id) {
  if (id.startsWith(kMbMovieIdPrefix)) return id.substring(kMbMovieIdPrefix.length);
  if (id.startsWith(kMbEpisodePrefix)) return id.substring(kMbEpisodePrefix.length);
  return id;
}

String? _s(Object? v) {
  if (v == null) return null;
  final t = v.toString().trim();
  return (t.isEmpty || t == 'None' || t == 'null') ? null : t;
}

int? _i(Object? v) => v is num ? v.toInt() : int.tryParse('${v ?? ''}');

double? _d(Object? v) => v is num ? v.toDouble() : double.tryParse('${v ?? ''}');

/// Kartu film (daftar /movies & hasil /search).
class MbItem {
  const MbItem({
    required this.id,
    this.title,
    this.cover,
    this.rating,
    this.year,
    this.subjectType,
  });

  final String id;
  final String? title;
  final String? cover;
  final String? rating;
  final String? year;

  /// 1 = film. null = tidak diketahui (daftar /movies memang khusus film).
  final int? subjectType;

  bool get isMovie => subjectType == null || subjectType == 1;

  factory MbItem.fromJson(Map<String, dynamic> j) {
    final release = _s(j['release_date']);
    return MbItem(
      id: _s(j['subject_id']) ?? '',
      title: _s(j['title']),
      cover: _s(j['cover']),
      rating: _s(j['rating']) ?? _s(j['imdb_rating']),
      year: _s(j['year']) ?? (release != null && release.length >= 4 ? release.substring(0, 4) : null),
      subjectType: _i(j['subject_type']),
    );
  }
}

class MbDub {
  const MbDub({required this.id, this.name});

  final String id;
  final String? name;

  factory MbDub.fromJson(Map<String, dynamic> j) =>
      MbDub(id: _s(j['subject_id']) ?? '', name: _s(j['lang_name']) ?? _s(j['language']));
}

/// Detail film (/detail/{id}).
class MbDetail {
  const MbDetail({
    required this.id,
    this.title,
    this.description,
    this.releaseDate,
    this.duration,
    this.rating,
    this.genre,
    this.country,
    this.cover,
    this.detailPath,
    this.subjectType,
    this.dubs = const [],
  });

  final String id;
  final String? title;
  final String? description;
  final String? releaseDate;

  /// Teks dari MovieBox, mis. "2h 25m" (bukan angka detik).
  final String? duration;
  final String? rating;
  final String? genre;
  final String? country;
  final String? cover;
  final String? detailPath;
  final int? subjectType;
  final List<MbDub> dubs;

  String? get year => (releaseDate != null && releaseDate!.length >= 4) ? releaseDate!.substring(0, 4) : null;

  factory MbDetail.fromJson(Map<String, dynamic> j) => MbDetail(
        id: _s(j['subject_id']) ?? '',
        title: _s(j['title']),
        description: _s(j['description']),
        releaseDate: _s(j['release_date']),
        duration: _s(j['duration']),
        rating: _s(j['imdb_rating']),
        genre: _s(j['genre']),
        country: _s(j['country']),
        cover: _s(j['cover']),
        detailPath: _s(j['detail_path']),
        subjectType: _i(j['subject_type']),
        dubs: [
          for (final d in (j['dubs'] as List? ?? const []))
            if (d is Map) MbDub.fromJson(Map<String, dynamic>.from(d)),
        ].where((d) => d.id.isNotEmpty).toList(),
      );
}

/// Satu link video (/api/stream/{id}).
class MbStream {
  const MbStream({
    required this.url,
    required this.quality,
    required this.qualityValue,
    this.format,
    this.codec,
    this.sizeMb,
    this.source,
    this.headers = const {},
  });

  final String url;

  /// Label tampil, mis. "1080p".
  final String quality;
  final int qualityValue;
  final String? format;
  final String? codec;
  final double? sizeMb;
  final String? source;

  /// Header wajib untuk CDN (Referer/Origin atau Cookie bertanda tangan).
  final Map<String, String> headers;

  bool get isDash => (format ?? '').toUpperCase() == 'DASH' || url.toLowerCase().contains('.mpd');
  bool get isHevc =>
      (codec ?? '').toLowerCase().contains('hevc') || url.toLowerCase().contains('h265');

  factory MbStream.fromJson(Map<String, dynamic> j) {
    final h = <String, String>{};
    final raw = j['headers'];
    if (raw is Map) {
      raw.forEach((k, v) {
        if (k != null && v != null) h['$k'] = '$v';
      });
    }
    return MbStream(
      url: _s(j['url']) ?? '',
      quality: _s(j['quality']) ?? 'Auto',
      qualityValue: _i(j['quality_value']) ?? 0,
      format: _s(j['format']),
      codec: _s(j['codec']),
      sizeMb: _d(j['size_mb']),
      source: _s(j['source']),
      headers: h,
    );
  }
}

/// Satu subtitle (/api/stream/{id}/captions).
class MbCaption {
  const MbCaption({required this.url, required this.language, this.code});

  final String url;
  final String language;
  final String? code;

  bool get isIndonesian {
    final c = (code ?? '').toLowerCase();
    return c == 'in' || c == 'id' || language.toLowerCase().contains('indo');
  }

  factory MbCaption.fromJson(Map<String, dynamic> j) => MbCaption(
        url: _s(j['url']) ?? '',
        language: _s(j['language']) ?? 'Subtitle',
        code: _s(j['code']),
      );
}

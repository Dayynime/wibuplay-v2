import 'episode_item.dart';

class StreamServer {
  const StreamServer({this.link, this.quality, this.type, this.name});

  final String? link;
  final String? quality;
  final String? type;
  final String? name;
}

class StreamData {
  const StreamData({
    this.episode,
    this.episodeNext,
    this.hasNextEpisode = false,
    this.server = const [],
  });

  final EpisodeItem? episode;
  final EpisodeItem? episodeNext;
  final bool hasNextEpisode;
  final List<StreamServer> server;
}

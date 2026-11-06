import 'audiobook.dart';

class Episode {
  Episode({
    required this.guid,
    required this.feedUrl,
    required this.title,
    required this.audioUrl,
    this.description = '',
    this.published,
    this.durationMs = 0,
    this.imageUrl,
    this.link,
    this.podcastTitle = '',
    this.podcastImage,
  });

  final String guid;
  final String feedUrl;
  final String title;
  final String audioUrl;
  final String description;
  final DateTime? published;
  final int durationMs;
  final String? imageUrl;
  final String? link;

  /// Copied from the show so an episode can be listed on its own.
  final String podcastTitle;
  final String? podcastImage;

  String? get art => imageUrl ?? podcastImage;

  /// Whether every word of [query] appears in the title or show notes.
  bool matches(String query) => query.toLowerCase().split(RegExp(r'\s+')).every(_haystack.contains);

  /// Title and notes in lower case, made once: search runs over every episode
  /// of a show on each keystroke.
  late final String _haystack = '$title\n$description'.toLowerCase();

  Map<String, dynamic> toJson() => {
        'guid': guid,
        'feedUrl': feedUrl,
        'title': title,
        'audioUrl': audioUrl,
        'description': description,
        'published': published?.toIso8601String(),
        'durationMs': durationMs,
        'imageUrl': imageUrl,
        'link': link,
        'podcastTitle': podcastTitle,
        'podcastImage': podcastImage,
      };

  factory Episode.fromJson(Map<String, dynamic> j) => Episode(
        guid: j['guid'] ?? '',
        feedUrl: j['feedUrl'] ?? '',
        title: j['title'] ?? '',
        audioUrl: j['audioUrl'] ?? '',
        description: j['description'] ?? '',
        published: DateTime.tryParse(j['published'] ?? ''),
        durationMs: j['durationMs'] ?? 0,
        imageUrl: j['imageUrl'],
        link: j['link'],
        podcastTitle: j['podcastTitle'] ?? '',
        podcastImage: j['podcastImage'],
      );
}

class Podcast {
  Podcast({
    required this.feedUrl,
    required this.title,
    this.author = '',
    this.description = '',
    this.imageUrl,
    this.link,
    this.categories = const [],
    this.episodes = const [],
    this.updatedAt,
    this.subscribedAt,
  });

  final String feedUrl;
  String title;
  String author;
  String description;
  String? imageUrl;
  String? link;
  List<String> categories;
  List<Episode> episodes;
  DateTime? updatedAt;
  DateTime? subscribedAt;

  Map<String, dynamic> toJson() => {
        'feedUrl': feedUrl,
        'title': title,
        'author': author,
        'description': description,
        'imageUrl': imageUrl,
        'link': link,
        'categories': categories,
        // Keep the newest episodes only; the feed has the rest.
        'episodes': episodes.take(150).map((e) => e.toJson()).toList(),
        'updatedAt': updatedAt?.toIso8601String(),
        'subscribedAt': subscribedAt?.toIso8601String(),
      };

  factory Podcast.fromJson(Map<String, dynamic> j) => Podcast(
        feedUrl: j['feedUrl'] ?? '',
        title: j['title'] ?? '',
        author: j['author'] ?? '',
        description: j['description'] ?? '',
        imageUrl: j['imageUrl'],
        link: j['link'],
        categories: ((j['categories'] as List?) ?? const []).cast<String>(),
        episodes: ((j['episodes'] as List?) ?? const []).whereType<Map>().map((e) => Episode.fromJson(Map<String, dynamic>.from(e))).toList(),
        updatedAt: DateTime.tryParse(j['updatedAt'] ?? ''),
        subscribedAt: DateTime.tryParse(j['subscribedAt'] ?? ''),
      );
}

/// Your history with one episode.
class EpisodeState {
  EpisodeState({required this.episode, this.posMs = 0, this.played = false, this.localPath, DateTime? updatedAt, UserMark? mark})
      : updatedAt = updatedAt ?? DateTime.now(),
        mark = mark ?? UserMark();

  Episode episode;
  int posMs;
  bool played;
  String? localPath;
  DateTime updatedAt;
  final UserMark mark;

  Map<String, dynamic> toJson() => {
        'episode': episode.toJson(),
        'posMs': posMs,
        'played': played,
        'localPath': localPath,
        'updatedAt': updatedAt.toIso8601String(),
        'mark': mark.toJson(),
      };

  factory EpisodeState.fromJson(Map<String, dynamic> j) => EpisodeState(
        episode: Episode.fromJson(Map<String, dynamic>.from(j['episode'] ?? const {})),
        posMs: j['posMs'] ?? 0,
        played: j['played'] ?? false,
        localPath: j['localPath'],
        updatedAt: DateTime.tryParse(j['updatedAt'] ?? ''),
        mark: UserMark.fromJson(j['mark'] == null ? null : Map<String, dynamic>.from(j['mark'])),
      );
}

/// A show from the directory, before its feed is loaded.
class PodcastHit {
  PodcastHit({required this.title, this.id = '', this.author = '', this.artwork, this.feedUrl, this.genre = '', this.episodes = 0});
  final String id;
  final String title;
  final String author;
  final String? artwork;
  final String? feedUrl;
  final String genre;
  final int episodes;
}

/// How a show's episodes are ordered.
enum EpisodeSort {
  newest('Newest first', 'Newest'),
  oldest('Oldest first', 'Oldest'),
  az('Title A–Z', 'A–Z'),
  za('Title Z–A', 'Z–A');

  const EpisodeSort(this.label, this.short);
  final String label;
  final String short;

  static EpisodeSort parse(String? name) => values.where((v) => v.name == name).firstOrNull ?? newest;

  /// [eps] in this order. Feeds list newest first, so the date orders need no sorting.
  List<Episode> apply(List<Episode> eps) => switch (this) {
        newest => eps,
        oldest => eps.reversed.toList(),
        az => [...eps]..sort((a, b) => naturalCompare(a.title, b.title)),
        za => [...eps]..sort((a, b) => naturalCompare(b.title, a.title)),
      };
}

/// Compares ignoring case, with runs of digits by their value, so "Episode 9"
/// comes before "Episode 10" and "#2" before "#11".
int naturalCompare(String a, String b) {
  a = a.toLowerCase();
  b = b.toLowerCase();
  bool digit(int c) => c >= 48 && c <= 57;
  var i = 0, j = 0;
  while (i < a.length && j < b.length) {
    final ca = a.codeUnitAt(i), cb = b.codeUnitAt(j);
    if (digit(ca) && digit(cb)) {
      // Skip leading zeros, then the longer run of digits is the bigger number.
      while (i < a.length - 1 && a.codeUnitAt(i) == 48 && digit(a.codeUnitAt(i + 1))) {
        i++;
      }
      while (j < b.length - 1 && b.codeUnitAt(j) == 48 && digit(b.codeUnitAt(j + 1))) {
        j++;
      }
      final si = i, sj = j;
      while (i < a.length && digit(a.codeUnitAt(i))) {
        i++;
      }
      while (j < b.length && digit(b.codeUnitAt(j))) {
        j++;
      }
      if (i - si != j - sj) return (i - si) - (j - sj);
      final c = a.substring(si, i).compareTo(b.substring(sj, j));
      if (c != 0) return c;
      continue;
    }
    if (ca != cb) return ca - cb;
    i++;
    j++;
  }
  return (a.length - i) - (b.length - j);
}

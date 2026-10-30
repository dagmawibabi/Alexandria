/// A note taken while listening; [ms] is where in [track] it was written.
class AudioNote {
  AudioNote({required this.text, this.track = 0, this.ms = 0, DateTime? at}) : at = at ?? DateTime.now();

  String text;
  final int track;
  final int ms;
  final DateTime at;

  Map<String, dynamic> toJson() => {'text': text, 'track': track, 'ms': ms, 'at': at.toIso8601String()};

  factory AudioNote.fromJson(Map<String, dynamic> j) => AudioNote(text: j['text'] ?? '', track: j['track'] ?? 0, ms: j['ms'] ?? 0, at: DateTime.tryParse(j['at'] ?? ''));
}

/// What you think of something you listen to: rating, favourite and notes.
class UserMark {
  UserMark({this.rating = 0, this.favorite = false, List<AudioNote>? notes}) : notes = notes ?? [];

  int rating;
  bool favorite;
  final List<AudioNote> notes;

  bool get isEmpty => rating == 0 && !favorite && notes.isEmpty;

  Map<String, dynamic> toJson() => {'rating': rating, 'favorite': favorite, 'notes': notes.map((n) => n.toJson()).toList()};

  factory UserMark.fromJson(Map<String, dynamic>? j) => UserMark(
        rating: j?['rating'] ?? 0,
        favorite: j?['favorite'] ?? false,
        notes: ((j?['notes'] as List?) ?? const []).whereType<Map>().map((e) => AudioNote.fromJson(Map<String, dynamic>.from(e))).toList(),
      );
}

/// One playable file: a local path inside app storage, or a stream URL.
class AudioTrack {
  AudioTrack({required this.title, required this.path, this.ms = 0, this.url});

  String title;

  /// What plays: a local file, or the stream URL until it is downloaded.
  String path;

  /// Where a downloaded track came from, so the download can be undone.
  String? url;

  /// Length in milliseconds; 0 until known.
  int ms;

  bool get remote => path.startsWith('http://') || path.startsWith('https://');

  bool get downloaded => url != null && !remote;

  Map<String, dynamic> toJson() => {'title': title, 'path': path, 'ms': ms, if (url != null) 'url': url};

  factory AudioTrack.fromJson(Map<String, dynamic> j) => AudioTrack(title: j['title'] ?? '', path: j['path'] ?? '', ms: (j['ms'] ?? 0) as int, url: j['url']);
}

class Audiobook {
  Audiobook({
    required this.id,
    required this.title,
    required this.tracks,
    this.author = '',
    this.narrator = '',
    this.description = '',
    this.year = '',
    this.coverPath,
    this.coverUrl,
    this.source = 'local',
    this.sourceKey = '',
    this.trackIndex = 0,
    this.positionMs = 0,
    this.speed = 1,
    DateTime? addedAt,
    this.lastPlayedAt,
    this.finished = false,
    this.finishedAt,
    this.bookId,
    UserMark? mark,
    this.folderIds = const [],
  })  : addedAt = addedAt ?? DateTime.now(),
        mark = mark ?? UserMark();

  final String id;
  String title;
  String author;
  String narrator;
  String description;
  String year;
  String? coverPath;
  String? coverUrl;

  /// 'local' (your files), 'librivox' or 'archive' (Internet Archive).
  final String source;
  final String sourceKey;
  final List<AudioTrack> tracks;

  int trackIndex;
  int positionMs;
  double speed;
  final DateTime addedAt;
  DateTime? lastPlayedAt;
  bool finished;
  DateTime? finishedAt;

  /// The ebook in the library this narrates, for reading along.
  String? bookId;

  final UserMark mark;
  List<String> folderIds;

  int get totalMs => tracks.fold(0, (a, t) => a + t.ms);

  /// Whether every track's length is known, so time-based progress is exact.
  bool get timed => tracks.isNotEmpty && tracks.every((t) => t.ms > 0);

  int get elapsedMs => tracks.take(trackIndex.clamp(0, tracks.length)).fold(0, (a, t) => a + t.ms) + positionMs;

  double get progress {
    if (finished) return 1;
    if (tracks.isEmpty) return 0;
    if (timed) return (elapsedMs / totalMs).clamp(0.0, 1.0);
    final cur = tracks[trackIndex.clamp(0, tracks.length - 1)];
    final within = cur.ms > 0 ? positionMs / cur.ms : 0;
    return ((trackIndex + within) / tracks.length).clamp(0.0, 1.0);
  }

  bool get streaming => tracks.any((t) => t.remote);

  /// Streamed books whose every track is now saved on the device.
  bool get offline => tracks.isNotEmpty && tracks.every((t) => !t.remote) && tracks.any((t) => t.downloaded);

  bool get downloadable => tracks.any((t) => t.remote);

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'author': author,
        'narrator': narrator,
        'description': description,
        'year': year,
        'coverPath': coverPath,
        'coverUrl': coverUrl,
        'source': source,
        'sourceKey': sourceKey,
        'tracks': tracks.map((t) => t.toJson()).toList(),
        'trackIndex': trackIndex,
        'positionMs': positionMs,
        'speed': speed,
        'addedAt': addedAt.toIso8601String(),
        'lastPlayedAt': lastPlayedAt?.toIso8601String(),
        'finished': finished,
        'finishedAt': finishedAt?.toIso8601String(),
        'bookId': bookId,
        'mark': mark.toJson(),
        'folderIds': folderIds,
      };

  factory Audiobook.fromJson(Map<String, dynamic> j) => Audiobook(
        id: j['id'],
        title: j['title'] ?? '',
        author: j['author'] ?? '',
        narrator: j['narrator'] ?? '',
        description: j['description'] ?? '',
        year: j['year'] ?? '',
        coverPath: j['coverPath'],
        coverUrl: j['coverUrl'],
        source: j['source'] ?? 'local',
        sourceKey: j['sourceKey'] ?? '',
        tracks: ((j['tracks'] as List?) ?? const []).whereType<Map>().map((e) => AudioTrack.fromJson(Map<String, dynamic>.from(e))).toList(),
        trackIndex: j['trackIndex'] ?? 0,
        positionMs: j['positionMs'] ?? 0,
        speed: (j['speed'] ?? 1).toDouble(),
        addedAt: DateTime.tryParse(j['addedAt'] ?? ''),
        lastPlayedAt: DateTime.tryParse(j['lastPlayedAt'] ?? ''),
        finished: j['finished'] ?? false,
        finishedAt: DateTime.tryParse(j['finishedAt'] ?? ''),
        bookId: j['bookId'],
        mark: UserMark.fromJson(j['mark'] == null ? null : Map<String, dynamic>.from(j['mark'])),
        folderIds: ((j['folderIds'] as List?) ?? const []).cast<String>(),
      );
}

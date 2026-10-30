class Highlight {
  Highlight({
    required this.id,
    required this.bookId,
    required this.block,
    required this.start,
    required this.end,
    required this.text,
    this.color = 0,
    this.note = '',
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  final String id;
  final String bookId;
  final int block;
  final int start;
  final int end;
  final String text;

  /// Index into the highlight palette.
  int color;
  String note;
  final DateTime createdAt;

  Map<String, dynamic> toJson() => {
        'id': id,
        'bookId': bookId,
        'block': block,
        'start': start,
        'end': end,
        'text': text,
        'color': color,
        'note': note,
        'createdAt': createdAt.toIso8601String(),
      };

  factory Highlight.fromJson(Map<String, dynamic> j) => Highlight(
        id: j['id'],
        bookId: j['bookId'],
        block: j['block'],
        start: j['start'],
        end: j['end'],
        text: j['text'],
        color: j['color'] ?? 0,
        note: j['note'] ?? '',
        createdAt: DateTime.tryParse(j['createdAt'] ?? ''),
      );
}

class Bookmark {
  Bookmark({
    required this.id,
    required this.bookId,
    required this.block,
    required this.label,
    this.progress = 0,
    this.excerpt = '',
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  final String id;
  final String bookId;
  final int block;
  String label;

  /// The passage this bookmark was made from (selection or highlight), if any.
  final String excerpt;
  final double progress;
  final DateTime createdAt;

  Map<String, dynamic> toJson() => {
        'id': id,
        'bookId': bookId,
        'block': block,
        'label': label,
        'progress': progress,
        'excerpt': excerpt,
        'createdAt': createdAt.toIso8601String(),
      };

  factory Bookmark.fromJson(Map<String, dynamic> j) => Bookmark(
        id: j['id'],
        bookId: j['bookId'],
        block: j['block'],
        label: j['label'] ?? '',
        progress: (j['progress'] ?? 0).toDouble(),
        excerpt: j['excerpt'] ?? '',
        createdAt: DateTime.tryParse(j['createdAt'] ?? ''),
      );
}

class ReadingSession {
  ReadingSession({
    required this.bookId,
    required this.start,
    required this.seconds,
    this.words = 0,
    this.mode = 'scroll',
    this.label,
  });

  final String bookId;
  final DateTime start;
  int seconds;

  /// What was listened to, kept in case the audiobook or show is later removed.
  final String? label;

  /// Approximate words read (progress delta × book words).
  final int words;

  /// Reading: scroll | swipe | pdf | listen. Listening: audiobook | podcast | radio.
  final String mode;

  bool get listening => mode == 'audiobook' || mode == 'podcast' || mode == 'radio';

  Map<String, dynamic> toJson() =>
      {'b': bookId, 's': start.toIso8601String(), 'd': seconds, 'w': words, 'm': mode, if (label != null) 't': label};

  factory ReadingSession.fromJson(Map<String, dynamic> j) => ReadingSession(
        bookId: j['b'],
        start: DateTime.parse(j['s']),
        seconds: j['d'],
        words: j['w'] ?? 0,
        mode: j['m'] ?? 'scroll',
        label: j['t'],
      );
}

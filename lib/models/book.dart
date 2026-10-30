import 'audiobook.dart' show UserMark;

enum BookFormat { pdf, epub, docx }

enum ReadStatus { unread, reading, finished, abandoned }

BookFormat? formatFromPath(String path) {
  final p = path.toLowerCase();
  if (p.endsWith('.pdf')) return BookFormat.pdf;
  if (p.endsWith('.epub')) return BookFormat.epub;
  if (p.endsWith('.docx')) return BookFormat.docx;
  return null;
}

class Book {
  Book({
    required this.id,
    required this.title,
    required this.format,
    required this.path,
    this.author = '',
    this.coverPath,
    this.description = '',
    this.publisher = '',
    this.year = '',
    this.isbn = '',
    this.language = '',
    this.pageCount = 0,
    this.subjects = const [],
    this.folderIds = const [],
    this.tags = const [],
    DateTime? addedAt,
    this.lastOpenedAt,
    this.finishedAt,
    this.progress = 0,
    this.position = 0,
    this.positionOffset = 0,
    this.status = ReadStatus.unread,
    this.rating = 0,
    this.favorite = false,
    this.wordCount = 0,
    this.fileSize = 0,
    this.metadataFetched = false,
  }) : addedAt = addedAt ?? DateTime.now();

  final String id;
  String title;
  String author;
  final BookFormat format;
  String path;
  String? coverPath;
  String description;
  String publisher;
  String year;
  String isbn;
  String language;
  int pageCount;
  List<String> subjects;
  List<String> folderIds;
  List<String> tags;
  DateTime addedAt;
  DateTime? lastOpenedAt;
  DateTime? finishedAt;

  /// 0..1 through the book.
  double progress;

  /// Block index the reader was last at, and how far into it (0..1).
  int position;
  double positionOffset;
  ReadStatus status;
  int rating;
  bool favorite;
  int wordCount;
  int fileSize;
  bool metadataFetched;

  String get formatLabel => format.name.toUpperCase();

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'author': author,
        'format': format.name,
        'path': path,
        'coverPath': coverPath,
        'description': description,
        'publisher': publisher,
        'year': year,
        'isbn': isbn,
        'language': language,
        'pageCount': pageCount,
        'subjects': subjects,
        'folderIds': folderIds,
        'tags': tags,
        'addedAt': addedAt.toIso8601String(),
        'lastOpenedAt': lastOpenedAt?.toIso8601String(),
        'finishedAt': finishedAt?.toIso8601String(),
        'progress': progress,
        'position': position,
        'positionOffset': positionOffset,
        'status': status.name,
        'rating': rating,
        'favorite': favorite,
        'wordCount': wordCount,
        'fileSize': fileSize,
        'metadataFetched': metadataFetched,
      };

  factory Book.fromJson(Map<String, dynamic> j) => Book(
        id: j['id'],
        title: j['title'] ?? 'Untitled',
        author: j['author'] ?? '',
        format: BookFormat.values.byName(j['format']),
        path: j['path'],
        coverPath: j['coverPath'],
        description: j['description'] ?? '',
        publisher: j['publisher'] ?? '',
        year: j['year'] ?? '',
        isbn: j['isbn'] ?? '',
        language: j['language'] ?? '',
        pageCount: j['pageCount'] ?? 0,
        subjects: List<String>.from(j['subjects'] ?? const []),
        folderIds: List<String>.from(j['folderIds'] ?? const []),
        tags: List<String>.from(j['tags'] ?? const []),
        addedAt: DateTime.tryParse(j['addedAt'] ?? ''),
        lastOpenedAt: DateTime.tryParse(j['lastOpenedAt'] ?? ''),
        finishedAt: DateTime.tryParse(j['finishedAt'] ?? ''),
        progress: (j['progress'] ?? 0).toDouble(),
        position: j['position'] ?? 0,
        positionOffset: (j['positionOffset'] ?? 0).toDouble(),
        status: ReadStatus.values.asNameMap()[j['status']] ?? ReadStatus.unread,
        rating: j['rating'] ?? 0,
        favorite: j['favorite'] ?? false,
        wordCount: j['wordCount'] ?? 0,
        fileSize: j['fileSize'] ?? 0,
        metadataFetched: j['metadataFetched'] ?? false,
      );
}

class Folder {
  Folder({required this.id, required this.name, this.color = 0xFFFF5A1F, this.icon = 0, this.coverPath});

  final String id;
  String name;
  int color;
  int icon;

  /// A picture you chose. Without one, the folder shows what's inside it.
  String? coverPath;

  Map<String, dynamic> toJson() => {'id': id, 'name': name, 'color': color, 'icon': icon, if (coverPath != null) 'coverPath': coverPath};

  factory Folder.fromJson(Map<String, dynamic> j) =>
      Folder(id: j['id'], name: j['name'], color: j['color'] ?? 0xFFFF5A1F, icon: j['icon'] ?? 0, coverPath: j['coverPath']);
}

/// A book found online and saved for later (wishlist).
class SavedBook {
  SavedBook({
    required this.key,
    required this.title,
    this.author = '',
    this.coverUrl,
    this.year = '',
    this.downloadUrl,
    this.source = 'openlibrary',
    DateTime? savedAt,
    UserMark? mark,
    this.folderIds = const [],
    this.wanted = true,
  })  : savedAt = savedAt ?? DateTime.now(),
        mark = mark ?? UserMark();

  final String key;
  final String title;
  final String author;
  final String? coverUrl;
  final String year;
  final String? downloadUrl;
  final String source;
  final DateTime savedAt;

  /// Your rating, favourite and notes, before you own a copy.
  final UserMark mark;
  List<String> folderIds;

  /// On the want-to-read list. False for a book you only rated, hearted or filed.
  bool wanted;

  Map<String, dynamic> toJson() => {
        'wanted': wanted,
        'mark': mark.toJson(),
        'folderIds': folderIds,
        'key': key,
        'title': title,
        'author': author,
        'coverUrl': coverUrl,
        'year': year,
        'downloadUrl': downloadUrl,
        'source': source,
        'savedAt': savedAt.toIso8601String(),
      };

  factory SavedBook.fromJson(Map<String, dynamic> j) => SavedBook(
        key: j['key'],
        title: j['title'],
        author: j['author'] ?? '',
        coverUrl: j['coverUrl'],
        year: j['year'] ?? '',
        downloadUrl: j['downloadUrl'],
        source: j['source'] ?? 'openlibrary',
        savedAt: DateTime.tryParse(j['savedAt'] ?? ''),
        mark: UserMark.fromJson(j['mark'] == null ? null : Map<String, dynamic>.from(j['mark'])),
        folderIds: ((j['folderIds'] as List?) ?? const []).cast<String>(),
        wanted: j['wanted'] ?? true,
      );
}

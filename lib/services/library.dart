import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../core/settings.dart';
import '../models/annotations.dart';
import '../models/book.dart';
import '../models/doc.dart';
import 'audio.dart';
import 'backup.dart';
import 'metadata.dart';
import 'parsers/docx_parser.dart';
import 'parsers/epub_parser.dart';
import 'parsers/pdf_parser.dart';
import 'podcasts.dart';
import 'radio.dart';
import 'storage.dart';

String newId() => '${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}${Random().nextInt(1 << 20).toRadixString(36)}';

class Library extends ChangeNotifier {
  Library._();
  static final Library i = Library._();

  final List<Book> books = [];
  final List<Folder> folders = [];
  final List<Highlight> highlights = [];
  final List<Bookmark> bookmarks = [];
  final List<ReadingSession> sessions = [];
  final List<SavedBook> saved = [];

  final Map<String, ParsedDoc> _docs = {};

  /// Ids currently importing, for progress UI.
  final ValueNotifier<Map<String, double>> importing = ValueNotifier({});

  Future<void> load() async {
    List<T> read<T>(dynamic j, T Function(Map<String, dynamic>) f) =>
        j is List ? j.whereType<Map>().map((e) => f(Map<String, dynamic>.from(e))).toList() : <T>[];
    books.addAll(read(await Storage.readJson('books'), Book.fromJson));
    folders.addAll(read(await Storage.readJson('folders'), Folder.fromJson));
    highlights.addAll(read(await Storage.readJson('highlights'), Highlight.fromJson));
    bookmarks.addAll(read(await Storage.readJson('bookmarks'), Bookmark.fromJson));
    sessions.addAll(read(await Storage.readJson('sessions'), ReadingSession.fromJson));
    saved.addAll(read(await Storage.readJson('saved'), SavedBook.fromJson));
    notifyListeners();
  }

  final Map<String, Timer> _pending = {};

  /// Debounced persistence per collection.
  void _persist(String name) {
    _pending[name]?.cancel();
    _pending[name] = Timer(const Duration(milliseconds: 400), () {
      final List list = switch (name) {
        'books' => books,
        'folders' => folders,
        'highlights' => highlights,
        'bookmarks' => bookmarks,
        'sessions' => sessions,
        _ => saved,
      };
      Storage.writeJson(name, list.map((e) => e.toJson()).toList());
    });
  }

  void touch(Book b) {
    _persist('books');
    notifyListeners();
  }

  Book? byId(String id) => books.where((b) => b.id == id).firstOrNull;

  /// Your copy of a catalogue book. A file's own title often differs from the
  /// catalogue's, and copies from before [Book.sourceKey] only have a title to go on.
  Book? copyOf(BookInfo info) {
    String norm(String s) => s.toLowerCase().replaceAll(RegExp(r'[^a-z0-9 ]'), ' ').replaceAll(RegExp(r'\s+'), ' ').trim();
    final title = norm(info.title);
    return books.where((b) => info.key.isNotEmpty && b.sourceKey == info.key).firstOrNull ?? books.where((b) => norm(b.title) == title).firstOrNull;
  }

  // ---------------- import ----------------

  /// Imports a file into the library (copied into app storage).
  /// Returns the existing book if the same file was imported before.
  Future<Book> importFile(String sourcePath, {String? displayName}) async {
    final format = formatFromPath(displayName ?? sourcePath) ?? formatFromPath(sourcePath);
    if (format == null) throw const FormatException('Unsupported file. Alexandria reads PDF, EPUB and DOCX.');
    final src = File(sourcePath);
    final bytes = await src.readAsBytes();
    final id = sha1.convert(bytes.length > 4 << 20 ? [...bytes.sublist(0, 4 << 20), ...utf8.encode('${bytes.length}')] : bytes).toString().substring(0, 16);

    final existing = byId(id);
    if (existing != null) return existing;

    importing.value = {...importing.value, id: 0};
    try {
      final dest = File(p.join(Storage.books.path, '$id.${format.name}'));
      await dest.writeAsBytes(bytes, flush: true);
      final fallbackTitle = _titleFromFilename(displayName ?? sourcePath);
      final book = Book(id: id, title: fallbackTitle, format: format, path: dest.path, fileSize: bytes.length);

      final doc = await _parse(book, onProgress: (v) => importing.value = {...importing.value, id: v});
      if ((doc.title ?? '').trim().isNotEmpty) book.title = doc.title!.trim();
      book.author = (doc.author ?? '').trim();
      book.description = doc.description ?? '';
      book.publisher = doc.publisher ?? '';
      book.language = doc.language ?? '';
      book.year = doc.year ?? '';
      book.isbn = doc.isbn ?? '';
      book.pageCount = doc.pageCount;
      book.wordCount = doc.wordCount;
      if (book.pageCount == 0) book.pageCount = (doc.wordCount / 275).ceil();
      if (doc.coverBytes != null) {
        final c = File(p.join(Storage.covers.path, '$id.img'));
        await c.writeAsBytes(doc.coverBytes!);
        book.coverPath = c.path;
      }
      books.insert(0, book);
      _persist('books');
      notifyListeners();

      if (Settings.i.autoFetchMetadata) unawaited(enrich(book, onlyMissing: true));
      return book;
    } finally {
      importing.value = Map.of(importing.value)..remove(id);
    }
  }

  String _titleFromFilename(String path) {
    var name = p.basenameWithoutExtension(path);
    name = name.replaceAll(RegExp(r'[_\.]+'), ' ').replaceAll(RegExp(r'\s*\(z-lib.*?\)|\s*\[.*?\]'), '').trim();
    return name.isEmpty ? 'Untitled' : name;
  }

  Future<ParsedDoc> _parse(Book book, {void Function(double)? onProgress}) async {
    final imgDir = Directory(p.join(Storage.images.path, book.id));
    final ParsedDoc doc = switch (book.format) {
      BookFormat.epub => await parseEpub(await File(book.path).readAsBytes(), imgDir),
      BookFormat.docx => await parseDocx(await File(book.path).readAsBytes(), imgDir),
      BookFormat.pdf => await parsePdf(book.path, onProgress: onProgress),
    };
    await File(p.join(Storage.cache.path, '${book.id}.json')).writeAsString(jsonEncode(doc.toJson()));
    _docs[book.id] = doc;
    return doc;
  }

  /// The parsed text model for [book], from memory, disk cache, or a fresh parse.
  Future<ParsedDoc> doc(Book book) async {
    final mem = _docs[book.id];
    if (mem != null) return mem;
    final f = File(p.join(Storage.cache.path, '${book.id}.json'));
    if (await f.exists()) {
      try {
        final j = jsonDecode(await f.readAsString());
        if (j['v'] == 2) return _docs[book.id] = ParsedDoc.fromJson(j);
      } catch (_) {}
    }
    return _parse(book);
  }

  /// Fetches cover and info from Open Library / Google Books.
  Future<bool> enrich(Book book, {bool onlyMissing = false, BookInfo? choice}) async {
    final info = choice ?? await Metadata.best(book.title, book.author, isbn: book.isbn);
    if (info == null) return false;
    void fill(String cur, String? v, void Function(String) set) {
      if (v == null || v.isEmpty) return;
      if (!onlyMissing || cur.isEmpty) set(v);
    }

    if (choice != null) {
      book.title = info.title;
    }
    fill(book.author, info.author, (v) => book.author = v);
    fill(book.description, info.description, (v) => book.description = v);
    fill(book.publisher, info.publisher, (v) => book.publisher = v);
    fill(book.year, info.year, (v) => book.year = v);
    fill(book.isbn, info.isbn, (v) => book.isbn = v);
    if (info.subjects.isNotEmpty && (!onlyMissing || book.subjects.isEmpty)) book.subjects = info.subjects.take(8).toList();
    if (info.pageCount > 0 && book.format != BookFormat.pdf) book.pageCount = info.pageCount;

    final needCover = book.coverPath == null || !onlyMissing || book.format != BookFormat.epub;
    if (info.coverUrl != null && needCover) {
      final bytes = await Metadata.download(info.coverUrl!);
      if (bytes != null && bytes.length > 2000) {
        final c = File(p.join(Storage.covers.path, '${book.id}-${DateTime.now().millisecondsSinceEpoch}.img'));
        await c.writeAsBytes(bytes);
        book.coverPath = c.path;
      }
    }
    book.metadataFetched = true;
    touch(book);
    return true;
  }

  Future<void> setCover(Book book, String imagePath) async {
    final c = File(p.join(Storage.covers.path, '${book.id}-${DateTime.now().millisecondsSinceEpoch}.img'));
    await File(imagePath).copy(c.path);
    book.coverPath = c.path;
    touch(book);
  }

  Future<void> remove(Book book) async {
    books.remove(book);
    highlights.removeWhere((h) => h.bookId == book.id);
    bookmarks.removeWhere((h) => h.bookId == book.id);
    _docs.remove(book.id);
    for (final f in [File(book.path), File(p.join(Storage.cache.path, '${book.id}.json'))]) {
      if (await f.exists()) await f.delete();
    }
    final img = Directory(p.join(Storage.images.path, book.id));
    if (await img.exists()) await img.delete(recursive: true);
    for (final n in ['books', 'highlights', 'bookmarks']) {
      _persist(n);
    }
    notifyListeners();
  }

  // ---------------- folders ----------------

  Folder addFolder(String name, {int? color}) {
    final f = Folder(id: newId(), name: name, color: color ?? accents[folders.length % accents.length].toARGB32());
    folders.add(f);
    _persist('folders');
    notifyListeners();
    return f;
  }

  void renameFolder(Folder f, String name) {
    f.name = name;
    _persist('folders');
    notifyListeners();
  }

  void recolorFolder(Folder f, int color) {
    f.color = color;
    _persist('folders');
    notifyListeners();
  }

  /// Sets a folder's picture, or clears it with null.
  Future<void> setFolderCover(Folder f, String? file) async {
    final old = f.coverPath;
    if (file == null) {
      f.coverPath = null;
    } else {
      final c = File(p.join(Storage.covers.path, 'folder-${f.id}-${DateTime.now().millisecondsSinceEpoch}.img'));
      await File(file).copy(c.path);
      f.coverPath = c.path;
    }
    if (old != null) File(old).delete().ignore();
    _persist('folders');
    notifyListeners();
  }

  void deleteFolder(Folder f) {
    folders.remove(f);
    if (f.coverPath != null) File(f.coverPath!).delete().ignore();
    for (final b in books) {
      if (b.folderIds.contains(f.id)) b.folderIds = [...b.folderIds]..remove(f.id);
    }
    for (final s in saved) {
      if (s.folderIds.contains(f.id)) s.folderIds = [...s.folderIds]..remove(f.id);
    }
    AudioLibrary.i.removeFolder(f.id);
    Podcasts.i.removeFolder(f.id);
    RadioDirectory.i.removeFolder(f.id);
    _persist('folders');
    _persist('books');
    _persist('saved');
    notifyListeners();
  }

  void toggleFolder(Book b, Folder f) {
    b.folderIds = b.folderIds.contains(f.id) ? ([...b.folderIds]..remove(f.id)) : [...b.folderIds, f.id];
    touch(b);
  }

  void reorderFolders(int from, int to) {
    final f = folders.removeAt(from);
    folders.insert(to > from ? to - 1 : to, f);
    _persist('folders');
    notifyListeners();
  }

  // ---------------- annotations ----------------

  List<Highlight> highlightsFor(String bookId) => highlights.where((h) => h.bookId == bookId).toList()..sort((a, b) => a.block != b.block ? a.block.compareTo(b.block) : a.start.compareTo(b.start));

  List<Bookmark> bookmarksFor(String bookId) => bookmarks.where((h) => h.bookId == bookId).toList()..sort((a, b) => a.block.compareTo(b.block));

  Highlight addHighlight(Highlight h) {
    // Replace overlapping highlights in the same block.
    highlights.removeWhere((o) => o.bookId == h.bookId && o.block == h.block && o.start < h.end && h.start < o.end);
    highlights.add(h);
    _persist('highlights');
    notifyListeners();
    return h;
  }

  void updateHighlight(Highlight h) {
    _persist('highlights');
    notifyListeners();
  }

  void removeHighlight(Highlight h) {
    highlights.remove(h);
    _persist('highlights');
    notifyListeners();
  }

  Bookmark? bookmarkAt(String bookId, int block) => bookmarks.where((b) => b.bookId == bookId && b.block == block).firstOrNull;

  void toggleBookmark(String bookId, int block, String label, double progress) {
    final existing = bookmarkAt(bookId, block);
    if (existing != null) {
      bookmarks.remove(existing);
    } else {
      bookmarks.add(Bookmark(id: newId(), bookId: bookId, block: block, label: label, progress: progress));
    }
    _persist('bookmarks');
    notifyListeners();
  }

  /// Bookmarks a passage (never toggles off an existing one).
  Bookmark addBookmark(String bookId, int block, String label, double progress, {String excerpt = ''}) {
    final existing = bookmarks.where((b) => b.bookId == bookId && b.block == block && b.excerpt == excerpt).firstOrNull;
    if (existing != null) return existing;
    final b = Bookmark(id: newId(), bookId: bookId, block: block, label: label, progress: progress, excerpt: excerpt);
    bookmarks.add(b);
    _persist('bookmarks');
    notifyListeners();
    return b;
  }

  void renameBookmark(Bookmark b, String label) {
    b.label = label;
    _persist('bookmarks');
    notifyListeners();
  }

  void removeBookmark(Bookmark b) {
    bookmarks.remove(b);
    _persist('bookmarks');
    notifyListeners();
  }

  // ---------------- sessions ----------------

  void addSession(ReadingSession s) {
    if (s.seconds < 10) return;
    sessions.add(s);
    _persist('sessions');
    notifyListeners();
  }

  /// Adds listening time, extending the last session if it only just paused
  /// so one sitting doesn't count as many.
  void addListening(String id, String mode, String label, int seconds) {
    if (seconds <= 0) return;
    final now = DateTime.now();
    final last = sessions.where((s) => s.bookId == id).lastOrNull;
    if (last != null && now.difference(last.start.add(Duration(seconds: last.seconds))).inMinutes < 15 && last.start.day == now.day) {
      last.seconds += seconds;
    } else {
      sessions.add(ReadingSession(bookId: id, start: now.subtract(Duration(seconds: seconds)), seconds: seconds, mode: mode, label: label));
    }
    _persist('sessions');
    notifyListeners();
  }

  int secondsFor(String bookId) => sessions.where((s) => s.bookId == bookId).fold(0, (a, s) => a + s.seconds);

  // ---------------- wishlist ----------------

  /// Books you chose to read later.
  List<SavedBook> get wantToRead => saved.where((s) => s.wanted).toList();

  bool isSaved(String key) => saved.any((s) => s.key == key && s.wanted);

  void toggleSaved(SavedBook s) {
    final mine = saved.where((e) => e.key == s.key).firstOrNull;
    if (mine == null) {
      saved.insert(0, s..wanted = true);
    } else {
      mine.wanted = !mine.wanted;
      // Keep the record while it still holds your rating, notes or folders.
      if (!mine.wanted && mine.mark.isEmpty && mine.folderIds.isEmpty) saved.remove(mine);
    }
    _persist('saved');
    notifyListeners();
  }

  /// The record for [s]'s key, or [s] itself if there isn't one yet.
  SavedBook savedOr(SavedBook s) => saved.where((e) => e.key == s.key).firstOrNull ?? s;

  /// Rating, hearting or filing a book keeps that, without putting it on the
  /// want-to-read list. Save is its own choice.
  void savedChanged(SavedBook s) {
    final listed = saved.any((e) => e.key == s.key);
    if (!listed) {
      saved.insert(0, s..wanted = false);
    } else if (!s.wanted && s.mark.isEmpty && s.folderIds.isEmpty) {
      saved.removeWhere((e) => e.key == s.key);
    }
    _persist('saved');
    notifyListeners();
  }

  void toggleSavedFolder(SavedBook s, String folderId) {
    s.folderIds = s.folderIds.contains(folderId) ? ([...s.folderIds]..remove(folderId)) : [...s.folderIds, folderId];
    savedChanged(s);
  }

  // ---------------- backup ----------------

  Map<String, dynamic> exportJson() => {
        'books': books.map((b) => b.toJson()).toList(),
        'folders': folders.map((b) => b.toJson()).toList(),
        'highlights': highlights.map((b) => b.toJson()).toList(),
        'bookmarks': bookmarks.map((b) => b.toJson()).toList(),
        'sessions': sessions.map((b) => b.toJson()).toList(),
        'saved': saved.map((b) => b.toJson()).toList(),
      };

  /// Merges a backup's library. Highlights, bookmarks and stats are kept even for
  /// books whose file is missing: ids come from file contents, so they reattach
  /// when the same file is added again.
  void mergeBackup(Map<String, dynamic> j, ImportResult r) {
    List<T> read<T>(dynamic v, T Function(Map<String, dynamic>) f) => v is List ? v.whereType<Map>().map((e) => f(Map<String, dynamic>.from(e))).toList() : <T>[];

    for (final b in read(j['books'], Book.fromJson)) {
      final at = books.indexWhere((x) => x.id == b.id);
      if (at >= 0) {
        final mine = books[at];
        if ((b.lastOpenedAt ?? b.addedAt).isAfter(mine.lastOpenedAt ?? mine.addedAt)) {
          // Their reading state and details, our file locations.
          b.path = mine.path;
          b.coverPath = mine.coverPath ?? (b.coverPath != null && File(b.coverPath!).existsSync() ? b.coverPath : null);
          books[at] = b;
        }
        continue;
      }
      if (!File(b.path).existsSync()) {
        r.missingBooks++;
        continue;
      }
      if (b.coverPath != null && !File(b.coverPath!).existsSync()) b.coverPath = null;
      books.add(b);
      r.books++;
    }
    for (final f in read(j['folders'], Folder.fromJson)) {
      if (!folders.any((x) => x.id == f.id)) folders.add(f);
    }
    for (final h in read(j['highlights'], Highlight.fromJson)) {
      if (highlights.any((x) => x.id == h.id)) continue;
      highlights.add(h);
      r.notes++;
    }
    for (final m in read(j['bookmarks'], Bookmark.fromJson)) {
      if (bookmarks.any((x) => x.id == m.id)) continue;
      bookmarks.add(m);
      r.notes++;
    }
    final seen = {for (final s in sessions) '${s.bookId}|${s.start.toIso8601String()}'};
    for (final s in read(j['sessions'], ReadingSession.fromJson)) {
      if (seen.add('${s.bookId}|${s.start.toIso8601String()}')) sessions.add(s);
    }
    sessions.sort((a, b) => a.start.compareTo(b.start));
    for (final s in read(j['saved'], SavedBook.fromJson)) {
      if (!saved.any((e) => e.key == s.key)) saved.add(s);
    }
    for (final n in const ['books', 'folders', 'highlights', 'bookmarks', 'sessions', 'saved']) {
      _persist(n);
    }
    notifyListeners();
  }

  /// Markdown export of a book's highlights and notes.
  String highlightsMarkdown(Book b) {
    final buf = StringBuffer('# ${b.title}\n');
    if (b.author.isNotEmpty) buf.writeln('*${b.author}*\n');
    for (final h in highlightsFor(b.id)) {
      buf.writeln('> ${h.text.replaceAll('\n', '\n> ')}');
      if (h.note.isNotEmpty) buf.writeln('\n${h.note}');
      buf.writeln();
    }
    return buf.toString();
  }
}

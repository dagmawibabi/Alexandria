import 'dart:io';
import 'dart:ui' as ui;

import 'package:material_ui/material_ui.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher_string.dart';

import '../core/net_image.dart';
import '../core/theme.dart';
import '../core/ui.dart';
import '../models/book.dart';
import '../services/ai.dart';
import '../services/library.dart';
import '../services/metadata.dart';
import 'ai_sheets.dart';
import 'library_screen.dart';
import 'marks.dart';

/// Keys of books being downloaded, shared by Discover and the info page.
final downloadingBooks = ValueNotifier<Set<String>>(const {});

/// Downloads a free EPUB into the library.
Future<Book?> downloadFreeBook(BuildContext context, BookInfo b) async {
  if (b.downloadUrl == null || downloadingBooks.value.contains(b.key)) return null;
  downloadingBooks.value = {...downloadingBooks.value, b.key};
  try {
    final bytes = await Metadata.download(b.downloadUrl!);
    if (bytes == null) throw 'Download failed';
    final dir = await getTemporaryDirectory();
    final f = File(p.join(dir.path, '${b.key.replaceAll(':', '_')}.epub'));
    await f.writeAsBytes(bytes);
    final book = await Library.i.importFile(f.path, displayName: '${b.title}.epub');
    // What you already said about it comes along.
    final mark = Library.i.savedOr(savedFrom(b));
    if (book.rating == 0) book.rating = mark.mark.rating;
    if (mark.mark.favorite) book.favorite = true;
    if (mark.folderIds.isNotEmpty) book.folderIds = {...book.folderIds, ...mark.folderIds}.toList();
    if (b.coverUrl != null && book.coverPath == null) {
      await Library.i.enrich(book, onlyMissing: true, choice: BookInfo(title: book.title, author: b.author, coverUrl: b.coverUrl, subjects: b.subjects, description: b.description));
    }
    if (context.mounted) toast(context, 'Added to library');
    return book;
  } catch (e) {
    if (context.mounted) toast(context, '$e');
    return null;
  } finally {
    downloadingBooks.value = {...downloadingBooks.value}..remove(b.key);
  }
}

/// Rate, favourite, take notes and file a catalogue book in folders. None of it saves the book.
Future<void> showBookMarks(BuildContext context, BookInfo b) {
  return showSheet(context, builder: (ctx) {
    return ListenableBuilder(
      listenable: Library.i,
      builder: (ctx, _) {
        final s = Library.i.savedOr(savedFrom(b));
        return Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(b.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
            const SizedBox(height: 14),
            MarksBar(mark: s.mark, title: b.title, changed: () => Library.i.savedChanged(s), folders: () => s.folderIds, onFolder: (id) => Library.i.toggleSavedFolder(s, id)),
          ]),
        );
      },
    );
  });
}

void openBookInfo(BuildContext context, BookInfo b) => Navigator.of(context).push(MaterialPageRoute(builder: (_) => BookInfoScreen(info: b)));

SavedBook savedFrom(BookInfo b) => SavedBook(key: b.key, title: b.title, author: b.author, coverUrl: b.coverUrl, year: b.year, downloadUrl: b.downloadUrl, source: b.source);

BookInfo infoFrom(SavedBook s) => BookInfo(title: s.title, author: s.author, coverUrl: s.coverUrl, year: s.year, key: s.key, downloadUrl: s.downloadUrl, source: s.source);

/// A catalogue cover from the network (cached on disk), or a generated one.
class NetCover extends StatelessWidget {
  const NetCover({super.key, required this.url, required this.title, this.shadow = false});
  final String? url;
  final String title;
  final bool shadow;

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    final fallback = GeneratedCover(Book(id: title, title: title, format: BookFormat.epub, path: ''));
    return AspectRatio(
      aspectRatio: 2 / 3,
      child: Container(
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          borderRadius: t.br,
          border: t.hair,
          boxShadow: shadow ? [BoxShadow(color: Colors.black.withValues(alpha: t.dark ? .55 : .2), blurRadius: 24, offset: const Offset(0, 10))] : null,
        ),
        child: url == null ? fallback : NetImage(url!, fallback: fallback),
      ),
    );
  }
}

/// Full-screen details for a catalogue or Gutenberg result.
class BookInfoScreen extends StatefulWidget {
  const BookInfoScreen({super.key, required this.info});
  final BookInfo info;

  @override
  State<BookInfoScreen> createState() => _BookInfoScreenState();
}

class _BookInfoScreenState extends State<BookInfoScreen> {
  BookInfo get _b => widget.info;
  late final Future<BookInfo?> _more = _fetchMore();

  /// Fills in what the search result left out: description, publisher, pages.
  Future<BookInfo?> _fetchMore() async {
    if (_b.source == 'Open Library' && _b.description.isEmpty) {
      final d = await Metadata.openLibraryDescription(_b.key);
      if (d.isNotEmpty) return BookInfo(title: _b.title, description: d);
    }
    return Metadata.best(_b.title, _b.author.split(',').first.trim(), isbn: _b.isbn);
  }

  String? get _webUrl {
    final k = _b.key;
    if (k.startsWith('gutenberg:')) return 'https://www.gutenberg.org/ebooks/${k.substring(10)}';
    if (k.startsWith('/')) return 'https://openlibrary.org$k';
    if (_b.source == 'Google Books' && k.isNotEmpty) return 'https://books.google.com/books?id=$k';
    return null;
  }

  Book? get _owned => Library.i.books.where((x) => x.title.toLowerCase() == _b.title.toLowerCase()).firstOrNull;

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    final top = MediaQuery.of(context).padding.top;
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: AppTitle(_b.source.isEmpty ? 'Book' : _b.source),
        actions: [
          if (_webUrl != null) IconButton(tooltip: 'Open on the web', onPressed: () => launchUrlString(_webUrl!, mode: LaunchMode.externalApplication), icon: const Icon(Icons.open_in_new_sharp)),
        ],
      ),
      body: ListenableBuilder(
        listenable: Listenable.merge([Library.i, downloadingBooks]),
        builder: (context, _) => FutureBuilder<BookInfo?>(
          future: _more,
          builder: (context, snap) {
            final more = snap.data;
            final loading = snap.connectionState != ConnectionState.done;
            String pick(String a, String? b) => a.isNotEmpty ? a : (b ?? '');
            final desc = pick(_b.description, more?.description);
            final publisher = pick(_b.publisher, more?.publisher);
            final year = pick(_b.year, more?.year);
            final isbn = pick(_b.isbn, more?.isbn);
            final pages = _b.pageCount > 0 ? _b.pageCount : (more?.pageCount ?? 0);
            final subjects = _b.subjects.isNotEmpty ? _b.subjects : (more?.subjects ?? const <String>[]);

            return ListView(padding: EdgeInsets.zero, children: [
              // Header: blurred cover behind the cover itself.
              SizedBox(
                height: top + 330,
                child: Stack(fit: StackFit.expand, children: [
                  if (_b.coverUrl != null)
                    Opacity(
                      opacity: t.dark ? .45 : .35,
                      child: ImageFiltered(imageFilter: ui.ImageFilter.blur(sigmaX: 28, sigmaY: 28), child: NetImage(_b.coverUrl!)),
                    ),
                  DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [t.bg.withValues(alpha: .2), t.bg]),
                    ),
                  ),
                  Padding(
                    padding: EdgeInsets.only(top: top + 64, bottom: 10),
                    child: Center(child: Hero(tag: 'net-${_b.key}', child: NetCover(url: _b.coverUrl, title: _b.title, shadow: true))),
                  ),
                ]),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 6, 20, 40),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(_b.title, style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w700, height: 1.1, letterSpacing: -.6)),
                  if (_b.author.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 6), child: Text(_b.author, style: TextStyle(color: t.muted, fontSize: 16))),
                  const SizedBox(height: 14),
                  Wrap(spacing: 6, runSpacing: 6, children: [
                    if (_b.downloadUrl != null) Tag('Free EPUB', color: t.accent),
                    if (year.isNotEmpty) Tag(year),
                    if (pages > 0) Tag('$pages pages'),
                    // ~280 words a page at ~230 words a minute
                    if (pages > 0) Tag('~${fmtDuration(pages * 280 * 60 ~/ 230)} read'),
                  ]),
                  const SizedBox(height: 20),
                  _actions(context),
                  const SizedBox(height: 14),
                  Builder(builder: (context) {
                    // One record throughout, so a first rating isn't written to a throwaway copy.
                    final rec = Library.i.savedOr(savedFrom(_b));
                    return MarksBar(mark: rec.mark, title: _b.title, changed: () => Library.i.savedChanged(rec), folders: () => rec.folderIds, onFolder: (id) => Library.i.toggleSavedFolder(rec, id));
                  }),
                  SectionHeader('01', t.zen ? 'About' : 'Abstract', padding: const EdgeInsets.fromLTRB(0, 28, 0, 12)),
                  if (desc.isNotEmpty)
                    CollapsibleText(desc, style: TextStyle(height: 1.55, color: t.ink.withValues(alpha: .85)))
                  else if (loading)
                    Row(children: [
                      const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 1.5)),
                      const SizedBox(width: 10),
                      Label('Looking up a description…'),
                    ])
                  else
                    Text('No description in the catalogues for this one.', style: TextStyle(color: t.muted)),
                  SectionHeader('02', t.zen ? 'Details' : 'Record', padding: const EdgeInsets.fromLTRB(0, 28, 0, 12)),
                  Panel(
                    padding: EdgeInsets.zero,
                    child: Column(children: [
                      _kv(context, 'Author', _b.author),
                      _kv(context, 'Publisher', publisher),
                      _kv(context, 'Year', year),
                      _kv(context, 'Pages', pages > 0 ? '$pages' : ''),
                      _kv(context, 'ISBN', isbn),
                      _kv(context, 'Source', _b.source),
                    ]),
                  ),
                  if (subjects.isNotEmpty) ...[
                    const SectionHeader('03', 'Subjects', padding: EdgeInsets.fromLTRB(0, 28, 0, 12)),
                    Wrap(spacing: 6, runSpacing: 6, children: [for (final s in subjects.take(12)) Tag(s.length > 40 ? '${s.substring(0, 40)}…' : s)]),
                  ],
                ]),
              ),
            ]);
          },
        ),
      ),
    );
  }

  Widget _actions(BuildContext context) {
    final owned = _owned;
    final saved = Library.i.isSaved(_b.key);
    final busy = downloadingBooks.value.contains(_b.key);
    final Widget main;
    if (owned != null) {
      main = PrimaryButton('Read now', icon: Icons.menu_book_sharp, expand: true, onTap: () => openBook(context, owned));
    } else if (_b.downloadUrl != null) {
      main = PrimaryButton(busy ? 'Downloading…' : 'Get EPUB · free', icon: busy ? Icons.hourglass_top_sharp : Icons.download_sharp, expand: true, onTap: busy ? null : () => downloadFreeBook(context, _b));
    } else {
      main = PrimaryButton('Find a copy', icon: Icons.open_in_new_sharp, expand: true, onTap: _webUrl == null ? null : () => launchUrlString(_webUrl!, mode: LaunchMode.externalApplication));
    }
    return Row(children: [
      Expanded(child: main),
      const SizedBox(width: 10),
      ToolButton(saved ? Icons.bookmark_added_sharp : Icons.bookmark_add_outlined, size: 48, active: saved, tooltip: saved ? 'On your list' : 'Want to read', onTap: () => Library.i.toggleSaved(savedFrom(_b))),
      const SizedBox(width: 10),
      ToolButton(Icons.auto_awesome_outlined, size: 48, tooltip: 'Ask AI about this book', onTap: () async {
        if (!await ensureAi(context) || !context.mounted) return;
        final tmp = Book(id: 'info:${_b.key}', title: _b.title, author: _b.author, description: _b.description, format: BookFormat.epub, path: '');
        showAiStream(context, title: 'About this book', subtitle: _b.title, book: tmp, make: () => Ai.aboutBook(tmp));
      }),
    ]);
  }

  Widget _kv(BuildContext context, String k, String v) {
    final t = Tokens.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(border: Border(bottom: BorderSide(color: t.line))),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SizedBox(width: 92, child: Label(k)),
        Expanded(child: Text(v.isEmpty ? '—' : v, style: TextStyle(color: v.isEmpty ? t.muted : t.ink, fontSize: 13.5))),
      ]),
    );
  }
}

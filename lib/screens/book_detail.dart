import 'package:file_picker/file_picker.dart';
import 'package:material_ui/material_ui.dart';
import 'package:share_plus/share_plus.dart';

import '../core/theme.dart';
import '../core/ui.dart';
import '../models/book.dart';
import '../services/ai.dart';
import '../services/library.dart';
import 'ai_sheets.dart';
import 'library_screen.dart';
import 'marks.dart';
import 'media_card.dart';
import 'meta_search.dart';
import 'quote_card.dart';
import '../core/image_viewer.dart';

class BookDetail extends StatelessWidget {
  const BookDetail({super.key, required this.book});
  final Book book;

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    return Scaffold(
      appBar: AppBar(
        title: AppTitle(t.zen ? book.title : 'Spec sheet · ${book.formatLabel}'),
        actions: [
          IconButton(tooltip: 'Share card', onPressed: () => showMediaCard(context, ShareItem.book(book)), icon: const Icon(Icons.ios_share_sharp)),
          IconButton(onPressed: () => showBookActions(context, book), icon: const Icon(Icons.more_horiz_sharp)),
        ],
      ),
      body: ListenableBuilder(
        listenable: Library.i,
        builder: (context, _) {
          final lib = Library.i;
          final sessions = lib.sessions.where((s) => s.bookId == book.id).toList();
          final secs = sessions.fold(0, (a, s) => a + s.seconds);
          final words = sessions.fold(0, (a, s) => a + s.words);
          final wpm = secs > 60 ? (words / (secs / 60)).round() : 0;
          final left = (book.wordCount * (1 - book.progress) / (wpm > 50 ? wpm : 230) * 60).round();
          final hls = lib.highlightsFor(book.id);

          final wide = isWide(context);
          final cover = ViewableImage(path: book.coverPath, title: book.title, child: Hero(tag: 'cover-${book.id}', child: Cover(book)));
          final info = <Widget>[
            Text(book.title, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700, height: 1.12, letterSpacing: -.4)),
            const SizedBox(height: 6),
            if (book.author.isNotEmpty) Text(book.author, style: TextStyle(color: t.muted, fontSize: 15)),
            const SizedBox(height: 14),
            Wrap(spacing: 6, runSpacing: 6, children: [
              Tag(book.formatLabel, color: t.accent),
              Tag(book.status.name),
              if (book.year.isNotEmpty) Tag(book.year),
              Tag('${(book.fileSize / 1048576).toStringAsFixed(1)} MB'),
            ]),
            const SizedBox(height: 14),
            _stars(context),
            const SizedBox(height: 10),
            Row(children: [
              ToolButton(book.favorite ? Icons.favorite_sharp : Icons.favorite_border_sharp, size: 40, active: book.favorite, tooltip: 'Favourite', onTap: () {
                book.favorite = !book.favorite;
                Library.i.touch(book);
              }),
              const SizedBox(width: 8),
              ToolButton(book.folderIds.isEmpty ? Icons.folder_outlined : Icons.folder_sharp, size: 40, active: book.folderIds.isNotEmpty, tooltip: 'Folders', onTap: () {
                showFolderPicker(context, title: book.title, selected: () => book.folderIds, onToggle: (id) => Library.i.toggleFolder(book, Library.i.folders.firstWhere((f) => f.id == id)));
              }),
            ]),
          ];

          return SplitDetail(padding: const EdgeInsets.fromLTRB(20, 8, 20, 40), side: [
            if (wide) ...[Center(child: SizedBox(width: 240, child: cover)), const SizedBox(height: 24), ...info]
            else
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                SizedBox(width: 130, child: cover),
                const SizedBox(width: 18),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: info)),
              ]),
            const SizedBox(height: 20),
            Row(children: [
              Expanded(child: PrimaryButton(book.progress > 0 ? 'Continue · ${(book.progress * 100).round()}%' : 'Start reading', icon: Icons.menu_book_sharp, onTap: () => openBook(context, book))),
              const SizedBox(width: 10),
              ToolButton(Icons.auto_awesome_outlined, size: 48, tooltip: 'Ask AI about this book', onTap: () => _askAbout(context)),
              const SizedBox(width: 10),
              ToolButton(Icons.forum_outlined, size: 48, tooltip: 'Chat about this book', onTap: () => openAiChat(context, book)),
            ]),
          ], main: [
            SectionHeader('01', t.zen ? 'Your reading' : 'Telemetry', padding: const EdgeInsets.fromLTRB(0, 28, 0, 12)),
            GridView.count(
              crossAxisCount: 3,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 8,
              crossAxisSpacing: 8,
              childAspectRatio: wide ? 3.4 : 1.35,
              children: [
                _Stat('Time', fmtDuration(secs)),
                _Stat('Sessions', '${sessions.length}'),
                _Stat('Speed', wpm > 0 ? '$wpm wpm' : '—'),
                _Stat('Left', book.wordCount > 0 ? '~${fmtDuration(left)}' : '—'),
                _Stat('Words', book.wordCount > 999 ? '${(book.wordCount / 1000).toStringAsFixed(0)}k' : '${book.wordCount}'),
                _Stat('Pages', '${book.pageCount}'),
                _Stat('Highlights', '${hls.length}'),
                _Stat('Bookmarks', '${lib.bookmarksFor(book.id).length}'),
                _Stat('Added', '${pad(book.addedAt.day)}.${pad(book.addedAt.month)}.${book.addedAt.year % 100}'),
              ],
            ),

            SectionHeader('02', t.zen ? 'About' : 'Abstract', padding: const EdgeInsets.fromLTRB(0, 28, 0, 12)),
            if (book.description.isNotEmpty)
              CollapsibleText(book.description, style: TextStyle(height: 1.55, color: t.ink.withValues(alpha: .85)))
            else
              Panel(
                padding: const EdgeInsets.all(16),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text('No details for this book yet', style: TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 4),
                  Text('Search the catalogues for its cover, author and description, or type them in yourself.', style: TextStyle(color: t.muted, height: 1.4)),
                  const SizedBox(height: 12),
                  Row(children: [
                    Expanded(child: PrimaryButton('Find info', icon: Icons.search_sharp, onTap: () => _fetch(context))),
                    const SizedBox(width: 8),
                    Expanded(child: PrimaryButton('Add manually', ghost: true, icon: Icons.edit_outlined, onTap: () => _edit(context))),
                  ]),
                ]),
              ),

            SectionHeader('03', t.zen ? 'Details' : 'Record', padding: const EdgeInsets.fromLTRB(0, 28, 0, 12)),
            Panel(
              padding: EdgeInsets.zero,
              child: Column(children: [
                _kv(context, 'Publisher', book.publisher),
                _kv(context, 'Year', book.year),
                _kv(context, 'ISBN', book.isbn),
                _kv(context, 'Language', book.language),
                _kv(context, 'Subjects', book.subjects.take(5).join(' · ')),
                _kv(context, 'Tags', book.tags.join(' · ')),
              ]),
            ),
            const SizedBox(height: 10),
            Wrap(spacing: 8, runSpacing: 8, children: [
              ToolButton(Icons.cloud_download_outlined, label: 'Find info', onTap: () => _fetch(context)),
              ToolButton(Icons.image_outlined, label: 'Cover', onTap: () => _cover(context)),
              ToolButton(Icons.edit_outlined, label: 'Edit', onTap: () => _edit(context)),
              ToolButton(Icons.sell_outlined, label: 'Tag', onTap: () async {
                final v = await promptText(context, title: 'Add tag');
                if (v != null && v.trim().isNotEmpty) {
                  book.tags = [...book.tags, v.trim()];
                  Library.i.touch(book);
                }
              }),
            ]),

            SectionHeader('04', 'Highlights · ${hls.length}',
                padding: const EdgeInsets.fromLTRB(0, 28, 0, 12),
                trailing: hls.isEmpty
                    ? null
                    : Tap(
                        onTap: () => SharePlus.instance.share(ShareParams(text: lib.highlightsMarkdown(book), subject: book.title)),
                        child: Label('Export ↗', color: t.accent),
                      )),
            if (hls.isEmpty) Label('Select text while reading to highlight.'),
            for (final h in hls.take(30))
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Panel(
                  onTap: () => shareHighlight(context, book, h),
                  padding: const EdgeInsets.all(14),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Container(width: 3, height: 40, color: highlightColor(h.color)),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(h.text, maxLines: 5, overflow: TextOverflow.ellipsis, style: const TextStyle(height: 1.45)),
                        if (h.note.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 6), child: Text('— ${h.note}', style: TextStyle(color: t.muted, fontStyle: FontStyle.italic))),
                      ]),
                    ),
                    Icon(Icons.ios_share_sharp, size: 16, color: t.muted),
                  ]),
                ),
              ),
            SectionHeader('05', 'Bookmarks · ${lib.bookmarksFor(book.id).length}', padding: const EdgeInsets.fromLTRB(0, 28, 0, 12)),
            if (lib.bookmarksFor(book.id).isEmpty) Label('Tap the bookmark icon, or select text → bookmark.'),
            for (final m in lib.bookmarksFor(book.id))
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Panel(
                  onTap: () => shareBookmark(context, book, m),
                  padding: const EdgeInsets.all(14),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Icon(Icons.bookmark_sharp, size: 18, color: t.accent),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(m.label, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600)),
                        if (m.excerpt.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 4), child: Text('“${m.excerpt}”', maxLines: 3, overflow: TextOverflow.ellipsis, style: TextStyle(color: t.muted, fontStyle: FontStyle.italic))),
                        const SizedBox(height: 4),
                        Label('${(m.progress * 100).toStringAsFixed(1)}%', size: 9),
                      ]),
                    ),
                    Icon(Icons.ios_share_sharp, size: 16, color: t.muted),
                  ]),
                ),
              ),
          ]);
        },
      ),
    );
  }

  Widget _stars(BuildContext context) {
    return Row(children: [
      RatingBar(
        value: book.rating,
        size: 20,
        onChanged: (v) {
          book.rating = v;
          Library.i.touch(book);
        },
      ),
      const SizedBox(width: 6),
      Label(book.rating == 0 ? 'Unrated' : '${book.rating}/5'),
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

  Future<void> _askAbout(BuildContext context) async {
    if (!await ensureAi(context)) return;
    final doc = await Library.i.doc(book);
    if (!context.mounted) return;
    showAiStream(context, title: 'About this book', subtitle: book.title, make: () => Ai.aboutBook(book, doc: doc), book: book);
  }

  Future<void> _fetch(BuildContext context) async {
    // Filenames make poor queries: drop extensions, underscores and bracketed junk first.
    final guess = book.title.replaceAll(RegExp(r'\.(pdf|epub|docx)$', caseSensitive: false), '').replaceAll(RegExp(r'[_]+'), ' ').replaceAll(RegExp(r'[\[(].*?[\])]'), '').trim();
    final pick = await showMetadataSearch(context, query: guess, author: book.author, isbn: book.isbn);
    if (pick == null) return;
    await Library.i.enrich(book, choice: pick);
    if (context.mounted) toast(context, 'Info updated');
  }

  Future<void> _cover(BuildContext context) async {
    final files = await FilePicker.pickFiles(type: FileType.image);
    final path = files.firstOrNull?.path;
    if (path != null) await Library.i.setCover(book, path);
  }

  Future<void> _edit(BuildContext context) async {
    final title = TextEditingController(text: book.title);
    final author = TextEditingController(text: book.author);
    final year = TextEditingController(text: book.year);
    final desc = TextEditingController(text: book.description);
    final publisher = TextEditingController(text: book.publisher);
    final isbn = TextEditingController(text: book.isbn);
    final language = TextEditingController(text: book.language);
    final subjects = TextEditingController(text: book.subjects.join(', '));
    await showSheet(context, builder: (ctx) {
      Widget field(TextEditingController c, String label, {int lines = 1, TextInputType? type}) =>
          Padding(padding: const EdgeInsets.only(bottom: 8), child: TextField(controller: c, maxLines: lines, keyboardType: type, decoration: InputDecoration(labelText: label)));
      return Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            const Expanded(child: Label('Edit record')),
            Tap(
              onTap: () {
                Navigator.pop(ctx);
                _fetch(context);
              },
              child: Label('Search catalogues ↗', color: Tokens.of(ctx).accent),
            ),
          ]),
          const SizedBox(height: 12),
          field(title, 'Title'),
          field(author, 'Author'),
          Row(children: [
            Expanded(child: field(year, 'Year', type: TextInputType.number)),
            const SizedBox(width: 8),
            Expanded(child: field(language, 'Language')),
          ]),
          field(publisher, 'Publisher'),
          field(isbn, 'ISBN', type: TextInputType.number),
          field(subjects, 'Subjects (comma separated)'),
          field(desc, 'Description', lines: 6),
          const SizedBox(height: 4),
          Row(children: [
            ToolButton(Icons.image_outlined, label: 'Cover', onTap: () => _cover(context)),
            const SizedBox(width: 10),
            Expanded(
              child: PrimaryButton('Save', expand: true, onTap: () {
                book
                  ..title = title.text.trim().isEmpty ? book.title : title.text.trim()
                  ..author = author.text.trim()
                  ..year = year.text.trim()
                  ..publisher = publisher.text.trim()
                  ..isbn = isbn.text.replaceAll(RegExp(r'[^0-9Xx]'), '')
                  ..language = language.text.trim()
                  ..subjects = subjects.text.split(',').map((s) => s.trim()).where((s) => s.isNotEmpty).toList()
                  ..description = desc.text.trim()
                  ..metadataFetched = true;
                Library.i.touch(book);
                Navigator.pop(ctx);
              }),
            ),
          ]),
        ]),
      );
    });
  }
}

class _Stat extends StatelessWidget {
  const _Stat(this.k, this.v);
  final String k;
  final String v;

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(color: t.surface, border: t.hair, borderRadius: t.br),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Label(k, size: 9),
        FittedBox(fit: BoxFit.scaleDown, child: Text(v, style: mono(context, size: 17, color: t.ink, weight: FontWeight.w600, spacing: -.3))),
      ]),
    );
  }
}

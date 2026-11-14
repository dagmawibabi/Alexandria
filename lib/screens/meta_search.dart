import 'package:material_ui/material_ui.dart';

import '../core/net_image.dart';
import '../core/search_box.dart';
import '../core/theme.dart';
import '../core/ui.dart';
import '../services/metadata.dart';
import '../core/skeleton.dart';

/// Searches Google Books and Open Library with a query the user can edit,
/// and returns the chosen record (with its description filled in when possible).
Future<BookInfo?> showMetadataSearch(BuildContext context, {required String query, String author = '', String isbn = ''}) {
  return showSheet<BookInfo>(context, scroll: false, maxHeight: .92, builder: (ctx) => _MetaSearch(query: query, author: author, isbn: isbn));
}

class _MetaSearch extends StatefulWidget {
  const _MetaSearch({required this.query, required this.author, required this.isbn});
  final String query;
  final String author;
  final String isbn;

  @override
  State<_MetaSearch> createState() => _MetaSearchState();
}

class _MetaSearchState extends State<_MetaSearch> {
  late final _q = TextEditingController(text: [widget.query, widget.author].where((s) => s.trim().isNotEmpty).join(' '));
  List<BookInfo>? _results;
  bool _loading = false;
  String? _picking;

  @override
  void initState() {
    super.initState();
    _run(first: true);
  }

  @override
  void dispose() {
    _q.dispose();
    super.dispose();
  }

  Future<void> _run({bool first = false}) async {
    final q = _q.text.trim();
    if (q.isEmpty) return;
    setState(() => _loading = true);
    // The first search uses the title/author/ISBN match; later ones search the typed text as-is.
    final r = first ? await Metadata.candidates(widget.query, widget.author, isbn: widget.isbn) : await Metadata.search(q);
    if (!mounted) return;
    setState(() {
      _results = r;
      _loading = false;
    });
  }

  Future<void> _pick(BookInfo b) async {
    setState(() => _picking = b.key);
    if (b.description.isEmpty && b.source == 'Open Library') b.description = await Metadata.openLibraryDescription(b.key);
    if (mounted) Navigator.pop(context, b);
  }

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    final results = _results ?? const <BookInfo>[];
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Label('Find book info', color: t.accent),
        const SizedBox(height: 10),
        SearchBox(historyKey: 'book-info', 
          controller: _q,
          textInputAction: TextInputAction.search,
          onSubmitted: (_) => _run(),
          decoration: InputDecoration(
            hintText: 'Title, author or ISBN',
            prefixIcon: const Icon(Icons.search_sharp, size: 18),
            suffixIcon: IconButton(icon: const Icon(Icons.arrow_forward_sharp, size: 18), onPressed: _run),
          ),
        ),
        const SizedBox(height: 6),
        Label('Google Books + Open Library · tap a match to apply it', size: 9),
        const SizedBox(height: 10),
        Expanded(
          child: _loading
              ? ListView(physics: const NeverScrollableScrollPhysics(), children: const [SkeletonRows(count: 6, art: 44, artAspect: 2 / 3, lines: 3)])
              : results.isEmpty
                  ? Center(child: Text('No matches. Try fewer words, or just the title.', style: TextStyle(color: t.muted)))
                  : ListView.builder(
                      padding: const EdgeInsets.only(bottom: 24),
                      itemCount: results.length,
                      itemBuilder: (_, i) {
                        final b = results[i];
                        return Tap(
                          onTap: _picking == null ? () => _pick(b) : null,
                          child: Container(
                            margin: const EdgeInsets.only(bottom: 8),
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(border: t.hair, borderRadius: t.br, color: t.raised),
                            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              ClipRRect(
                                borderRadius: t.br,
                                child: SizedBox(
                                  width: 44,
                                  height: 66,
                                  child: b.coverUrl == null ? Container(color: t.line) : NetImage(b.coverUrl!, fallback: Container(color: t.line)),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                  Text(b.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600)),
                                  Text([b.author, b.year].where((s) => s.isNotEmpty).join(' · '), maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: t.muted, fontSize: 12.5)),
                                  if (b.description.isNotEmpty)
                                    Padding(padding: const EdgeInsets.only(top: 4), child: Text(b.description, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(color: t.muted, fontSize: 12))),
                                  const SizedBox(height: 4),
                                  Label(b.source, size: 9),
                                ]),
                              ),
                              if (_picking == b.key) const Padding(padding: EdgeInsets.all(4), child: SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 1.5))),
                            ]),
                          ),
                        );
                      },
                    ),
        ),
      ]),
    );
  }
}

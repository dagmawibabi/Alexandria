import 'package:material_ui/material_ui.dart';

import '../core/search_box.dart';
import '../core/theme.dart';
import '../core/ui.dart';
import 'book_info_screen.dart';
import 'folders_screen.dart';
import 'library_screen.dart' show importBooks, openBook;
import '../services/api_cache.dart';
import '../services/folders.dart';
import '../services/library.dart';
import '../services/metadata.dart';

class DiscoverScreen extends StatefulWidget {
  const DiscoverScreen({super.key});

  @override
  State<DiscoverScreen> createState() => _DiscoverScreenState();
}

class _DiscoverScreenState extends State<DiscoverScreen> {
  String _source = 'free';
  final _q = TextEditingController();
  List<BookInfo>? _results;
  bool _loading = false;

  /// What's being browsed when the search box is empty; a new one each launch.
  String _keyword = (Metadata.keywords.toList()..shuffle()).first;

  /// Want-to-read filter: 'all' or 'fav'.
  String _savedFilter = 'all';

  @override
  void initState() {
    super.initState();
    _run();
  }

  Future<void> _run() async {
    setState(() => _loading = true);
    final q = _q.text.trim();
    final List<BookInfo> r;
    if (q.isEmpty) {
      r = _source == 'free' ? await Metadata.popular(_keyword) : await Metadata.catalogPopular(_keyword);
    } else {
      r = _source == 'free' ? await Metadata.gutenberg(q) : await Metadata.openLibrary(q, limit: 30);
    }
    if (!mounted) return;
    setState(() {
      _results = r;
      _loading = false;
    });
  }


  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    return SafeArea(
      bottom: false,
      child: ListenableBuilder(
        listenable: Listenable.merge([Library.i, downloadingBooks]),
        builder: (context, _) {
          final downloading = downloadingBooks.value;
          final saved = Library.i.wantToRead;
          return RefreshIndicator(
            onRefresh: () => ApiCache.fresh(_run),
            child: CustomScrollView(physics: const AlwaysScrollableScrollPhysics(), slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Kicker('Find / catalogue'),
                  Row(children: [
                    Expanded(
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Text('Books', style: Theme.of(context).textTheme.displaySmall?.copyWith(fontWeight: FontWeight.w700, letterSpacing: -1.2, height: 1)),
                      ),
                    ),
                    const SizedBox(width: 12),
                    ToolButton(Icons.folder_outlined, tooltip: 'Folders', onTap: () => openFolders(context, FolderKind.books)),
                    const SizedBox(width: 8),
                    ToolButton(Icons.add_sharp, active: true, tooltip: 'Add books', onTap: () => importBooks(context)),
                  ]),
                  const SizedBox(height: 18),
                  SearchBox(historyKey: 'books', 
                    controller: _q,
                    textInputAction: TextInputAction.search,
                    onSubmitted: (_) => _run(),
                    onChanged: (v) {
                      // Clearing the box goes back to browsing.
                      if (v.isEmpty) _run();
                      setState(() {});
                    },
                    decoration: InputDecoration(
                      hintText: _source == 'free' ? 'Classics: Austen, Dostoevsky, Homer…' : 'Any book, author or ISBN',
                      prefixIcon: const Icon(Icons.search_sharp, size: 18),
                      suffixIcon: IconButton(icon: const Icon(Icons.arrow_forward_sharp, size: 18), onPressed: _run),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Segmented<String>(
                    values: const ['free', 'catalog'],
                    labels: const ['Free ebooks', 'World catalogue'],
                    value: _source,
                    onChanged: (v) {
                      setState(() {
                        _source = v;
                        _results = null;
                      });
                      _run();
                    },
                  ),
                  const SizedBox(height: 6),
                  Label(_source == 'free' ? 'Public domain · Project Gutenberg · downloads EPUB' : 'Open Library · save to your want-to-read list', size: 9),
                ]),
              ),
            ),
            if (saved.isNotEmpty && _q.text.isEmpty) ...[
              SliverToBoxAdapter(child: SectionHeader('', 'Want to read · ${saved.length}', padding: const EdgeInsets.fromLTRB(20, 24, 20, 8))),
              SliverToBoxAdapter(
                child: SizedBox(
                  height: 36,
                  child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 20), children: [
                    Padding(padding: const EdgeInsets.only(right: 6), child: Tag('All', filled: _savedFilter == 'all', onTap: () => setState(() => _savedFilter = 'all'))),
                    Padding(padding: const EdgeInsets.only(right: 6), child: Tag('★ Favourites', filled: _savedFilter == 'fav', onTap: () => setState(() => _savedFilter = 'fav'))),
                  ]),
                ),
              ),
              const SliverToBoxAdapter(child: SizedBox(height: 10)),
              SliverToBoxAdapter(
                child: Builder(builder: (context) {
                  final shown = saved.where((s) => _savedFilter == 'all' || s.mark.favorite).toList();
                  if (shown.isEmpty) return Padding(padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8), child: Text('Nothing here yet.', style: TextStyle(color: t.muted)));
                  return SizedBox(
                    height: 190,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      itemCount: shown.length,
                      separatorBuilder: (_, _) => const SizedBox(width: 12),
                      itemBuilder: (_, i) {
                        final s = shown[i];
                        return GestureDetector(
                          onTap: () => openBookInfo(context, infoFrom(s)),
                          onLongPress: () {
                            haptic(true);
                            showBookMarks(context, infoFrom(s));
                          },
                          child: SizedBox(
                            width: 92,
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Stack(children: [
                                NetCover(url: s.coverUrl, title: s.title),
                                if (s.mark.favorite) Positioned(left: 5, top: 5, child: Icon(Icons.favorite_sharp, size: 14, color: t.accent)),
                              ]),
                              const SizedBox(height: 6),
                              Text(s.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                            ]),
                          ),
                        );
                      },
                    ),
                  );
                }),
              ),
            ],
            SliverToBoxAdapter(
              child: SectionHeader(
                '',
                _q.text.isEmpty ? 'Popular · $_keyword' : 'Results · ${_results?.length ?? 0}',
                padding: const EdgeInsets.fromLTRB(20, 24, 20, 8),
                trailing: _q.text.isEmpty
                    ? Tag('Surprise me', color: t.accent, onTap: () {
                        setState(() => _keyword = (Metadata.keywords.where((k) => k != _keyword).toList()..shuffle()).first);
                        _run();
                      })
                    : null,
              ),
            ),
            if (_q.text.isEmpty)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: SizedBox(
                    height: 36,
                    child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 20), children: [
                      for (final k in Metadata.keywords)
                        Padding(
                          padding: const EdgeInsets.only(right: 6),
                          child: Tag(k, filled: k == _keyword, onTap: () {
                            setState(() => _keyword = k);
                            _run();
                          }),
                        ),
                    ]),
                  ),
                ),
              ),
            if (_loading)
              const SliverToBoxAdapter(child: Padding(padding: EdgeInsets.all(40), child: Center(child: CircularProgressIndicator(strokeWidth: 1.5))))
            else if ((_results ?? []).isEmpty)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.all(36),
                  child: Column(children: [
                    Text(_q.text.isEmpty ? 'Couldn’t load these. The book catalogue may be slow, or you may be offline.' : 'No results. The free catalogue can be slow, so it may also have timed out.',
                        textAlign: TextAlign.center, style: TextStyle(color: t.muted, height: 1.4)),
                    const SizedBox(height: 12),
                    ToolButton(Icons.refresh_sharp, label: 'Try again', size: 36, onTap: () => ApiCache.fresh(_run)),
                  ]),
                ),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
                sliver: SliverList.separated(
                  itemCount: _results!.length,
                  separatorBuilder: (_, _) => Divider(color: t.line),
                  itemBuilder: (_, i) {
                    final b = _results![i];
                    final isSaved = Library.i.isSaved(b.key);
                    final owned = Library.i.copyOf(b);
                    return GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () => openBookInfo(context, b),
                      onLongPress: () {
                        haptic(true);
                        showBookMarks(context, b);
                      },
                      child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        SizedBox(width: 56, child: Hero(tag: 'net-${b.key}', child: NetCover(url: b.coverUrl, title: b.title))),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text(b.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
                            if (b.author.isNotEmpty) Text(b.author, maxLines: 1, style: TextStyle(color: t.muted, fontSize: 13)),
                            const SizedBox(height: 6),
                            Label([b.year, if (b.subjects.isNotEmpty) b.subjects.first].where((s) => s.isNotEmpty).join(' · '), size: 9),
                            const SizedBox(height: 10),
                            // Wraps on narrow screens rather than overflowing.
                            Wrap(spacing: 8, runSpacing: 8, children: [
                              if (owned != null)
                                ToolButton(Icons.menu_book_sharp, label: 'Read', active: true, size: 34, onTap: () => openBook(context, owned))
                              else if (b.downloadUrl != null)
                                ToolButton(
                                  downloading.contains(b.key) ? Icons.hourglass_top_sharp : Icons.download_sharp,
                                  label: downloading.contains(b.key) ? 'Fetching' : 'Get EPUB',
                                  active: true,
                                  size: 34,
                                  onTap: downloading.contains(b.key) ? null : () => downloadFreeBook(context, b),
                                ),
                              ToolButton(isSaved ? Icons.bookmark_added_sharp : Icons.bookmark_add_outlined, label: isSaved ? 'Saved' : 'Save', size: 34, onTap: () => Library.i.toggleSaved(savedFrom(b))),
                              ToolButton(
                                Library.i.savedOr(savedFrom(b)).mark.favorite ? Icons.favorite_sharp : Icons.favorite_border_sharp,
                                size: 34,
                                active: Library.i.savedOr(savedFrom(b)).mark.favorite,
                                tooltip: 'Favourite',
                                onTap: () {
                                  final rec = Library.i.savedOr(savedFrom(b));
                                  rec.mark.favorite = !rec.mark.favorite;
                                  Library.i.savedChanged(rec);
                                },
                              ),
                            ]),
                          ]),
                        ),
                        Padding(padding: const EdgeInsets.only(left: 6, top: 2), child: Icon(Icons.chevron_right_sharp, color: t.muted)),
                      ]),
                      ),
                    );
                  },
                ),
              ),
          ]),
          );
        },
      ),
    );
  }
}

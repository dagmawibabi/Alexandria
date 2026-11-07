import 'package:file_picker/file_picker.dart';
import 'package:material_ui/material_ui.dart';

import '../core/settings.dart';
import '../core/theme.dart';
import '../core/ui.dart';
import '../models/audiobook.dart';
import '../models/book.dart';
import '../models/podcast.dart';
import '../models/radio.dart';
import '../services/audio.dart';
import '../services/folders.dart';
import '../services/library.dart';
import '../services/podcasts.dart';
import '../services/radio.dart';
import 'audiobook_screen.dart';
import 'book_detail.dart';
import 'book_info_screen.dart';
import 'folders_screen.dart';
import 'media_card.dart';
import 'player_screen.dart';
import 'podcasts_view.dart';
import 'radio_view.dart';
import 'reader/reader_screen.dart';
import 'recently_added.dart';
import 'shell.dart';
import 'stats_screen.dart';

void openBook(BuildContext context, Book b) => Navigator.of(context).push(MaterialPageRoute(builder: (_) => ReaderScreen(book: b)));

void openDetail(BuildContext context, Book b) => Navigator.of(context).push(MaterialPageRoute(builder: (_) => BookDetail(book: b)));

Future<void> importBooks(BuildContext context) async {
  final files = await FilePicker.pickFiles(type: FileType.custom, allowedExtensions: ['pdf', 'epub', 'docx']);
  var n = 0;
  for (final f in files) {
    if (f.path == null) continue;
    try {
      await Library.i.importFile(f.path!, displayName: f.name);
      n++;
    } catch (e) {
      if (context.mounted) toast(context, '$e');
    }
  }
  if (context.mounted && n > 0) toast(context, '$n added');
}

class LibraryScreen extends StatefulWidget {
  const LibraryScreen({super.key});

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  String _filter = 'all';

  List<Book> _visible() {
    final lib = Library.i;
    var list = lib.books.where((b) {
      switch (_filter) {
        case 'all':
        case 'books':
          break;
        case 'audio':
        case 'shows':
        case 'radio':
          return false;
        case 'reading':
          if (b.status != ReadStatus.reading) return false;
        case 'unread':
          if (b.status != ReadStatus.unread) return false;
        case 'finished':
          if (b.status != ReadStatus.finished) return false;
        case 'fav':
          if (!b.favorite) return false;
        case 'pdf':
        case 'epub':
        case 'docx':
          if (b.format.name != _filter) return false;
        default:
          if (!b.folderIds.contains(_filter)) return false;
      }
      return true;
    }).toList();

    int cmpDate(DateTime? a, DateTime? b) => (b ?? DateTime(1970)).compareTo(a ?? DateTime(1970));
    switch (Settings.i.librarySort) {
      case 'title':
        list.sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));
      case 'author':
        list.sort((a, b) => a.author.toLowerCase().compareTo(b.author.toLowerCase()));
      case 'added':
        list.sort((a, b) => b.addedAt.compareTo(a.addedAt));
      case 'progress':
        list.sort((a, b) => b.progress.compareTo(a.progress));
      default:
        list.sort((a, b) => cmpDate(a.lastOpenedAt ?? a.addedAt, b.lastOpenedAt ?? b.addedAt));
    }
    return lib.newFirst(list);
  }

  /// Audiobooks for the current search and filter.
  List<Audiobook> _matchingAudio() {
    return AudioLibrary.i.recent.where((b) {
      return switch (_filter) {
        'all' || 'audio' => true,
        'books' || 'shows' || 'radio' || 'pdf' || 'epub' || 'docx' => false,
        'reading' => !b.finished && b.progress > 0,
        'unread' => !b.finished && b.progress == 0,
        'finished' => b.finished,
        'fav' => b.mark.favorite,
        _ => b.folderIds.contains(_filter),
      };
    }).toList();
  }

  /// Stations for the current filter: your favourites at home, all you've kept under Radio.
  List<Station> _matchingStations() {
    final dir = RadioDirectory.i;
    return switch (_filter) {
      'all' || 'fav' => dir.favorites,
      'radio' => dir.kept,
      'books' || 'audio' || 'shows' || 'reading' || 'unread' || 'finished' || 'pdf' || 'epub' || 'docx' => const <Station>[],
      _ => dir.kept.where((s) => dir.foldersOf(s.id).contains(_filter)).toList(),
    };
  }

  /// Subscribed shows for the current search and filter.
  List<Podcast> _matchingShows() {
    final pods = Podcasts.i;
    return pods.subscriptions.where((x) {
      final stages = x.episodes.map(pods.stage);
      return switch (_filter) {
        'all' || 'shows' => true,
        'books' || 'audio' || 'radio' || 'pdf' || 'epub' || 'docx' => false,
        'reading' => stages.contains('started'),
        'unread' => stages.every((e) => e == 'unplayed'),
        'finished' => stages.isNotEmpty && stages.every((e) => e == 'played'),
        'fav' => pods.showMark(x.feedUrl).favorite,
        _ => pods.foldersOf(x.feedUrl).contains(_filter),
      };
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    return ListenableBuilder(
      listenable: Listenable.merge([Library.i, Settings.i, AudioLibrary.i, Podcasts.i, RadioDirectory.i]),
      builder: (context, _) {
        final lib = Library.i;
        // The folder being filtered by may have just been deleted.
        const builtIn = {'all', 'books', 'audio', 'shows', 'radio', 'reading', 'unread', 'finished', 'fav', 'pdf', 'epub', 'docx'};
        if (!builtIn.contains(_filter) && !lib.folders.any((f) => f.id == _filter)) _filter = 'all';
        final books = _visible();
        final s = Settings.i;
        final home = _filter == 'all';
        final audio = _matchingAudio();
        final shows = _matchingShows();
        final radio = _matchingStations();
        // Catalogue books you hearted or filed show up only under those filters.
            final wanted = _filter == 'all' || const ['books', 'audio', 'shows', 'radio', 'reading', 'unread', 'finished', 'pdf', 'epub', 'docx'].contains(_filter)
            ? const <SavedBook>[]
            : lib.saved.where((x) => (_filter == 'fav' ? x.mark.favorite : x.folderIds.contains(_filter))).toList();
        final nothing = lib.books.isEmpty && AudioLibrary.i.books.isEmpty && Podcasts.i.subscriptions.isEmpty;
        // On a filtered view, skip the Books heading when no books match.
        final showBooks = _filter != 'audio' && _filter != 'shows' && _filter != 'radio' && (home || books.isNotEmpty);

        return SafeArea(
          bottom: false,
          child: CustomScrollView(slivers: [
            SliverToBoxAdapter(child: _header(context, lib)),
            SliverToBoxAdapter(child: _filters(context, lib)),
            ValueListenableBuilder(
              valueListenable: lib.importing,
              builder: (context, m, _) => SliverToBoxAdapter(
                child: m.isEmpty
                    ? const SizedBox.shrink()
                    : Padding(
                        padding: const EdgeInsets.fromLTRB(20, 4, 20, 4),
                        child: Panel(
                          padding: const EdgeInsets.all(12),
                          child: Row(children: [
                            const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 1.5)),
                            const SizedBox(width: 12),
                            Label('Processing ${m.length} file${m.length > 1 ? 's' : ''}'),
                            const Spacer(),
                            Label('${(m.values.first * 100).round()}%', color: t.ink),
                          ]),
                        ),
                      ),
              ),
            ),
            if (home) const SliverToBoxAdapter(child: RecentlyAdded()),
            if (_filter == 'books') const SliverToBoxAdapter(child: RecentlyAdded(kinds: {AddedKind.book})),
            if (_filter == 'audio') const SliverToBoxAdapter(child: RecentlyAdded(kinds: {AddedKind.audio})),
            if (_filter == 'shows') const SliverToBoxAdapter(child: RecentlyAdded(kinds: {AddedKind.show})),
            if (home) const SliverToBoxAdapter(child: _ContinueRail()),
            if (showBooks) ...[
            SliverToBoxAdapter(
              child: SectionHeader(
                '',
                'Books · ${books.length}',
                trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                  _SortMenu(),
                  const SizedBox(width: 6),
                  ToolButton(s.libraryGrid ? Icons.view_agenda_outlined : Icons.grid_view_sharp, size: 32, onTap: () => s.libraryGrid = !s.libraryGrid),
                ]),
              ),
            ),
            if (nothing)
              SliverToBoxAdapter(child: _empty(context))
            else if (lib.books.isEmpty)
              SliverToBoxAdapter(child: Padding(padding: const EdgeInsets.all(24), child: Center(child: PrimaryButton('Add your first book', ghost: true, icon: Icons.add_sharp, onTap: () => importBooks(context))))),
            if (s.libraryGrid)
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
                sliver: SliverLayoutBuilder(builder: (context, c) {
                  // Tile height = cover (2:3) + room for two title lines and the status label,
                  // so nothing spills into the row below at any column count or text size.
                  final n = s.gridColumns;
                  final tileW = (c.crossAxisExtent - 14 * (n - 1)) / n;
                  final textH = MediaQuery.textScalerOf(context).scale(46) + 14;
                  return SliverGrid(
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: n, mainAxisSpacing: 18, crossAxisSpacing: 14, mainAxisExtent: tileW * 1.5 + textH),
                    delegate: SliverChildBuilderDelegate((c, i) => _GridTile(book: books[i]), childCount: books.length),
                  );
                }),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
                sliver: SliverList.separated(
                  itemCount: books.length,
                  separatorBuilder: (_, _) => Divider(color: t.line),
                  itemBuilder: (c, i) => _ListTile(book: books[i]),
                ),
              ),
            ],
            if (wanted.isNotEmpty) ...[
              SliverToBoxAdapter(child: _StripHeader('Not in your library', wanted.length, tab: 1)),
              SliverToBoxAdapter(
                child: _Tiles(
                  strip: false,
                  builder: (w) => [
                    for (final x in wanted)
                      GestureDetector(
                        onTap: () => openBookInfo(context, infoFrom(x)),
                        child: SizedBox(
                          width: w,
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            NetCover(url: x.coverUrl, title: x.title),
                            const SizedBox(height: 6),
                            Text(x.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, height: 1.15)),
                          ]),
                        ),
                      ),
                  ],
                ),
              ),
            ],
            if (audio.isNotEmpty) ...[
              SliverToBoxAdapter(child: _StripHeader('Audiobooks', audio.length, tab: 2)),
              SliverToBoxAdapter(child: _Tiles(strip: home, builder: (w) => [for (final b in home ? audio.take(14) : audio) _AudioTile(book: b, width: w)])),
            ],
            if (shows.isNotEmpty) ...[
              SliverToBoxAdapter(child: _StripHeader('Your shows', shows.length, tab: 3)),
              SliverToBoxAdapter(child: _Tiles(strip: home, builder: (w) => [for (final x in home ? shows.take(14) : shows) ShowTile(show: x, width: w)])),
              if (home && Podcasts.i.latest.isNotEmpty)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
                    child: Panel(
                      onTap: () => openEpisodes(context, 'New episodes', () => Podcasts.i.latest, showShow: true),
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      child: Row(children: [
                        Icon(Icons.fiber_new_sharp, color: t.accent),
                        const SizedBox(width: 12),
                        Expanded(child: Text('New episodes · ${Podcasts.i.latest.length}', style: const TextStyle(fontWeight: FontWeight.w600))),
                        Icon(Icons.chevron_right_sharp, color: t.muted),
                      ]),
                    ),
                  ),
                ),
            ],
            if (radio.isNotEmpty) ...[
              SliverToBoxAdapter(child: _StripHeader(home ? 'Favourite stations' : 'Radio', radio.length, tab: 3)),
              SliverToBoxAdapter(child: _Tiles(strip: home, builder: (w) => [for (final x in home ? radio.take(14) : radio) StationTile(station: x, width: w)])),
            ],
            if (home && !nothing && (AudioLibrary.i.books.isEmpty || Podcasts.i.subscriptions.isEmpty))
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
                  child: Row(children: [
                    if (AudioLibrary.i.books.isEmpty) Expanded(child: _Try(Icons.headphones_outlined, 'Try audiobooks', () => shellTab.value = 2)),
                    if (AudioLibrary.i.books.isEmpty && Podcasts.i.subscriptions.isEmpty) const SizedBox(width: 8),
                    if (Podcasts.i.subscriptions.isEmpty) Expanded(child: _Try(Icons.podcasts_sharp, 'Find podcasts', () => shellTab.value = 3)),
                  ]),
                ),
              ),
            if (!nothing && books.isEmpty && audio.isEmpty && shows.isEmpty && wanted.isEmpty && radio.isEmpty)
              const SliverToBoxAdapter(child: Padding(padding: EdgeInsets.all(40), child: Center(child: Label('Nothing here')))),
            const SliverToBoxAdapter(child: SizedBox(height: 32)),
          ]),
        );
      },
    );
  }

  Widget _header(BuildContext context, Library lib) {
    final h = DateTime.now().hour;
    final greeting = h < 5 ? 'Reading late' : (h < 12 ? 'Good morning' : (h < 18 ? 'Good afternoon' : 'Good evening'));
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 14),
      child: Row(children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            Row(children: [
              const Pip(size: 6),
              Flexible(child: Label(greeting, size: 9.5)),
            ]),
            const SizedBox(height: 8),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text('Library', style: Theme.of(context).textTheme.displaySmall?.copyWith(fontWeight: FontWeight.w700, letterSpacing: -1.2, height: 1)),
            ),
          ]),
        ),
        const SizedBox(width: 12),
        ToolButton(Icons.insights_sharp, tooltip: 'Stats', onTap: () => openStats(context)),
        const SizedBox(width: 8),
        ToolButton(Icons.folder_outlined, tooltip: 'Folders', onTap: () => openFolders(context, FolderKind.books)),
        const SizedBox(width: 8),
        ToolButton(Icons.add_sharp, active: true, tooltip: 'Add books', onTap: () => importBooks(context)),
      ]),
    );
  }

  Widget _filters(BuildContext context, Library lib) {
    final t = Tokens.of(context);
    final items = <(String, String, Color?)>[
      ('all', 'All', null),
      ('books', 'Books', null),
      ('audio', 'Audiobooks', null),
      ('shows', 'Podcasts', null),
      ('radio', 'Radio', null),
      ('reading', 'In progress', null),
      ('unread', 'Not started', null),
      ('finished', 'Finished', null),
      ('fav', '★ Favourites', null),
      for (final f in lib.folders) (f.id, f.name, Color(f.color)),
      ('pdf', 'PDF', null),
      ('epub', 'EPUB', null),
      ('docx', 'DOCX', null),
    ];
    return SizedBox(
      height: 40,
      child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 20), children: [
        for (final it in items)
          Padding(
            padding: const EdgeInsets.only(right: 6),
            child: GestureDetector(
              onLongPress: lib.folders.any((f) => f.id == it.$1) ? () => showFolderEditor(context, folder: lib.folders.firstWhere((f) => f.id == it.$1)) : null,
              child: Tag(
                it.$3 == null ? it.$2 : '■ ${it.$2}',
                filled: _filter == it.$1,
                color: _filter == it.$1 ? (it.$3 ?? t.ink) : (it.$3 ?? t.ink),
                onTap: () => setState(() => _filter = it.$1),
              ),
            ),
          ),
      ]),
    );
  }

  Widget _empty(BuildContext context) {
    final t = Tokens.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 40),
      child: Panel(
        padding: const EdgeInsets.all(24),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (!t.zen) ...[Label('Status: empty', color: t.accent), const SizedBox(height: 12)],
          Text('Your shelf is clear.', style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          Text('Add PDF, EPUB or DOCX files, open them from any app with "Open with → Alexandria", or grab free classics in Discover.',
              style: TextStyle(color: t.muted, height: 1.45)),
          const SizedBox(height: 20),
          PrimaryButton('Import files', icon: Icons.file_open_outlined, onTap: () => importBooks(context)),
        ]),
      ),
    );
  }
}

class _SortMenu extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    const opts = {'recent': 'Recent', 'added': 'Added', 'title': 'Title', 'author': 'Author', 'progress': 'Progress'};
    return PopupMenuButton<String>(
      onSelected: (v) => Settings.i.librarySort = v,
      itemBuilder: (_) => [for (final e in opts.entries) PopupMenuItem(value: e.key, child: Label(e.value, color: Tokens.of(context).ink))],
      child: Container(
        height: 32,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        alignment: Alignment.center,
        decoration: BoxDecoration(color: Tokens.of(context).zen ? Tokens.of(context).raised : null, border: Tokens.of(context).hair, borderRadius: Tokens.of(context).br),
        child: Label('Sort: ${opts[Settings.i.librarySort] ?? 'Recent'}', color: Tokens.of(context).ink),
      ),
    );
  }
}

/// Everything in progress, newest first: books, audiobooks and episodes side by side.
class _ContinueRail extends StatelessWidget {
  const _ContinueRail();

  @override
  Widget build(BuildContext context) {
    // Const, so a parent rebuild skips it: it has to listen for itself.
    return ListenableBuilder(listenable: Listenable.merge([Library.i, AudioLibrary.i, Podcasts.i]), builder: (context, _) => _rail(context));
  }

  Widget _rail(BuildContext context) {
    final items = <(int, DateTime, Widget)>[
      for (final b in Library.i.books.where((b) => b.status == ReadStatus.reading && b.lastOpenedAt != null))
        (
          0,
          b.lastOpenedAt!,
          _RailCard(
            art: Cover(b),
            artWidth: 58,
            kind: 'Reading',
            title: b.title,
            subtitle: b.author,
            progress: b.progress,
            detail: b.wordCount > 0 ? 'about ${fmtDuration((b.wordCount * (1 - b.progress) / 230).round() * 60)} to go' : '',
            icon: Icons.menu_book_sharp,
            onTap: () => openBook(context, b),
            onAction: () => openBook(context, b),
          ),
        ),
      for (final b in AudioLibrary.i.books.where((b) => !b.finished && b.lastPlayedAt != null))
        (
          1,
          b.lastPlayedAt!,
          _RailCard(
            art: AudioCover(b, shadow: false),
            artWidth: 72,
            kind: 'Audiobook',
            title: b.title,
            subtitle: b.author,
            progress: b.progress,
            detail: b.tracks.length > 1 ? 'Chapter ${b.trackIndex + 1} of ${b.tracks.length}' : '',
            sourceKey: b.id,
            onTap: () => playAudiobook(context, b),
            onAction: () => Player.i.book?.id == b.id ? Player.i.toggle() : Player.i.open(b),
          ),
        ),
      for (final s in Podcasts.i.inProgress)
        (
          2,
          s.updatedAt,
          _RailCard(
            art: PodcastArt(s.episode.art, title: s.episode.podcastTitle),
            artWidth: 72,
            kind: 'Podcast',
            title: s.episode.title,
            subtitle: s.episode.podcastTitle,
            progress: Podcasts.i.progressOf(s.episode),
            detail: s.episode.durationMs > 0 ? '${fmtDuration(((s.episode.durationMs - s.posMs) / 1000).round().clamp(0, 1 << 30))} left' : '',
            sourceKey: s.episode.guid,
            onTap: () => showEpisode(context, s.episode),
            onAction: () => Podcasts.i.play(s.episode),
          ),
        ),
    ]..sort((a, b) => a.$1 != b.$1 ? a.$1.compareTo(b.$1) : b.$2.compareTo(a.$2));
    if (items.isEmpty) return const SizedBox.shrink();
    final w = MediaQuery.of(context).size.width;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const SectionHeader('', 'Continue', padding: EdgeInsets.fromLTRB(20, 18, 20, 10)),
      SizedBox(
        height: MediaQuery.textScalerOf(context).scale(14) * 8.5 + 18,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 20),
          itemCount: items.length,
          separatorBuilder: (_, _) => const SizedBox(width: 10),
          // One card fills the row; more than one peeks to show it scrolls.
          itemBuilder: (_, i) => SizedBox(width: items.length == 1 ? w - 40 : w * .8, child: items[i].$3),
        ),
      ),
    ]);
  }
}

class _RailCard extends StatelessWidget {
  const _RailCard({
    required this.art,
    required this.artWidth,
    required this.kind,
    required this.title,
    required this.subtitle,
    required this.progress,
    required this.detail,
    required this.onTap,
    required this.onAction,
    this.icon,
    this.sourceKey,
  });

  final Widget art;
  final double artWidth;
  final String kind;
  final String title;
  final String subtitle;
  final double progress;
  final String detail;
  final VoidCallback onTap;
  final VoidCallback onAction;

  /// A fixed action icon (books), or null for a play/pause that follows the player.
  final IconData? icon;

  /// What the player must be on for this card to show as active.
  final String? sourceKey;

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    return Panel(
      onTap: onTap,
      padding: const EdgeInsets.all(12),
      child: Row(children: [
        SizedBox(width: artWidth, child: art),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
            Label(kind, color: t.accent, size: 9),
            const SizedBox(height: 3),
            Text(title, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700, height: 1.15)),
            if (subtitle.isNotEmpty) Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: t.muted, fontSize: 12.5)),
            const SizedBox(height: 8),
            _Meter(value: progress),
            if (detail.isNotEmpty) ...[const SizedBox(height: 5), Label(detail, size: 9)],
          ]),
        ),
        const SizedBox(width: 10),
        // Only this button follows the player, so the page doesn't rebuild with every tick.
        ListenableBuilder(
          listenable: Player.i,
          builder: (context, _) {
            final b = Player.i.book;
            final on = sourceKey != null && b != null && (b.id == sourceKey || b.sourceKey == sourceKey);
            return ToolButton(icon ?? (on && Player.i.playing ? Icons.pause_sharp : Icons.play_arrow_sharp), size: 40, active: true, onTap: onAction);
          },
        ),
      ]),
    );
  }
}

class _StripHeader extends StatelessWidget {
  const _StripHeader(this.title, this.count, {required this.tab});
  final String title;
  final int count;
  final int tab;

  @override
  Widget build(BuildContext context) {
    return SectionHeader(
      '',
      '$title · $count',
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 10),
      trailing: SeeAll(onTap: () => shellTab.value = tab),
    );
  }
}

/// Square-art tiles: a scrolling strip on the home view, every match on a filtered one.
class _Tiles extends StatelessWidget {
  const _Tiles({required this.strip, required this.builder});
  final bool strip;
  final List<Widget> Function(double width) builder;

  @override
  Widget build(BuildContext context) {
    if (strip) {
      final children = builder(96);
      return SizedBox(
        height: 102 + MediaQuery.textScalerOf(context).scale(32) + 6,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 20),
          itemCount: children.length,
          separatorBuilder: (_, _) => const SizedBox(width: 12),
          itemBuilder: (_, i) => children[i],
        ),
      );
    }
    final w = (MediaQuery.of(context).size.width - 40 - 24) / 3;
    return Padding(padding: const EdgeInsets.symmetric(horizontal: 20), child: Wrap(spacing: 12, runSpacing: 16, children: builder(w)));
  }
}

class _AudioTile extends StatelessWidget {
  const _AudioTile({required this.book, required this.width});
  final Audiobook book;
  final double width;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => openAudiobook(context, book),
      onLongPress: () {
        haptic(true);
        showAudiobookActions(context, book);
      },
      child: SizedBox(
        width: width,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          AudioCover(book, showProgress: true),
          const SizedBox(height: 6),
          Text(book.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, height: 1.15)),
        ]),
      ),
    );
  }
}

class _Try extends StatelessWidget {
  const _Try(this.icon, this.label, this.onTap);
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    return Panel(
      onTap: onTap,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      child: Row(children: [
        Icon(icon, size: 18, color: t.accent),
        const SizedBox(width: 8),
        Expanded(child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13))),
      ]),
    );
  }
}

/// A quiet progress rule.
class _Meter extends StatelessWidget {
  const _Meter({required this.value});
  final double value;

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    return ClipRRect(
      borderRadius: BorderRadius.circular(2),
      child: SizedBox(
        height: 4,
        child: Stack(children: [
          Container(color: t.line),
          FractionallySizedBox(widthFactor: value.clamp(0, 1), child: Container(color: t.accent)),
        ]),
      ),
    );
  }
}

class _GridTile extends StatelessWidget {
  const _GridTile({required this.book});
  final Book book;

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    return GestureDetector(
      onTap: () => openBook(context, book),
      onLongPress: () {
        haptic(true);
        showBookActions(context, book);
      },
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Hero(tag: 'cover-${book.id}', child: Cover(book, showProgress: Settings.i.showProgressOnCovers)),
        const SizedBox(height: 8),
        Text(book.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, height: 1.2)),
        const SizedBox(height: 3),
        Row(children: [
          if (book.favorite) Padding(padding: const EdgeInsets.only(right: 4), child: Icon(Icons.star_sharp, size: 10, color: t.accent)),
          Expanded(child: Label(book.status == ReadStatus.finished ? 'Done' : (book.progress > 0 ? '${(book.progress * 100).round()}%' : book.formatLabel), size: 9)),
        ]),
      ]),
    );
  }
}

class _ListTile extends StatelessWidget {
  const _ListTile({required this.book});
  final Book book;

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    final folders = Library.i.folders.where((f) => book.folderIds.contains(f.id)).toList();
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => openBook(context, book),
      onLongPress: () {
        haptic(true);
        showBookActions(context, book);
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(children: [
          SizedBox(width: 52, child: Cover(book, showProgress: Settings.i.showProgressOnCovers)),
          const SizedBox(width: 14),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(book.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
              if (book.author.isNotEmpty) Text(book.author, maxLines: 1, style: TextStyle(color: t.muted, fontSize: 13)),
              const SizedBox(height: 6),
              Row(children: [
                Label(book.formatLabel, color: t.accent),
                const SizedBox(width: 8),
                Label('${(book.progress * 100).round()}%'),
                for (final f in folders) ...[const SizedBox(width: 8), Container(width: 6, height: 6, color: Color(f.color)), const SizedBox(width: 4), Label(f.name)],
              ]),
            ]),
          ),
          IconButton(onPressed: () => showBookActions(context, book), icon: Icon(Icons.more_vert_sharp, color: t.muted)),
        ]),
      ),
    );
  }
}

Future<void> showBookActions(BuildContext context, Book book) async {
  await showSheet(context, builder: (ctx) {
    return ListenableBuilder(
      listenable: Library.i,
      builder: (ctx, _) {
        final t = Tokens.of(ctx);
        Widget row(IconData i, String l, VoidCallback onTap, {Color? color}) => ListTile(
              dense: true,
              leading: Icon(i, size: 20, color: color ?? t.ink),
              title: Text(l, style: TextStyle(color: color ?? t.ink, fontWeight: FontWeight.w500)),
              onTap: () {
                haptic();
                onTap();
              },
            );
        return Padding(
          padding: const EdgeInsets.fromLTRB(8, 4, 8, 20),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
              child: Row(children: [
                SizedBox(width: 44, child: Cover(book)),
                const SizedBox(width: 14),
                Expanded(child: Text(book.title, maxLines: 2, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16))),
              ]),
            ),
            row(Icons.menu_book_sharp, 'Read', () {
              Navigator.pop(ctx);
              openBook(context, book);
            }),
            row(Icons.ios_share_sharp, 'Share card', () {
              Navigator.pop(ctx);
              showMediaCard(context, ShareItem.book(book));
            }),
            row(Icons.info_outline_rounded, 'Details & info', () {
              Navigator.pop(ctx);
              openDetail(context, book);
            }),
            row(book.favorite ? Icons.star_sharp : Icons.star_border_sharp, book.favorite ? 'Unfavourite' : 'Favourite', () {
              book.favorite = !book.favorite;
              Library.i.touch(book);
            }),
            row(book.status == ReadStatus.finished ? Icons.replay_sharp : Icons.check_sharp, book.status == ReadStatus.finished ? 'Mark as unread' : 'Mark as finished', () {
              if (book.status == ReadStatus.finished) {
                book.status = ReadStatus.unread;
                book.finishedAt = null;
              } else {
                book.status = ReadStatus.finished;
                book.finishedAt = DateTime.now();
              }
              Library.i.touch(book);
            }),
            const Padding(padding: EdgeInsets.fromLTRB(16, 12, 16, 8), child: Label('Folders')),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Wrap(spacing: 6, runSpacing: 6, children: [
                for (final f in Library.i.folders) Tag(f.name, color: Color(f.color), filled: book.folderIds.contains(f.id), onTap: () => Library.i.toggleFolder(book, f)),
                Tag('+ New', color: t.accent, onTap: () async {
                  final n = await promptText(ctx, title: 'New folder');
                  if (n != null && n.trim().isNotEmpty) Library.i.toggleFolder(book, Library.i.addFolder(n.trim()));
                }),
              ]),
            ),
            const SizedBox(height: 8),
            row(Icons.delete_outline_sharp, 'Remove from library', color: const Color(0xFFE5243B), () async {
              if (await confirm(ctx, 'Remove book', 'Deletes "${book.title}", its highlights and bookmarks from Alexandria. Reading stats are kept.')) {
                await Library.i.remove(book);
                if (ctx.mounted) Navigator.pop(ctx);
              }
            }),
          ]),
        );
      },
    );
  });
}

import 'package:material_ui/material_ui.dart';

import '../core/search_box.dart';
import '../core/theme.dart';
import '../core/ui.dart';
import '../models/audiobook.dart';
import '../services/api_cache.dart';
import '../services/audio.dart';
import '../services/folders.dart';
import '../services/downloads.dart';
import '../services/free_audio.dart';
import 'audiobook_create.dart';
import 'audiobook_screen.dart';
import 'folders_screen.dart';
import 'book_info_screen.dart' show NetCover;
import 'player_screen.dart';
import 'downloads_screen.dart';
import 'media_card.dart';
import 'recently_added.dart';
import '../core/skeleton.dart';

class AudiobooksScreen extends StatefulWidget {
  const AudiobooksScreen({super.key});

  @override
  State<AudiobooksScreen> createState() => _AudiobooksScreenState();
}

class _AudiobooksScreenState extends State<AudiobooksScreen> {
  String _tab = 'shelf';
  String _source = 'librivox';

  /// 'all' or 'fav'.
  String _shelfFilter = 'all';
  String _shelfSort = 'recent';
  final _q = TextEditingController();
  List<FreeAudiobook>? _results;
  bool _loading = false;

  @override
  void dispose() {
    _q.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    FreeAudio.unreachable = false;
    setState(() => _loading = true);
    final q = _q.text.trim();
    final r = _source == 'librivox' ? await FreeAudio.librivox(q) : await FreeAudio.archive(q);
    if (!mounted) return;
    setState(() {
      _results = r;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      bottom: false,
      child: ListenableBuilder(
        listenable: Listenable.merge([AudioLibrary.i, Player.i]),
        builder: (context, _) => RefreshIndicator(
          // Pull to refresh is the only time the free catalogue asks the network again early.
          onRefresh: () async {
            if (_tab == 'free') await ApiCache.fresh(_search);
          },
          child: CustomScrollView(physics: const AlwaysScrollableScrollPhysics(), slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      const Kicker('Listen / audio', pip: 6),
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Text('Audiobooks', style: Theme.of(context).textTheme.displaySmall?.copyWith(fontWeight: FontWeight.w700, letterSpacing: -1.2, height: 1)),
                      ),
                    ]),
                  ),
                  const SizedBox(width: 12),
                  ToolButton(Icons.folder_outlined, tooltip: 'Folders', onTap: () => openFolders(context, FolderKind.audio)),
                  const SizedBox(width: 8),
                  ToolButton(Icons.add_sharp, active: true, tooltip: 'Add from your files', onTap: () => addAudiobookFromFiles(context)),
                ]),
                const SizedBox(height: 16),
                Segmented<String>(
                  values: const ['shelf', 'free', 'downloads'],
                  labels: const ['My shelf', 'Free', 'Downloads'],
                  value: _tab,
                  onChanged: (v) {
                    setState(() => _tab = v);
                    if (v == 'free' && _results == null) _search();
                  },
                ),
              ]),
            ),
          ),
          if (_tab == 'shelf') ..._shelf(context) else if (_tab == 'free') ..._free(context) else const SliverToBoxAdapter(child: AudiobookDownloads()),
          const SliverToBoxAdapter(child: SizedBox(height: 32)),
        ]),
        ),
      ),
    );
  }

  List<Widget> _shelf(BuildContext context) {
    final t = Tokens.of(context);
    final all = AudioLibrary.i.recent;
    final books = all.where((b) => _shelfFilter == 'all' || b.mark.favorite).toList();
    switch (_shelfSort) {
      case 'title':
        books.sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));
      case 'author':
        books.sort((a, b) => a.author.toLowerCase().compareTo(b.author.toLowerCase()));
      case 'rating':
        books.sort((a, b) => b.mark.rating.compareTo(a.mark.rating));
      case 'progress':
        books.sort((a, b) => b.progress.compareTo(a.progress));
    }
    if (all.isEmpty) {
      return [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
            child: Panel(
              padding: const EdgeInsets.all(22),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Icon(Icons.headphones_outlined, color: t.accent, size: 28),
                const SizedBox(height: 12),
                Text('No audiobooks yet', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
                const SizedBox(height: 6),
                Text('Add MP3, M4A/M4B, OGG or other audio files from your phone. Alexandria looks up the cover and description for you. Or stream thousands of free public-domain audiobooks.',
                    style: TextStyle(color: t.muted, height: 1.45)),
                const SizedBox(height: 18),
                PrimaryButton('Add audio files', icon: Icons.audio_file_outlined, expand: true, onTap: () => addAudiobookFromFiles(context)),
                const SizedBox(height: 8),
                PrimaryButton('Browse free audiobooks', ghost: true, icon: Icons.public_sharp, expand: true, onTap: () {
                  setState(() => _tab = 'free');
                  if (_results == null) _search();
                }),
              ]),
            ),
          ),
        ),
      ];
    }
    final current = _shelfFilter == 'all' ? books.where((b) => !b.finished && (b.lastPlayedAt != null)).firstOrNull : null;
    return [
      if (_shelfFilter == 'all') const SliverToBoxAdapter(child: RecentlyAdded(kinds: {AddedKind.audio})),
      if (current != null) ...[
        const SliverToBoxAdapter(child: SectionHeader('01', 'Continue listening', padding: EdgeInsets.fromLTRB(20, 22, 20, 10))),
        SliverToBoxAdapter(child: _ContinueListening(book: current)),
      ],
      SliverToBoxAdapter(child: SectionHeader(current != null ? '02' : '01', 'Shelf · ${books.length}',
          padding: const EdgeInsets.fromLTRB(20, 22, 20, 8),
          trailing: PopupMenuButton<String>(
            onSelected: (v) => setState(() => _shelfSort = v),
            itemBuilder: (_) => [for (final e in const {'recent': 'Recent', 'title': 'Title', 'author': 'Author', 'rating': 'Rating', 'progress': 'Progress'}.entries) PopupMenuItem(value: e.key, child: Text(e.value))],
            child: Tag(const {'recent': 'Recent', 'title': 'Title', 'author': 'Author', 'rating': 'Rating', 'progress': 'Progress'}[_shelfSort]!),
          ),
        )),
      SliverToBoxAdapter(
        child: SizedBox(
          height: 36,
          child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 20), children: [
            Padding(padding: const EdgeInsets.only(right: 6), child: Tag('All', filled: _shelfFilter == 'all', onTap: () => setState(() => _shelfFilter = 'all'))),
            Padding(padding: const EdgeInsets.only(right: 6), child: Tag('★ Favourites', filled: _shelfFilter == 'fav', onTap: () => setState(() => _shelfFilter = 'fav'))),
          ]),
        ),
      ),
      const SliverToBoxAdapter(child: SizedBox(height: 10)),
      SliverPadding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        sliver: SliverLayoutBuilder(builder: (context, c) {
          final tileW = (c.crossAxisExtent - 14 * 2) / 3;
          final textH = MediaQuery.textScalerOf(context).scale(46) + 14;
          return SliverGrid(
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 3, mainAxisSpacing: 16, crossAxisSpacing: 14, mainAxisExtent: tileW + textH),
            delegate: SliverChildBuilderDelegate((context, i) {
              final b = books[i];
              return GestureDetector(
                onTap: () => openAudiobook(context, b),
                onLongPress: () {
                  haptic(true);
                  showAudiobookActions(context, b);
                },
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Hero(tag: 'audio-${b.id}', child: AudioCover(b, showProgress: true)),
                  const SizedBox(height: 8),
                  Text(b.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, height: 1.2)),
                  const SizedBox(height: 3),
                  Row(children: [
                    if (b.mark.favorite) Padding(padding: const EdgeInsets.only(right: 4), child: Icon(Icons.favorite_sharp, size: 10, color: t.accent)),
                    Expanded(child: Label(b.finished ? 'Done' : (b.progress > 0 ? '${(b.progress * 100).round()}%' : (b.streaming ? 'Stream' : '${b.tracks.length} ch')), size: 9)),
                  ]),
                ]),
              );
            }, childCount: books.length),
          );
        }),
      ),
    ];
  }

  List<Widget> _free(BuildContext context) {
    final t = Tokens.of(context);
    final results = _results ?? const <FreeAudiobook>[];
    return [
      SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SearchBox(historyKey: 'free-audiobooks', 
              controller: _q,
              textInputAction: TextInputAction.search,
              onSubmitted: (_) => _search(),
              decoration: InputDecoration(
                hintText: 'Title or author: Austen, Sherlock, Odyssey…',
                prefixIcon: const Icon(Icons.search_sharp, size: 18),
                suffixIcon: IconButton(icon: const Icon(Icons.arrow_forward_sharp, size: 18), onPressed: _search),
              ),
            ),
            const SizedBox(height: 10),
            Wrap(spacing: 6, children: [
              for (final (id, name) in const [('librivox', 'LibriVox'), ('archive', 'Internet Archive')])
                Tag(name, filled: _source == id, onTap: () {
                  setState(() {
                    _source = id;
                    _results = null;
                  });
                  _search();
                }),
            ]),
            const SizedBox(height: 6),
            Label(_source == 'librivox' ? 'Public-domain books read by volunteers · free, no account' : 'Audio Books & Poetry collection · free, no account', size: 9),
          ]),
        ),
      ),
      SliverToBoxAdapter(child: SectionHeader('', _q.text.isEmpty ? 'Browse' : 'Results · ${results.length}', padding: const EdgeInsets.fromLTRB(20, 20, 20, 8))),
      if (_loading)
        const SliverToBoxAdapter(child: SkeletonRows(count: 6, art: 64, lines: 3, padding: EdgeInsets.symmetric(horizontal: 20)))
      else if (results.isEmpty)
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.all(40),
            child: Column(children: [
              Text(FreeAudio.unreachable ? 'Couldn’t reach the catalogue. Check your connection.' : 'Nothing found. Check the spelling, or try the author.',
                  textAlign: TextAlign.center, style: TextStyle(color: t.muted)),
              if (FreeAudio.unreachable) ...[const SizedBox(height: 12), ToolButton(Icons.refresh_sharp, label: 'Retry', size: 36, onTap: _search)],
            ]),
          ),
        )
      else
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          sliver: SliverList.separated(
            itemCount: results.length,
            separatorBuilder: (_, _) => Divider(color: t.line),
            itemBuilder: (context, i) {
              final f = results[i];
              final have = AudioLibrary.i.shelved(f);
              return GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => FreeAudiobookScreen(book: f))),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    SizedBox(width: 64, child: AspectRatio(aspectRatio: 1, child: _FreeCover(f))),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(f.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
                        if (f.author.isNotEmpty) Text(f.author, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: t.muted, fontSize: 13)),
                        const SizedBox(height: 6),
                        Label([if (f.seconds > 0) fmtDuration(f.seconds), if (f.sections > 0) '${f.sections} ch', if (f.language.isNotEmpty) f.language, if (have) 'On shelf'].join(' · '), size: 9),
                      ]),
                    ),
                    Icon(Icons.chevron_right_sharp, color: t.muted),
                  ]),
                ),
              );
            },
          ),
        ),
    ];
  }
}

class _FreeCover extends StatelessWidget {
  const _FreeCover(this.f);
  final FreeAudiobook f;

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    return ClipRRect(
      borderRadius: BorderRadius.circular(t.zen ? 12 : t.radius + 2),
      child: FittedBox(fit: BoxFit.cover, clipBehavior: Clip.hardEdge, child: SizedBox(width: 100, height: 150, child: NetCover(url: f.coverUrl, title: f.title))),
    );
  }
}

class _ContinueListening extends StatelessWidget {
  const _ContinueListening({required this.book});
  final Audiobook book;

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    final active = Player.i.book?.id == book.id;
    final ch = book.tracks.isEmpty ? '' : book.tracks[book.trackIndex.clamp(0, book.tracks.length - 1)].title;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Panel(
        onTap: () => playAudiobook(context, book),
        padding: const EdgeInsets.all(14),
        child: Row(children: [
          SizedBox(width: 76, child: AudioCover(book, shadow: false)),
          const SizedBox(width: 16),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(book.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700, height: 1.15)),
              const SizedBox(height: 3),
              Text('Ch. ${book.trackIndex + 1} · $ch', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: t.muted, fontSize: 13)),
              const SizedBox(height: 12),
              ClipRRect(borderRadius: BorderRadius.circular(2), child: LinearProgressIndicator(value: book.progress, minHeight: 4)),
            ]),
          ),
          const SizedBox(width: 12),
          GestureDetector(
            onTap: () {
              haptic(true);
              if (active) {
                Player.i.toggle();
              } else {
                Player.i.open(book);
              }
            },
            child: Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(color: t.accent, borderRadius: t.zen ? BorderRadius.circular(12) : t.br),
              child: Icon(active && Player.i.playing ? Icons.pause_sharp : Icons.play_arrow_sharp, color: t.onAccent),
            ),
          ),
        ]),
      ),
    );
  }
}

/// Details for a free catalogue audiobook, with its chapter list.
class FreeAudiobookScreen extends StatefulWidget {
  const FreeAudiobookScreen({super.key, required this.book});
  final FreeAudiobook book;

  @override
  State<FreeAudiobookScreen> createState() => _FreeAudiobookScreenState();
}

class _FreeAudiobookScreenState extends State<FreeAudiobookScreen> {
  late Future<List<AudioTrack>> _tracks = _load();

  Future<List<AudioTrack>> _load() {
    FreeAudio.unreachable = false;
    return FreeAudio.tracks(widget.book);
  }

  bool _adding = false;

  /// null: not looked yet · true: looking · false: looked, nothing found.
  bool? _findingText;

  Audiobook? get _shelved => AudioLibrary.i.books.where((b) => b.source == widget.book.source && b.sourceKey == widget.book.key).firstOrNull;

  /// Puts the book on the shelf, attaching its free text when Gutenberg has it.
  Future<Audiobook?> _shelve() async {
    final have = _shelved;
    if (have != null) return have;
    final tracks = await _tracks;
    if (tracks.isEmpty) throw 'No playable audio in this item';
    final b = await AudioLibrary.i.addFree(widget.book, tracks);
    _findText(b);
    return b;
  }

  Future<void> _findText(Audiobook b) async {
    if (b.bookId != null || _findingText == true) return;
    setState(() => _findingText = true);
    final book = await AudioLibrary.i.attachFreeText(b);
    if (!mounted) return;
    setState(() => _findingText = book == null ? false : null);
    if (book != null) toast(context, 'Book text attached: read along');
  }

  Future<void> _play({int? track}) async {
    setState(() => _adding = true);
    try {
      final b = await _shelve();
      if (b != null && mounted) playAudiobook(context, b, track: track);
    } catch (e) {
      if (mounted) toast(context, '$e');
    } finally {
      if (mounted) setState(() => _adding = false);
    }
  }

  Future<void> _download() async {
    try {
      final b = await _shelve();
      if (b == null) return;
      final ok = await AudioLibrary.i.download(b);
      if (mounted && !ok && !Downloads.i.cancelled(b.id)) toast(context, 'Download stopped. Tap again to resume.');
    } catch (e) {
      if (mounted) toast(context, '$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    final f = widget.book;
    return Scaffold(
      appBar: AppBar(title: AppTitle(f.sourceName), actions: [
        IconButton(
          tooltip: 'Share card',
          onPressed: () => showMediaCard(context, ShareItem(kind: 'Audiobook', title: f.title, subtitle: f.author, detail: f.seconds > 0 ? fmtDuration(f.seconds) : '', about: f.description, coverUrl: f.coverUrl)),
          icon: const Icon(Icons.ios_share_sharp),
        ),
      ]),
      body: FutureBuilder<List<AudioTrack>>(
        future: _tracks,
        builder: (context, snap) {
          final tracks = snap.data ?? const <AudioTrack>[];
          final total = tracks.fold(0, (a, x) => a + x.ms) ~/ 1000;
          return ListView(padding: const EdgeInsets.fromLTRB(20, 8, 20, 40), children: [
            Center(child: SizedBox(width: 200, height: 200, child: _FreeCover(f))),
            const SizedBox(height: 20),
            Text(f.title, textAlign: TextAlign.center, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700, height: 1.15)),
            if (f.author.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 4), child: Text(f.author, textAlign: TextAlign.center, style: TextStyle(color: t.muted, fontSize: 15))),
            const SizedBox(height: 10),
            Center(
              child: Label([
                if ((total > 0 ? total : f.seconds) > 0) fmtDuration(total > 0 ? total : f.seconds),
                if (tracks.isNotEmpty) '${tracks.length} chapters',
                if (f.language.isNotEmpty) f.language,
              ].join(' · ')),
            ),
            const SizedBox(height: 18),
            PrimaryButton(
              _adding ? 'Loading…' : (AudioLibrary.i.shelved(f) ? 'Continue listening' : 'Add to shelf & play'),
              icon: Icons.play_arrow_sharp,
              expand: true,
              onTap: _adding || (snap.connectionState == ConnectionState.done && tracks.isEmpty) ? null : () => _play(),
            ),
            const SizedBox(height: 10),
            ListenableBuilder(
              listenable: Listenable.merge([AudioLibrary.i, Downloads.i]),
              builder: (context, _) {
                final b = _shelved;
                final dl = b == null ? null : Downloads.i.progress[b.id];
                final text = b == null ? null : AudioLibrary.i.bookFor(b);
                return Column(children: [
                  Row(children: [
                    Expanded(
                      child: dl != null
                          ? PrimaryButton('Downloading ${(dl * 100).round()}%', ghost: true, icon: Icons.close_sharp, onTap: () => Downloads.i.cancel(b!.id))
                          : (b != null && b.offline
                              ? PrimaryButton('Downloaded', ghost: true, icon: Icons.download_done_sharp, onTap: null)
                              : PrimaryButton('Download all', ghost: true, icon: Icons.download_sharp, onTap: tracks.isEmpty ? null : _download)),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: text != null
                          ? PrimaryButton('Read along', ghost: true, icon: Icons.menu_book_sharp, onTap: () => readAlong(context, b!, text))
                          : PrimaryButton(
                              _findingText == true ? 'Finding text…' : (_findingText == false ? 'No free text' : 'Get the text'),
                              ghost: true,
                              icon: Icons.menu_book_outlined,
                              onTap: _findingText != null || tracks.isEmpty
                                  ? null
                                  : () async {
                                      final b = await _shelve();
                                      if (b != null) _findText(b);
                                    },
                            ),
                    ),
                  ]),
                  if (dl != null) Padding(padding: const EdgeInsets.only(top: 8), child: LinearProgressIndicator(value: dl)),
                ]);
              },
            ),
            const SizedBox(height: 6),
            Center(child: Label('Streams until downloaded · text from Project Gutenberg when available', size: 9)),
            if (f.description.isNotEmpty) ...[
              const SectionHeader('01', 'About', padding: EdgeInsets.fromLTRB(0, 26, 0, 10)),
              CollapsibleText(f.description, lines: 5, style: TextStyle(height: 1.5, color: t.ink.withValues(alpha: .85))),
            ],
            const SectionHeader('02', 'Chapters', padding: EdgeInsets.fromLTRB(0, 26, 0, 6)),
            if (snap.connectionState != ConnectionState.done)
              const SkeletonRows(count: 6, art: null, lines: 2)
            else if (tracks.isEmpty)
              Row(children: [
                Expanded(child: Text(FreeAudio.unreachable ? 'Couldn’t load the chapters. Check your connection.' : 'This item has no playable audio files.', style: TextStyle(color: t.muted))),
                if (FreeAudio.unreachable) ToolButton(Icons.refresh_sharp, label: 'Retry', size: 34, onTap: () => setState(() => _tracks = _load())),
              ])
            else
              for (var i = 0; i < tracks.length; i++)
                InkWell(
                  onTap: _adding ? null : () => _play(track: i),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    decoration: BoxDecoration(border: Border(bottom: BorderSide(color: t.line))),
                    child: Row(children: [
                      SizedBox(width: 34, child: Label(pad(i + 1), color: t.accent)),
                      Expanded(child: Text(tracks[i].title, maxLines: 2, overflow: TextOverflow.ellipsis)),
                      if (tracks[i].ms > 0) Label(fmtClock(Duration(milliseconds: tracks[i].ms))),
                      const SizedBox(width: 6),
                      Icon(Icons.play_arrow_sharp, size: 20, color: t.muted),
                      ListenableBuilder(
                        listenable: Listenable.merge([Downloads.i, AudioLibrary.i]),
                        builder: (context, _) {
                          final b = _shelved;
                          if (b != null) return ChapterDownload(book: b, index: i);
                          // Not on the shelf yet: downloading a chapter puts it there.
                          return IconButton(
                            tooltip: 'Download chapter',
                            icon: Icon(Icons.download_sharp, size: 20, color: t.muted),
                            onPressed: () async {
                              try {
                                final s = await _shelve();
                                if (s != null) AudioLibrary.i.downloadTrack(s, i);
                              } catch (e) {
                                if (context.mounted) toast(context, '$e');
                              }
                            },
                          );
                        },
                      ),
                    ]),
                  ),
                ),
          ]);
        },
      ),
    );
  }
}

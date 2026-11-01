import 'package:material_ui/material_ui.dart';

import '../core/net_image.dart';
import '../core/search_box.dart';
import '../core/settings.dart';
import '../core/theme.dart';
import '../core/ui.dart';
import '../models/podcast.dart';
import '../services/api_cache.dart';
import '../services/audio.dart';
import '../services/downloads.dart';
import '../services/folders.dart';
import '../services/library.dart';
import '../services/podcasts.dart';
import 'downloads_screen.dart';
import 'folders_screen.dart';
import 'marks.dart';
import 'media_card.dart';
import 'player_screen.dart';
import 'radio_view.dart';
import 'recently_added.dart';

String fmtDate(DateTime? d) {
  if (d == null) return '';
  final now = DateTime.now();
  final days = DateTime(now.year, now.month, now.day).difference(DateTime(d.year, d.month, d.day)).inDays;
  if (days == 0) return 'Today';
  if (days == 1) return 'Yesterday';
  if (days < 7) return '${days}d ago';
  const m = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  return '${d.day} ${m[d.month - 1]}${d.year == now.year ? '' : ' ${d.year}'}';
}

/// Square show artwork.
class PodcastArt extends StatelessWidget {
  const PodcastArt(this.url, {super.key, required this.title, this.radius});
  final String? url;
  final String title;
  final double? radius;

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    final fallback = Container(
      color: t.raised,
      alignment: Alignment.center,
      padding: const EdgeInsets.all(8),
      child: Text(title, maxLines: 3, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center, style: TextStyle(color: t.muted, fontSize: 11, fontWeight: FontWeight.w600)),
    );
    return AspectRatio(
      aspectRatio: 1,
      child: Container(
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(borderRadius: BorderRadius.circular(radius ?? (t.zen ? 12 : t.radius + 2)), border: t.zen ? null : Border.all(color: t.line)),
        child: url == null ? fallback : NetImage(url!, fallback: fallback),
      ),
    );
  }
}

Future<void> openPodcast(BuildContext context, {String? feedUrl, PodcastHit? hit}) async {
  var url = feedUrl;
  if (url == null && hit != null) {
    url = await Podcasts.i.feedFor(hit);
    if (url == null) {
      if (context.mounted) toast(context, 'This show has no public feed');
      return;
    }
  }
  if (url == null || !context.mounted) return;
  await Navigator.of(context).push(MaterialPageRoute(builder: (_) => PodcastScreen(feedUrl: url!, hit: hit)));
}

/// The Podcasts tab: your shows, shortcuts to episode lists, explore and search.
class PodcastsScreen extends StatefulWidget {
  const PodcastsScreen({super.key});

  @override
  State<PodcastsScreen> createState() => _PodcastsScreenState();
}

class _PodcastsScreenState extends State<PodcastsScreen> with WidgetsBindingObserver {
  final _q = TextEditingController();
  List<PodcastHit>? _results;
  late Future<List<PodcastHit>> _explore = Podcasts.i.top();
  int? _genre;
  bool _searching = false;

  /// 'all' or 'fav'.
  String _shelf = 'all';

  /// 'podcasts' or 'radio'.
  String _tab = 'podcasts';
  final _radio = GlobalKey<RadioPaneState>();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // This notifies listeners, which isn't allowed while the tree is building.
    WidgetsBinding.instance.addPostFrameCallback((_) => Podcasts.i.refreshAll());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Cheap: feeds younger than an hour come from the cache.
    if (state == AppLifecycleState.resumed) Podcasts.i.refreshAll();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _q.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    final q = _q.text.trim();
    if (q.isEmpty) return setState(() => _results = null);
    Podcasts.i.unreachable = false;
    setState(() => _searching = true);
    final r = await Podcasts.i.search(q);
    if (mounted) {
      setState(() {
        _results = r;
        _searching = false;
      });
    }
  }

  void _pickGenre(int? g) {
    Podcasts.i.unreachable = false;
    setState(() {
      _genre = g;
      _explore = g == null ? Podcasts.i.top() : Podcasts.i.search(podcastGenres.firstWhere((x) => x.$2 == g).$1, genre: g);
    });
  }

  /// Pull to refresh: the one time everything goes back to the network.
  Future<void> _refresh() => ApiCache.fresh(() async {
        if (_tab == 'radio') return _radio.currentState?.load();
        await Podcasts.i.refreshAll();
        if (_results != null) await _search();
        _pickGenre(_genre);
        await _explore;
      });

  Future<void> _addUrl() async {
    final url = await promptText(context, title: 'Add by RSS link', hint: 'https://example.com/feed.xml');
    if (url == null || url.trim().isEmpty || !mounted) return;
    toast(context, 'Reading feed…');
    final pod = await Podcasts.i.addByUrl(url);
    if (!mounted) return;
    if (pod == null) return toast(context, 'That link is not a podcast feed');
    toast(context, 'Subscribed to ${pod.title}');
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      bottom: false,
      child: ListenableBuilder(
        listenable: Listenable.merge([Podcasts.i, Downloads.i, Library.i]),
        builder: (context, _) {
          final searchMode = _results != null || _searching;
          return RefreshIndicator(
            onRefresh: _refresh,
            child: CustomScrollView(physics: const AlwaysScrollableScrollPhysics(), slivers: [
              SliverToBoxAdapter(child: _header(context)),
              if (_tab == 'radio') RadioPane(key: _radio) else if (searchMode) ..._searchResults(context) else ...[
                const SliverToBoxAdapter(child: RecentlyAdded(kinds: {AddedKind.show})),
                ..._shows(context),
                ..._exploreSection(context),
              ],
              const SliverToBoxAdapter(child: SizedBox(height: 32)),
            ]),
          );
        },
      ),
    );
  }

  Widget _header(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Kicker(_tab == 'radio' ? 'Listen / radio' : 'Listen / podcasts', pip: 6),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(_tab == 'radio' ? 'Radio' : 'Podcasts', style: Theme.of(context).textTheme.displaySmall?.copyWith(fontWeight: FontWeight.w700, letterSpacing: -1.2, height: 1)),
              ),
            ]),
          ),
          const SizedBox(width: 12),
          ToolButton(Icons.folder_outlined, tooltip: 'Folders', onTap: () => openFolders(context, _tab == 'radio' ? FolderKind.radio : FolderKind.podcasts)),
          if (_tab == 'podcasts') ...[
            const SizedBox(width: 8),
            ToolButton(Icons.download_done_sharp, tooltip: 'Downloads', onTap: () => openDownloads(context)),
            const SizedBox(width: 8),
            ToolButton(Icons.rss_feed_sharp, tooltip: 'Add by RSS link', onTap: _addUrl),
          ],
        ]),
        const SizedBox(height: 14),
        Segmented<String>(values: const ['podcasts', 'radio'], labels: const ['Podcasts', 'Global Radio'], value: _tab, onChanged: (v) => setState(() => _tab = v)),
        if (_tab == 'podcasts') ...[
        const SizedBox(height: 10),
        SearchBox(historyKey: 'podcasts', 
          controller: _q,
          textInputAction: TextInputAction.search,
          onSubmitted: (_) => _search(),
          onChanged: (v) => setState(() {
            if (v.isEmpty) _results = null;
          }),
          decoration: InputDecoration(
            hintText: 'Search podcasts',
            prefixIcon: const Icon(Icons.search_sharp, size: 18),
            suffixIcon: _q.text.isEmpty
                ? null
                : IconButton(
                    icon: const Icon(Icons.close_sharp, size: 18),
                    onPressed: () => setState(() {
                      _q.clear();
                      _results = null;
                    }),
                  ),
          ),
        ),
        ],
      ]),
    );
  }

  List<Widget> _shows(BuildContext context) {
    final t = Tokens.of(context);
    final pods = Podcasts.i;
    if (pods.subscriptions.isEmpty) return const [];
    final shows = pods.subscriptions.where((x) {
      return _shelf == 'all' || pods.showMark(x.feedUrl).favorite;
    }).toList();
    return [
      SliverToBoxAdapter(
        child: SectionHeader(
          '',
          'Your shows · ${pods.subscriptions.length}',
          padding: const EdgeInsets.fromLTRB(20, 22, 20, 8),
          trailing: pods.refreshing ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 1.5)) : null,
        ),
      ),
      SliverToBoxAdapter(
        child: SizedBox(
          height: 36,
          child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 20), children: [
            Padding(padding: const EdgeInsets.only(right: 6), child: Tag('All', filled: _shelf == 'all', onTap: () => setState(() => _shelf = 'all'))),
            Padding(padding: const EdgeInsets.only(right: 6), child: Tag('★ Favourites', filled: _shelf == 'fav', onTap: () => setState(() => _shelf = 'fav'))),
          ]),
        ),
      ),
      const SliverToBoxAdapter(child: SizedBox(height: 10)),
      if (shows.isEmpty)
        SliverToBoxAdapter(child: Padding(padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10), child: Text('No favourites yet. Hold a show to favourite it.', style: TextStyle(color: t.muted))))
      else
        SliverToBoxAdapter(
          child: SizedBox(
            height: 140,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 20),
              itemCount: shows.length,
              separatorBuilder: (_, _) => const SizedBox(width: 12),
              itemBuilder: (context, i) => ShowTile(show: shows[i]),
            ),
          ),
        ),
    ];
  }

  List<Widget> _searchResults(BuildContext context) {
    final t = Tokens.of(context);
    final r = _results ?? const <PodcastHit>[];
    return [
      SliverToBoxAdapter(child: SectionHeader('', _searching ? 'Searching…' : 'Shows · ${r.length}', padding: const EdgeInsets.fromLTRB(20, 20, 20, 6))),
      if (_searching)
        const SliverToBoxAdapter(child: Padding(padding: EdgeInsets.all(40), child: Center(child: CircularProgressIndicator(strokeWidth: 1.5))))
      else if (r.isEmpty)
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.all(40),
            child: Center(child: Text(Podcasts.i.unreachable ? 'Couldn’t reach the podcast directory. Check your connection.' : 'No shows found.', textAlign: TextAlign.center, style: TextStyle(color: t.muted))),
          ),
        )
      else
        SliverPadding(padding: const EdgeInsets.symmetric(horizontal: 20), sliver: SliverList.list(children: [for (final h in r) _ShowRow(hit: h)])),
    ];
  }

  List<Widget> _exploreSection(BuildContext context) {
    final t = Tokens.of(context);
    return [
      const SliverToBoxAdapter(child: SectionHeader('', 'Explore', padding: EdgeInsets.fromLTRB(20, 22, 20, 10))),
      SliverToBoxAdapter(
        child: SizedBox(
          height: 36,
          child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 20), children: [
            Padding(padding: const EdgeInsets.only(right: 6), child: Tag('Top charts', filled: _genre == null, onTap: () => _pickGenre(null))),
            for (final (name, id) in podcastGenres) Padding(padding: const EdgeInsets.only(right: 6), child: Tag(name, filled: _genre == id, onTap: () => _pickGenre(id))),
          ]),
        ),
      ),
      SliverToBoxAdapter(
        child: FutureBuilder<List<PodcastHit>>(
          future: _explore,
          builder: (context, snap) {
            if (snap.connectionState != ConnectionState.done) {
              return const Padding(padding: EdgeInsets.all(40), child: Center(child: CircularProgressIndicator(strokeWidth: 1.5)));
            }
            final list = snap.data ?? const <PodcastHit>[];
            if (list.isEmpty) {
              return Padding(
                padding: const EdgeInsets.all(30),
                child: Column(children: [
                  Text(Podcasts.i.unreachable ? 'Couldn’t reach the podcast directory.' : 'Nothing here right now.', style: TextStyle(color: t.muted)),
                  const SizedBox(height: 10),
                  ToolButton(Icons.refresh_sharp, label: 'Retry', size: 36, onTap: () => _pickGenre(_genre)),
                ]),
              );
            }
            return LayoutBuilder(builder: (context, c) {
              final w = (c.maxWidth - 40 - 12 * 2) / 3;
              return Padding(
                padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
                child: Wrap(spacing: 12, runSpacing: 16, children: [
                  for (final (n, h) in list.indexed)
                    GestureDetector(
                      onTap: () => openPodcast(context, hit: h),
                      child: SizedBox(
                        width: w,
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          PodcastArt(h.artwork, title: h.title),
                          const SizedBox(height: 6),
                          Text(h.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, height: 1.15)),
                          Label(_genre == null ? '#${n + 1}${h.genre.isEmpty ? '' : ' · ${h.genre}'}' : h.author, size: 9),
                        ]),
                      ),
                    ),
                ]),
              );
            });
          },
        ),
      ),
    ];
  }
}

/// A subscribed show: tap to open, hold for its menu.
class ShowTile extends StatelessWidget {
  const ShowTile({super.key, required this.show, this.width = 96});
  final Podcast show;
  final double width;

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    final pods = Podcasts.i;
    final unplayed = show.episodes.take(10).where((e) => pods.stage(e) == 'unplayed').length;
    final fav = pods.showMark(show.feedUrl).favorite;
    return GestureDetector(
      onTap: () => openPodcast(context, feedUrl: show.feedUrl),
      onLongPress: () {
        haptic(true);
        showShowMenu(context, show);
      },
      child: SizedBox(
        width: width,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Stack(children: [
            PodcastArt(show.imageUrl, title: show.title),
            if (unplayed > 0)
              Positioned(
                right: 4,
                top: 4,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(color: t.accent, borderRadius: BorderRadius.circular(6)),
                  child: Text('$unplayed', style: TextStyle(color: t.onAccent, fontSize: 10.5, fontWeight: FontWeight.w700)),
                ),
              ),
            if (fav) Positioned(left: 5, top: 5, child: Icon(Icons.favorite_sharp, size: 14, color: t.accent)),
          ]),
          const SizedBox(height: 6),
          Text(show.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, height: 1.15)),
        ]),
      ),
    );
  }
}

/// Rate, favourite, take notes, file in folders, share or unsubscribe.
Future<void> showShowMenu(BuildContext context, Podcast show) {
  return showSheet(context, builder: (ctx) {
    return ListenableBuilder(
      listenable: Podcasts.i,
      builder: (ctx, _) {
        final pods = Podcasts.i;
        final subbed = pods.subscribed(show.feedUrl);
        return Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              SizedBox(width: 52, child: PodcastArt(show.imageUrl, title: show.title)),
              const SizedBox(width: 12),
              Expanded(child: Text(show.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700))),
            ]),
            const SizedBox(height: 14),
            MarksBar(mark: pods.showMark(show.feedUrl), title: show.title, changed: pods.marksChanged, folders: () => pods.foldersOf(show.feedUrl), onFolder: (id) => pods.toggleFolder(show.feedUrl, id)),
            const SizedBox(height: 16),
            Row(children: [
              Expanded(
                child: PrimaryButton('Share card', ghost: true, icon: Icons.ios_share_sharp, onTap: () {
                  Navigator.pop(ctx);
                  showMediaCard(context, ShareItem.podcast(show, pods.showMark(show.feedUrl)));
                }),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: PrimaryButton(subbed ? 'Unsubscribe' : 'Subscribe', ghost: subbed, icon: subbed ? Icons.close_sharp : Icons.add_sharp, onTap: () {
                  subbed ? pods.unsubscribe(show.feedUrl) : pods.subscribe(show);
                }),
              ),
            ]),
          ]),
        );
      },
    );
  });
}

/// A plain list of episodes on its own page.
void openEpisodes(BuildContext context, String title, List<Episode> Function() episodes, {bool showShow = false}) {
  Navigator.of(context).push(MaterialPageRoute(
    builder: (_) => Scaffold(
      appBar: AppBar(title: AppTitle(title)),
      bottomNavigationBar: const PagePlayer(),
      body: ListenableBuilder(
        listenable: Listenable.merge([Podcasts.i, Player.i, Downloads.i]),
        builder: (context, _) {
          final list = episodes();
          if (list.isEmpty) return Center(child: Text('All caught up.', style: TextStyle(color: Tokens.of(context).muted)));
          return ListView.builder(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
            itemCount: list.length,
            itemBuilder: (_, i) => EpisodeRow(episode: list[i], showShow: showShow),
          );
        },
      ),
    ),
  ));
}

class _ShowRow extends StatelessWidget {
  const _ShowRow({required this.hit});
  final PodcastHit hit;

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    final subbed = hit.feedUrl != null && Podcasts.i.subscribed(hit.feedUrl!);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => openPodcast(context, hit: hit),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(children: [
          SizedBox(width: 60, child: PodcastArt(hit.artwork, title: hit.title)),
          const SizedBox(width: 14),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(hit.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600)),
              Text(hit.author, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: t.muted, fontSize: 12.5)),
              const SizedBox(height: 3),
              Label([if (hit.genre.isNotEmpty) hit.genre, if (hit.episodes > 0) '${hit.episodes} episodes', if (subbed) 'Subscribed'].join(' · '), size: 9),
            ]),
          ),
          Icon(Icons.chevron_right_sharp, color: t.muted),
        ]),
      ),
    );
  }
}

/// One show: header, subscribe, and its episodes.
class PodcastScreen extends StatefulWidget {
  const PodcastScreen({super.key, required this.feedUrl, this.hit});
  final String feedUrl;
  final PodcastHit? hit;

  @override
  State<PodcastScreen> createState() => _PodcastScreenState();
}

class _PodcastScreenState extends State<PodcastScreen> {
  late Future<Podcast?> _feed = _load();
  bool _oldest = false;

  /// 'all', or an episode stage: 'unplayed', 'started', 'played'.
  String _filter = 'all';

  final _search = TextEditingController();

  Future<Podcast?> _load() {
    Podcasts.i.unreachable = false;
    return Podcasts.i.feed(widget.feedUrl, refresh: true);
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    return Scaffold(
      appBar: AppBar(title: AppTitle('Podcast')),
      bottomNavigationBar: const PagePlayer(),
      body: FutureBuilder<Podcast?>(
        future: _feed,
        // Show what we already know while the feed refreshes.
        initialData: Podcasts.i.cached(widget.feedUrl),
        builder: (context, snap) {
          final pod = snap.data;
          final loading = snap.connectionState != ConnectionState.done;
          if (pod == null) {
            if (loading) return const Center(child: CircularProgressIndicator(strokeWidth: 1.5));
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(30),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Text(Podcasts.i.unreachable ? 'Couldn’t load this show. Check your connection.' : 'This feed could not be read.', textAlign: TextAlign.center, style: TextStyle(color: t.muted)),
                  const SizedBox(height: 12),
                  ToolButton(Icons.refresh_sharp, label: 'Retry', size: 36, onTap: () => setState(() => _feed = _load())),
                ]),
              ),
            );
          }
          return ListenableBuilder(
            listenable: Listenable.merge([Podcasts.i, Player.i, Downloads.i]),
            builder: (context, _) {
              final subbed = Podcasts.i.subscribed(pod.feedUrl);
              final sorted = _oldest ? pod.episodes.reversed.toList() : pod.episodes;
              final query = _search.text.trim();
              final eps = sorted.where((e) => (_filter == 'all' || Podcasts.i.stage(e) == _filter) && (query.isEmpty || e.matches(query))).toList();
              int count(String stage) => pod.episodes.where((e) => Podcasts.i.stage(e) == stage).length;
              return RefreshIndicator(
                onRefresh: () => ApiCache.fresh(() async {
                  setState(() => _feed = _load());
                  await _feed;
                }),
                child: CustomScrollView(physics: const AlwaysScrollableScrollPhysics(), slivers: [
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      // The show's details step aside during a search, so the results
                      // sit right under the box instead of behind the keyboard.
                      if (query.isEmpty) ...[
                      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        SizedBox(width: 120, child: PodcastArt(pod.imageUrl ?? widget.hit?.artwork, title: pod.title)),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text(pod.title, maxLines: 3, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700, height: 1.15)),
                            if (pod.author.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 4), child: Text(pod.author, maxLines: 2, style: TextStyle(color: t.muted))),
                            const SizedBox(height: 8),
                            Label('${pod.episodes.length} episodes${loading ? ' · updating' : ''}', size: 9),
                          ]),
                        ),
                      ]),
                      const SizedBox(height: 16),
                      Row(children: [
                        Expanded(
                          child: PrimaryButton(subbed ? 'Subscribed' : 'Subscribe', ghost: subbed, icon: subbed ? Icons.check_sharp : Icons.add_sharp, onTap: () {
                            subbed ? Podcasts.i.unsubscribe(pod.feedUrl) : Podcasts.i.subscribe(pod);
                          }),
                        ),
                        const SizedBox(width: 10),
                        if (pod.episodes.isNotEmpty) ToolButton(Icons.play_arrow_sharp, size: 48, tooltip: 'Play latest', onTap: () => playEpisode(context, pod.episodes.first)),
                        const SizedBox(width: 10),
                        ToolButton(Icons.ios_share_sharp, size: 48, tooltip: 'Share card', onTap: () => showMediaCard(context, ShareItem.podcast(pod, Podcasts.i.showMark(pod.feedUrl)))),
                      ]),
                      const SizedBox(height: 14),
                      MarksBar(mark: Podcasts.i.showMark(pod.feedUrl), title: pod.title, changed: Podcasts.i.marksChanged, folders: () => Podcasts.i.foldersOf(pod.feedUrl), onFolder: (id) => Podcasts.i.toggleFolder(pod.feedUrl, id)),
                      if (pod.description.isNotEmpty) ...[
                        const SizedBox(height: 18),
                        CollapsibleText(pod.description, lines: 4, style: TextStyle(height: 1.5, color: t.ink.withValues(alpha: .85))),
                      ],
                      if (pod.categories.isNotEmpty) ...[
                        const SizedBox(height: 12),
                        Wrap(spacing: 6, runSpacing: 6, children: [for (final c in pod.categories.take(6)) Tag(c)]),
                      ],
                      ],
                      SectionHeader(
                        '',
                        query.isEmpty ? 'Episodes' : '${eps.length} found',
                        padding: const EdgeInsets.fromLTRB(0, 24, 0, 8),
                        trailing: Tag(_oldest ? 'Oldest first' : 'Newest first', onTap: () => setState(() => _oldest = !_oldest)),
                      ),
                      // Keyed so it keeps focus when the details above it go away.
                      SearchBox(
                        key: const ValueKey('show-search'),
                        historyKey: 'show-episodes',
                        controller: _search,
                        onChanged: (_) => setState(() {}),
                        decoration: InputDecoration(
                          hintText: 'Search this show',
                          prefixIcon: const Icon(Icons.search_sharp, size: 18),
                          suffixIcon: _search.text.isEmpty ? null : IconButton(tooltip: 'Clear', icon: const Icon(Icons.close_sharp, size: 18), onPressed: () => setState(_search.clear)),
                        ),
                      ),
                      const SizedBox(height: 10),
                      SizedBox(
                        height: 36,
                        child: ListView(scrollDirection: Axis.horizontal, children: [
                          for (final (id, name, n) in [('all', 'All', pod.episodes.length), ('unplayed', 'Unplayed', count('unplayed')), ('started', 'In progress', count('started')), ('played', 'Played', count('played'))])
                            Padding(padding: const EdgeInsets.only(right: 6), child: Tag('$name · $n', filled: _filter == id, onTap: () => setState(() => _filter = id))),
                        ]),
                      ),
                      if (eps.isEmpty) Padding(padding: const EdgeInsets.symmetric(vertical: 24), child: Center(child: Text(query.isEmpty ? 'No episodes in this view.' : 'No episodes match “$query”.', textAlign: TextAlign.center, style: TextStyle(color: t.muted)))),
                    ]),
                  ),
                ),
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 40),
                  sliver: SliverList.builder(itemCount: eps.length, itemBuilder: (_, i) => EpisodeRow(episode: eps[i], podcast: pod)),
                ),
              ]),
              );
            },
          );
        },
      ),
    );
  }
}

/// An episode with play, download and more.
class EpisodeRow extends StatelessWidget {
  const EpisodeRow({super.key, required this.episode, this.podcast, this.showShow = false});
  final Episode episode;
  final Podcast? podcast;
  final bool showShow;

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    final pods = Podcasts.i;
    final e = episode;
    final played = pods.played(e);
    final prog = pods.progressOf(e);
    final current = pods.isCurrent(e);
    final playing = pods.isPlaying(e);
    final dl = Downloads.i.progress[e.guid];
    final meta = [
      fmtDate(e.published),
      if (e.durationMs > 0) prog > 0 && !played ? '${fmtDuration((e.durationMs * (1 - prog) / 1000).round())} left' : fmtDuration(e.durationMs ~/ 1000),
      if (pods.isDownloaded(e)) 'Downloaded',
      if (pods.queued(e)) 'Queued',
    ].where((s) => s.isNotEmpty).join(' · ');
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => showEpisode(context, e, podcast: podcast),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(border: Border(bottom: BorderSide(color: t.line))),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (showShow) ...[SizedBox(width: 52, child: PodcastArt(e.art, title: e.podcastTitle)), const SizedBox(width: 12)],
          Expanded(
            child: Opacity(
              opacity: played ? .55 : 1,
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                if (showShow) Label(e.podcastTitle, size: 9, color: t.accent),
                Text(e.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontWeight: FontWeight.w600, color: current ? t.accent : t.ink, height: 1.25)),
                const SizedBox(height: 4),
                Row(children: [
                  if (played) Padding(padding: const EdgeInsets.only(right: 4), child: Icon(Icons.check_sharp, size: 13, color: t.muted)),
                  Expanded(child: Label(meta, size: 9)),
                ]),
                if (prog > 0 && !played)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: ClipRRect(borderRadius: BorderRadius.circular(2), child: LinearProgressIndicator(value: prog, minHeight: 3)),
                  ),
              ]),
            ),
          ),
          const SizedBox(width: 6),
          if (dl != null)
            SizedBox(
              width: 40,
              height: 40,
              child: GestureDetector(
                onTap: () => Downloads.i.cancel(e.guid),
                child: Padding(padding: const EdgeInsets.all(10), child: CircularProgressIndicator(strokeWidth: 2, value: dl < 0 ? null : dl)),
              ),
            ),
          ToolButton(playing ? Icons.pause_sharp : Icons.play_arrow_sharp, size: 40, active: current, tooltip: playing ? 'Pause' : 'Play', onTap: () => playEpisode(context, e)),
        ]),
      ),
    );
  }
}

/// Episode details and every action on it.
Future<void> showEpisode(BuildContext context, Episode e, {Podcast? podcast}) {
  return showSheet(context, builder: (ctx) {
    final t = Tokens.of(ctx);
    return ListenableBuilder(
      listenable: Listenable.merge([Podcasts.i, Player.i, Downloads.i]),
      builder: (ctx, _) {
        final pods = Podcasts.i;
        final played = pods.played(e);
        final dl = Downloads.i.progress[e.guid];
        Widget row(IconData i, String l, VoidCallback f) => ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: Icon(i, size: 20, color: t.ink),
              title: Text(l, style: TextStyle(color: t.ink, fontWeight: FontWeight.w500)),
              onTap: () {
                haptic();
                f();
              },
            );
        return Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              SizedBox(width: 64, child: PodcastArt(e.art, title: e.podcastTitle)),
              const SizedBox(width: 14),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Label(e.podcastTitle, color: t.accent, size: 9.5),
                  const SizedBox(height: 4),
                  Text(e.title, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700, height: 1.2)),
                  const SizedBox(height: 4),
                  Label([fmtDate(e.published), if (e.durationMs > 0) fmtDuration(e.durationMs ~/ 1000)].where((s) => s.isNotEmpty).join(' · '), size: 9),
                ]),
              ),
            ]),
            const SizedBox(height: 16),
            Row(children: [
              Expanded(
                child: PrimaryButton(pods.isPlaying(e) ? 'Pause' : (pods.progressOf(e) > 0 && !played ? 'Resume' : 'Play'), icon: pods.isPlaying(e) ? Icons.pause_sharp : Icons.play_arrow_sharp, onTap: () {
                  // Starting one leaves this sheet for the full player.
                  if (!pods.isCurrent(e) && Settings.i.openPlayerOnPlay) Navigator.pop(ctx);
                  playEpisode(context, e);
                }),
              ),
              const SizedBox(width: 10),
              ToolButton(
                dl != null ? Icons.close_sharp : (pods.isDownloaded(e) ? Icons.download_done_sharp : Icons.download_sharp),
                size: 48,
                active: pods.isDownloaded(e),
                tooltip: dl != null ? 'Cancel download' : (pods.isDownloaded(e) ? 'Remove download' : 'Download'),
                onTap: () {
                  if (dl != null) return Downloads.i.cancel(e.guid);
                  pods.isDownloaded(e) ? pods.removeDownload(e) : pods.download(e);
                },
              ),
            ]),
            if (dl != null) Padding(padding: const EdgeInsets.only(top: 8), child: LinearProgressIndicator(value: dl < 0 ? null : dl)),
            const SizedBox(height: 14),
            MarksBar(
              mark: pods.episodeMark(e),
              title: e.title,
              changed: pods.marksChanged,
              here: () => (track: 0, ms: pods.isCurrent(e) ? Player.i.position.inMilliseconds : (pods.states[e.guid]?.posMs ?? 0)),
              onSeek: (n) async {
                if (!pods.isCurrent(e)) await pods.play(e);
                await Player.i.seek(Duration(milliseconds: n.ms));
              },
            ),
            const SizedBox(height: 8),
            row(Icons.playlist_play_sharp, 'Play next', () {
              pods.enqueue(e, next: true);
              toast(ctx, 'Plays next');
            }),
            row(pods.queued(e) ? Icons.playlist_remove_sharp : Icons.playlist_add_sharp, pods.queued(e) ? 'Remove from queue' : 'Add to queue', () {
              pods.queued(e) ? pods.dequeue(e) : pods.enqueue(e);
            }),
            row(played ? Icons.replay_sharp : Icons.check_sharp, played ? 'Mark as unplayed' : 'Mark as played', () => pods.setPlayed(e, !played)),
            if (podcast != null) row(Icons.done_all_sharp, 'Mark older as played', () {
              pods.markOlderPlayed(podcast, e);
              Navigator.pop(ctx);
            }),
            if (podcast == null) row(Icons.podcasts_sharp, 'Go to show', () {
              Navigator.pop(ctx);
              openPodcast(context, feedUrl: e.feedUrl);
            }),
            row(Icons.ios_share_sharp, 'Share card', () {
              Navigator.pop(ctx);
              showMediaCard(context, ShareItem.episode(e, mark: pods.episodeMark(e), progress: pods.progressOf(e)));
            }),
            if (e.description.isNotEmpty) ...[
              const SectionHeader('', 'Show notes', padding: EdgeInsets.fromLTRB(0, 14, 0, 8)),
              CollapsibleText(e.description, lines: 8, style: TextStyle(height: 1.5, color: t.ink.withValues(alpha: .85))),
            ],
          ]),
        );
      },
    );
  });
}

/// The episode queue, reorderable.
Future<void> showQueue(BuildContext context) {
  return showSheet(context, scroll: false, builder: (ctx) {
    final t = Tokens.of(ctx);
    return ListenableBuilder(
      listenable: Podcasts.i,
      builder: (ctx, _) {
        final q = Podcasts.i.queue;
        return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 12, 4),
            child: Row(children: [
              Expanded(child: Label('Up next · ${q.length}', color: t.accent)),
              if (q.isNotEmpty) TextButton(onPressed: Podcasts.i.clearQueue, child: Label('Clear', color: t.muted)),
            ]),
          ),
          if (q.isEmpty) Padding(padding: const EdgeInsets.all(24), child: Text('Nothing queued. Add episodes from their menu.', style: TextStyle(color: t.muted))),
          Flexible(
            child: ReorderableListView.builder(
              shrinkWrap: true,
              buildDefaultDragHandles: false,
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
              itemCount: q.length,
              onReorderItem: Podcasts.i.reorderQueue,
              itemBuilder: (_, i) => Row(key: ValueKey(q[i].guid), children: [
                Expanded(child: EpisodeRow(episode: q[i], showShow: true)),
                ReorderableDragStartListener(index: i, child: Padding(padding: const EdgeInsets.all(8), child: Icon(Icons.drag_handle_sharp, color: t.muted))),
              ]),
            ),
          ),
        ]);
      },
    );
  });
}

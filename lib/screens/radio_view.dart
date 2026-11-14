import 'package:material_ui/material_ui.dart';
import 'package:url_launcher/url_launcher_string.dart';

import '../core/settings.dart';
import '../core/search_box.dart';
import '../core/theme.dart';
import '../core/ui.dart';
import '../models/radio.dart';
import '../services/audio.dart';
import '../services/library.dart';
import '../services/radio.dart';
import 'marks.dart';
import 'media_card.dart';
import 'player_screen.dart' show playStation;
import 'podcasts_view.dart' show PodcastArt;
import '../core/image_viewer.dart';
import '../core/skeleton.dart';

/// Global Radio: browse, search by name and country, favourites and recents.
class RadioPane extends StatefulWidget {
  const RadioPane({super.key});

  @override
  State<RadioPane> createState() => RadioPaneState();
}

class RadioPaneState extends State<RadioPane> {
  final _q = TextEditingController();

  /// 'all', 'fav', 'recent' or a genre tag.
  String _view = 'all';
  List<Station> _results = const [];
  bool _loading = true;
  bool _hasMore = false;

  @override
  void initState() {
    super.initState();
    load();
  }

  @override
  void dispose() {
    _q.dispose();
    super.dispose();
  }

  bool get _isGenre => _view != 'all' && _view != 'fav' && _view != 'recent';

  Future<void> load() async {
    final dir = RadioDirectory.i;
    dir.unreachable = false;
    setState(() => _loading = true);
    final r = await dir.browse(name: _q.text, country: Settings.i.radioCountry, countryName: Settings.i.radioCountryName, tag: _isGenre ? _view : null);
    if (!mounted) return;
    setState(() {
      _results = r;
      _hasMore = r.length >= RadioDirectory.pageSize ~/ 2;
      _loading = false;
    });
  }

  Future<void> _more() async {
    final more = await RadioDirectory.i.browse(name: _q.text, country: Settings.i.radioCountry, countryName: Settings.i.radioCountryName, tag: _isGenre ? _view : null, offset: _results.length);
    if (!mounted) return;
    final have = {for (final s in _results) s.name.toLowerCase()};
    final fresh = more.where((s) => have.add(s.name.toLowerCase())).toList();
    setState(() {
      _results = [..._results, ...fresh];
      _hasMore = fresh.isNotEmpty;
    });
  }

  void _pick(String view) {
    setState(() => _view = view);
    if (view != 'fav' && view != 'recent') load();
  }

  Future<void> _country() async {
    final picked = await showSheet<RadioCountry>(context, scroll: false, maxHeight: .9, builder: (_) => const _CountryPicker());
    if (picked == null || !mounted) return;
    Settings.i.radioCountry = picked.code;
    Settings.i.radioCountryName = picked.name;
    load();
  }

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    final s = Settings.i;
    final dir = RadioDirectory.i;
    final code = s.radioCountry;
    final shown = _view == 'fav' ? dir.favorites : (_view == 'recent' ? dir.recents : _results);
    final local = _view == 'fav' || _view == 'recent';
    return SliverMainAxisGroup(slivers: [
      SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
          child: SearchBox(historyKey: 'radio', 
            controller: _q,
            textInputAction: TextInputAction.search,
            onSubmitted: (_) {
              if (local) setState(() => _view = 'all');
              load();
            },
            onChanged: (v) {
              setState(() {});
              if (v.isEmpty) load();
            },
            decoration: InputDecoration(
              hintText: code.isEmpty ? 'Search stations worldwide' : 'Search stations in ${s.radioCountryName}',
              prefixIcon: const Icon(Icons.search_sharp, size: 18),
              suffixIcon: _q.text.isEmpty
                  ? null
                  : IconButton(
                      icon: const Icon(Icons.close_sharp, size: 18),
                      onPressed: () {
                        _q.clear();
                        load();
                      },
                    ),
            ),
          ),
        ),
      ),
      SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
          child: Panel(
            onTap: _country,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
            child: Row(children: [
              if (countryFlag(code, s.radioCountryName).isEmpty) Icon(Icons.public_sharp, size: 19, color: t.accent) else Text(countryFlag(code, s.radioCountryName), style: const TextStyle(fontSize: 18)),
              const SizedBox(width: 10),
              Expanded(child: Text(code.isEmpty ? 'All countries' : s.radioCountryName, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600))),
              if (code.isNotEmpty)
                Tap(
                  behavior: HitTestBehavior.opaque,
                  onTap: () {
                    s.radioCountry = '';
                    s.radioCountryName = '';
                    load();
                  },
                  child: Padding(padding: const EdgeInsets.symmetric(horizontal: 6), child: Icon(Icons.close_sharp, size: 18, color: t.muted)),
                ),
              Icon(Icons.chevron_right_sharp, color: t.muted),
            ]),
          ),
        ),
      ),
      SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.only(top: 10),
          child: SizedBox(
            height: 36,
            child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 20), children: [
              for (final (id, name) in [('all', 'Top'), ('fav', '★ Favourites'), ('recent', 'Recent'), ...RadioDirectory.genres])
                Padding(padding: const EdgeInsets.only(right: 6), child: Tag(name, filled: _view == id, onTap: () => _pick(id))),
            ]),
          ),
        ),
      ),
      if (!local && !_loading && dir.usingFallback && shown.isNotEmpty)
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
            child: Text('Radio Browser is down, so this list is from TuneIn.', style: TextStyle(color: t.muted, fontSize: 12.5)),
          ),
        ),
      if (!local && _loading)
        const SliverToBoxAdapter(child: SkeletonRows(count: 8, art: 50, padding: EdgeInsets.symmetric(horizontal: 20)))
      else if (shown.isEmpty)
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.all(36),
            child: Column(children: [
              Text(
                _view == 'fav'
                    ? 'No favourite stations yet. Tap a heart to keep one here.'
                    : (_view == 'recent'
                        ? 'Stations you play show up here.'
                        : (dir.unreachable ? 'The radio directory isn’t answering right now. Its servers are sometimes down, so try again in a little while.' : 'No stations found. Try fewer words, another genre or another country.')),
                textAlign: TextAlign.center,
                style: TextStyle(color: t.muted, height: 1.4),
              ),
              if (!local && dir.unreachable) ...[const SizedBox(height: 12), ToolButton(Icons.refresh_sharp, label: 'Try again', size: 36, onTap: load)],
            ]),
          ),
        )
      else ...[
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(20, 6, 20, 0),
          sliver: SliverList.builder(itemCount: shown.length, itemBuilder: (_, i) => StationRow(station: shown[i])),
        ),
        if (!local && _hasMore)
          SliverToBoxAdapter(child: Padding(padding: const EdgeInsets.fromLTRB(20, 14, 20, 0), child: PrimaryButton('Load more', ghost: true, expand: true, onTap: _more))),
      ],
    ]);
  }
}

class _CountryPicker extends StatefulWidget {
  const _CountryPicker();

  @override
  State<_CountryPicker> createState() => _CountryPickerState();
}

class _CountryPickerState extends State<_CountryPicker> {
  late final Future<List<RadioCountry>> _all = RadioDirectory.i.countries();
  String _q = '';

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Choose a country', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
        const SizedBox(height: 10),
        SearchBox(historyKey: 'countries', onChanged: (v) => setState(() => _q = v.trim().toLowerCase()), decoration: const InputDecoration(hintText: 'Search countries', prefixIcon: Icon(Icons.search_sharp, size: 18))),
        const SizedBox(height: 6),
        Expanded(
          child: FutureBuilder<List<RadioCountry>>(
            future: _all,
            builder: (context, snap) {
              if (snap.connectionState != ConnectionState.done) return ListView(physics: const NeverScrollableScrollPhysics(), children: const [SkeletonRows(count: 12, art: null, lines: 1)]);
              final list = (snap.data ?? const <RadioCountry>[]).where((c) => _q.isEmpty || c.name.toLowerCase().contains(_q) || c.code.toLowerCase() == _q).toList();
              if (list.isEmpty) {
                return Center(child: Text(snap.data?.isEmpty ?? true ? 'The radio directory isn’t answering right now.' : 'No country by that name.', textAlign: TextAlign.center, style: TextStyle(color: t.muted)));
              }
              return ListView.builder(
                padding: const EdgeInsets.only(bottom: 24),
                itemCount: list.length,
                itemBuilder: (_, i) {
                  final c = list[i];
                  return Tap(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => Navigator.pop(context, c),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 11),
                      child: Row(children: [
                        SizedBox(width: 34, child: c.flag.isEmpty ? Icon(Icons.public_sharp, size: 20, color: t.muted) : Text(c.flag, style: const TextStyle(fontSize: 20))),
                        Expanded(child: Text(c.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w500))),
                        if (c.count > 0) Text('${c.count}', style: TextStyle(color: t.muted, fontSize: 12.5)),
                      ]),
                    ),
                  );
                },
              );
            },
          ),
        ),
      ]),
    );
  }
}

/// A station in a list: tap for details, heart and play right there.
class StationRow extends StatelessWidget {
  const StationRow({super.key, required this.station});
  final Station station;

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    final s = station;
    return Tap(
      behavior: HitTestBehavior.opaque,
      onTap: () => showStationMenu(context, s),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 9),
        decoration: BoxDecoration(border: Border(bottom: BorderSide(color: t.line))),
        child: Row(children: [
          SizedBox(width: 50, child: PodcastArt(s.favicon, title: s.name)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(s.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600)),
              if (s.subtitle.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 2), child: Text(s.subtitle, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: t.muted, fontSize: 12.5))),
            ]),
          ),
          const SizedBox(width: 6),
          // Only these follow the player and marks, not the whole list.
          ListenableBuilder(
            listenable: Listenable.merge([RadioDirectory.i, Player.i]),
            builder: (context, _) {
              final dir = RadioDirectory.i;
              final on = dir.isCurrent(s.id);
              return Row(mainAxisSize: MainAxisSize.min, children: [
                IconButton(
                  tooltip: 'Favourite',
                  onPressed: () {
                    haptic();
                    dir.toggleFavorite(s);
                  },
                  icon: Icon(dir.isFavorite(s.id) ? Icons.favorite_sharp : Icons.favorite_border_sharp, size: 20, color: dir.isFavorite(s.id) ? t.accent : t.muted),
                ),
                ToolButton(on && Player.i.playing ? Icons.pause_sharp : Icons.play_arrow_sharp, size: 40, active: on, tooltip: 'Play', onTap: () => dir.play(s)),
              ]);
            },
          ),
        ]),
      ),
    );
  }
}

/// A station tile for rows of favourites.
class StationTile extends StatelessWidget {
  const StationTile({super.key, required this.station, this.width = 96});
  final Station station;
  final double width;

  @override
  Widget build(BuildContext context) {
    return Tap(
      onTap: () => RadioDirectory.i.play(station),
      onLongPress: () {
        haptic(true);
        showStationMenu(context, station);
      },
      child: SizedBox(
        width: width,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          PodcastArt(station.favicon, title: station.name),
          const SizedBox(height: 6),
          Text(station.name, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, height: 1.15)),
        ]),
      ),
    );
  }
}

/// A station's details, with rating, favourite, notes, folders and sharing.
Future<void> showStationMenu(BuildContext context, Station s) {
  return showSheet(context, builder: (ctx) {
    final t = Tokens.of(ctx);
    return ListenableBuilder(
      listenable: Listenable.merge([RadioDirectory.i, Player.i, Library.i]),
      builder: (ctx, _) {
        final dir = RadioDirectory.i;
        final on = dir.isCurrent(s.id);
        final facts = [if (s.language.isNotEmpty) s.language, if (s.bitrate > 0) '${s.bitrate} kbps'].join(' · ');
        return Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              SizedBox(width: 68, child: ViewableImage(url: s.favicon, title: s.name, child: PodcastArt(s.favicon, title: s.name))),
              const SizedBox(width: 14),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(s.name, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700, height: 1.15)),
                  if (s.country.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 3), child: Text('${s.flag} ${s.country}'.trim(), style: TextStyle(color: t.muted, fontSize: 13.5))),
                  if (facts.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 2), child: Text(facts, style: TextStyle(color: t.muted, fontSize: 12.5))),
                ]),
              ),
            ]),
            if (s.tags.isNotEmpty) ...[
              const SizedBox(height: 12),
              Wrap(spacing: 6, runSpacing: 6, children: [for (final tag in s.tags.take(6)) Tag(tag)]),
            ],
            const SizedBox(height: 16),
            PrimaryButton(on && Player.i.playing ? 'Pause' : 'Listen live', icon: on && Player.i.playing ? Icons.pause_sharp : Icons.play_arrow_sharp, expand: true, onTap: () {
              // Starting one leaves this sheet for the full player.
              if (!on && Settings.i.openPlayerOnPlay) Navigator.pop(ctx);
              playStation(context, s);
            }),
            const SizedBox(height: 14),
            MarksBar(mark: dir.markOf(s.id), title: s.name, changed: () => dir.changed(s), folders: () => dir.foldersOf(s.id), onFolder: (id) => dir.toggleFolder(s, id)),
            const SizedBox(height: 14),
            Row(children: [
              Expanded(
                child: PrimaryButton('Share card', ghost: true, icon: Icons.ios_share_sharp, onTap: () {
                  Navigator.pop(ctx);
                  showMediaCard(context, ShareItem.station(s, dir.markOf(s.id)));
                }),
              ),
              if (s.homepage != null) ...[
                const SizedBox(width: 8),
                Expanded(child: PrimaryButton('Website', ghost: true, icon: Icons.open_in_new_sharp, onTap: () => launchUrlString(s.homepage!, mode: LaunchMode.externalApplication))),
              ],
            ]),
          ]),
        );
      },
    );
  });
}

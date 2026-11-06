import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:html/parser.dart' as html;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:xml/xml.dart';

import '../core/net_image.dart';
import '../core/settings.dart';
import '../models/audiobook.dart';
import '../models/podcast.dart';
import 'api_cache.dart';
import 'audio.dart';
import 'backup.dart';
import 'downloads.dart';
import 'storage.dart';

/// Podcast categories in Apple's directory: (name, genre id).
const podcastGenres = <(String, int)>[
  ('Technology', 1318),
  ('News', 1489),
  ('History', 1487),
  ('Science', 1533),
  ('Comedy', 1303),
  ('True Crime', 1488),
  ('Business', 1321),
  ('Society & Culture', 1324),
  ('Health & Fitness', 1512),
  ('Education', 1304),
  ('Arts', 1301),
  ('Fiction', 1483),
  ('Sports', 1545),
  ('TV & Film', 1309),
  ('Kids & Family', 1305),
  ('Music', 1310),
  ('Religion & Spirituality', 1314),
  ('Self-Improvement', 1500),
  ('Mental Health', 1517),
  ('Books', 1482),
  ('Philosophy', 1443),
  ('Documentary', 1543),
  ('Politics', 1527),
  ('Personal Journals', 1302),
  ('Entrepreneurship', 1493),
  ('Investing', 1412),
  ('Careers', 1410),
  ('Relationships', 1544),
  ('Parenting', 1521),
  ('Language Learning', 1498),
  ('Food', 1306),
  ('Places & Travel', 1320),
  ('Nature', 1537),
  ('Science Fiction', 1485),
  ('Stand-Up', 1497),
  ('Video Games', 1509),
  ('Leisure', 1502),
  ('Government', 1511),
];

const _ua = {'User-Agent': 'Alexandria-Reader/1.0 (podcast player)'};

String _plain(String s) => (html.parseFragment(s).text ?? '').replaceAll(RegExp(r'[ \t]+'), ' ').replaceAll(RegExp(r'\n\s*\n\s*'), '\n\n').trim();

/// [Podcasts.parseFeed] for a background isolate. Top-level on purpose: the
/// isolate must be handed a plain function, nothing tied to the Podcasts class.
Podcast? _parseFeedInIsolate((String, String) a) => Podcasts.parseFeed(a.$1, a.$2);

/// Subscriptions, listening history, the queue and downloaded episodes.
class Podcasts extends ChangeNotifier {
  Podcasts._();
  static final Podcasts i = Podcasts._();

  final List<Podcast> subscriptions = [];
  final Map<String, EpisodeState> states = {};
  final List<Episode> queue = [];

  /// Rating, favourite and notes per show, by feed address.
  final Map<String, UserMark> showMarks = {};

  /// Library folders each show is filed in, by feed address.
  final Map<String, List<String>> showFolders = {};

  /// Episode order each show was set to, by feed address ([EpisodeSort] names).
  /// Shows not in here follow the default in Settings.
  final Map<String, String> showSorts = {};

  /// Last speed used for podcasts, applied to the next episode.
  double speed = 1;

  /// Feeds loaded this session (subscribed or just browsed).
  final Map<String, Podcast> _feeds = {};

  bool refreshing = false;

  /// Set when a request could not connect, so screens can say so.
  bool unreachable = false;

  Future<void> load() async {
    final j = await Storage.readJson('podcasts');
    if (j is! Map) return;
    subscriptions.addAll(((j['subscriptions'] as List?) ?? const []).whereType<Map>().map((e) => Podcast.fromJson(Map<String, dynamic>.from(e))));
    for (final e in ((j['states'] as Map?) ?? const {}).entries) {
      if (e.value is Map) states['${e.key}'] = EpisodeState.fromJson(Map<String, dynamic>.from(e.value));
    }
    queue.addAll(((j['queue'] as List?) ?? const []).whereType<Map>().map((e) => Episode.fromJson(Map<String, dynamic>.from(e))));
    speed = ((j['speed'] ?? 1) as num).toDouble();
    for (final e in ((j['showMarks'] as Map?) ?? const {}).entries) {
      if (e.value is Map) showMarks['${e.key}'] = UserMark.fromJson(Map<String, dynamic>.from(e.value));
    }
    for (final e in ((j['showFolders'] as Map?) ?? const {}).entries) {
      if (e.value is List) showFolders['${e.key}'] = (e.value as List).cast<String>();
    }
    for (final e in ((j['showSorts'] as Map?) ?? const {}).entries) {
      if (e.value is String) showSorts['${e.key}'] = e.value as String;
    }
    for (final s in subscriptions) {
      _feeds[s.feedUrl] = s;
    }
    notifyListeners();
    syncBackgroundCheck();
  }

  Timer? _pending;

  Map<String, dynamic> toJson() => {
        'subscriptions': subscriptions.map((s) => s.toJson()).toList(),
        'states': {for (final e in states.entries) e.key: e.value.toJson()},
        'queue': queue.map((e) => e.toJson()).toList(),
        'speed': speed,
        'showMarks': {for (final e in showMarks.entries) if (!e.value.isEmpty) e.key: e.value.toJson()},
        'showFolders': {for (final e in showFolders.entries) if (e.value.isNotEmpty) e.key: e.value},
        'showSorts': showSorts,
      };

  void _persist() {
    _pending?.cancel();
    _pending = Timer(const Duration(milliseconds: 500), () {
      Storage.writeJson('podcasts', toJson());
      syncBackgroundCheck();
    });
    notifyListeners();
  }

  static const _channel = MethodChannel('alexandria/podcasts');

  /// Tells the background check which shows to look at and the newest episode
  /// known for each, and sets when it runs. It works without the app open.
  Future<void> syncBackgroundCheck() async {
    if (!Platform.isAndroid) return;
    try {
      final dir = await getApplicationSupportDirectory();
      final shows = [
        for (final x in subscriptions)
          {
            'feed': x.feedUrl,
            'title': x.title,
            'latestMs': x.episodes.fold<int>(0, (a, e) => math.max(a, e.published?.millisecondsSinceEpoch ?? 0)),
          }
      ];
      final f = File(p.join(dir.path, 'podcast_check.json'));
      final tmp = File('${f.path}.tmp');
      await tmp.writeAsString(jsonEncode({'shows': shows}), flush: true);
      await tmp.rename(f.path);
      final s = Settings.i;
      await _channel.invokeMethod('schedule', {'enabled': s.podcastAlerts && shows.isNotEmpty, 'hours': s.podcastCheckHours});
    } catch (e) {
      debugPrint('[podcasts] background check not set: $e');
    }
  }

  /// Runs the background check now. How many new episodes, or -1 if it failed.
  Future<int> checkNow() async {
    await syncBackgroundCheck();
    return await _channel.invokeMethod<int>('checkNow') ?? 0;
  }

  /// Merges a backup's podcasts. Listening state: the newer copy of each episode wins.
  void mergeBackup(dynamic j, ImportResult r) {
    if (j is! Map) return;
    for (final m in ((j['subscriptions'] as List?) ?? const []).whereType<Map>()) {
      final pod = Podcast.fromJson(Map<String, dynamic>.from(m));
      if (subscribed(pod.feedUrl)) continue;
      subscriptions.add(pod);
      _feeds[pod.feedUrl] = pod;
      r.shows++;
    }
    for (final e in ((j['states'] as Map?) ?? const {}).entries) {
      if (e.value is! Map) continue;
      final s = EpisodeState.fromJson(Map<String, dynamic>.from(e.value));
      if (s.localPath != null && !File(s.localPath!).existsSync()) s.localPath = null;
      final mine = states['${e.key}'];
      if (mine != null && !s.updatedAt.isAfter(mine.updatedAt)) continue;
      // Keep a download that exists here even if the backup's copy has none.
      if (mine?.localPath != null) s.localPath ??= mine!.localPath;
      if (mine == null) r.episodes++;
      states['${e.key}'] = s;
    }
    for (final m in ((j['queue'] as List?) ?? const []).whereType<Map>()) {
      final ep = Episode.fromJson(Map<String, dynamic>.from(m));
      if (!queued(ep)) queue.add(ep);
    }
    for (final e in ((j['showMarks'] as Map?) ?? const {}).entries) {
      if (e.value is Map && (showMarks['${e.key}']?.isEmpty ?? true)) showMarks['${e.key}'] = UserMark.fromJson(Map<String, dynamic>.from(e.value));
    }
    for (final e in ((j['showFolders'] as Map?) ?? const {}).entries) {
      if (e.value is List) showFolders['${e.key}'] = {...foldersOf('${e.key}'), ...(e.value as List).cast<String>()}.toList();
    }
    // A show's order set on this device wins over the backup's.
    for (final e in ((j['showSorts'] as Map?) ?? const {}).entries) {
      if (e.value is String) showSorts.putIfAbsent('${e.key}', () => e.value as String);
    }
    _persist();
  }

  Future<dynamic> _get(String url, {bool json = true, Duration ttl = const Duration(days: 1)}) async {
    final body = await ApiCache.get(url, ttl: ttl, headers: _ua, onUnreachable: () => unreachable = true);
    if (body == null || !json) return body;
    try {
      return jsonDecode(body);
    } catch (_) {
      return null;
    }
  }

  // ---------------- directory ----------------

  PodcastHit _hit(Map r) => PodcastHit(
        id: '${r['collectionId'] ?? r['id'] ?? ''}',
        title: '${r['collectionName'] ?? r['name'] ?? ''}',
        author: '${r['artistName'] ?? ''}',
        artwork: (r['artworkUrl600'] ?? r['artworkUrl100'])?.toString().replaceAll('100x100bb', '600x600bb'),
        feedUrl: r['feedUrl'] as String?,
        genre: '${r['primaryGenreName'] ?? ((r['genres'] as List?)?.whereType<Map>().firstOrNull?['name']) ?? ''}',
        episodes: (r['trackCount'] ?? 0) as int,
      );

  /// Apple's podcast directory: free, no key.
  Future<List<PodcastHit>> search(String term, {int? genre}) async {
    final q = Uri.encodeQueryComponent(term.trim().isEmpty ? 'podcast' : term.trim());
    final j = await _get('https://itunes.apple.com/search?media=podcast&entity=podcast&limit=40&term=$q${genre == null ? '' : '&genreId=$genre'}');
    final list = (j is Map ? j['results'] : null) as List? ?? const [];
    return [for (final r in list.whereType<Map>()) if (r['feedUrl'] != null) _hit(r)];
  }

  /// Today's top shows.
  Future<List<PodcastHit>> top() async {
    final j = await _get('https://rss.marketingtools.apple.com/api/v2/us/podcasts/top/50/podcasts.json');
    final feed = j is Map ? j['feed'] : null;
    final list = (feed is Map ? feed['results'] : null) as List? ?? const [];
    return [for (final r in list.whereType<Map>()) _hit(r)];
  }

  /// Chart entries come without a feed address; the lookup API has it.
  Future<String?> feedFor(PodcastHit h) async {
    if (h.feedUrl != null) return h.feedUrl;
    final j = await _get('https://itunes.apple.com/lookup?id=${h.id}&entity=podcast');
    final r = ((j is Map ? j['results'] : null) as List?)?.whereType<Map>().firstOrNull;
    return r?['feedUrl'] as String?;
  }

  // ---------------- feeds ----------------

  Podcast? cached(String feedUrl) => _feeds[feedUrl];

  /// Loads and parses an RSS feed. Subscribed shows keep their state and are re-saved.
  Future<Podcast?> feed(String url, {bool refresh = false}) {
    if (!refresh && _feeds[url] != null && _feeds[url]!.episodes.isNotEmpty && _feeds[url]!.subscribedAt == null) return Future.value(_feeds[url]);
    // The show page and the player can ask for the same feed at once: share one fetch.
    // The block body matters: `() => _loading.remove(url)` would return this very
    // future, and whenComplete waits on a returned future, so it would wait forever.
    return _loading[url] ??= _fetchFeed(url).whenComplete(() {
      _loading.remove(url);
    });
  }

  final _loading = <String, Future<Podcast?>>{};

  /// What each feed's last parsed body looked like (length and hash).
  final _parsedSig = <String, (int, int)>{};

  Future<Podcast?> _fetchFeed(String url) async {
    // New episodes are what feeds are for, so these go stale within the hour.
    final body = await _get(url, json: false, ttl: const Duration(hours: 1));
    if (body is! String) return _feeds[url];
    // Within the hour the body comes from the disk cache unchanged: don't parse
    // megabytes again for every subscription each time the tab opens.
    final sig = (body.length, body.hashCode);
    if (_parsedSig[url] == sig && (_feeds[url]?.episodes.isNotEmpty ?? false)) return _feeds[url];
    // A long-running show's feed is megabytes of XML and HTML; parsing that here
    // would freeze the screen, so big ones go to a background isolate.
    final parsed = body.length < 200000 ? parseFeed(url, body) : await compute(_parseFeedInIsolate, (url, body));
    if (parsed == null) return _feeds[url];
    _parsedSig[url] = sig;
    final sub = subscriptions.where((s) => s.feedUrl == url).firstOrNull;
    if (sub != null) {
      sub
        ..title = parsed.title
        ..author = parsed.author
        ..description = parsed.description
        ..imageUrl = parsed.imageUrl ?? sub.imageUrl
        ..categories = parsed.categories
        ..episodes = parsed.episodes
        ..updatedAt = DateTime.now();
      _persist();
      return sub;
    }
    return _feeds[url] = parsed;
  }


  /// RSS 2.0 with the iTunes extensions most feeds use.
  static Podcast? parseFeed(String url, String body) {
    final XmlDocument doc;
    try {
      doc = XmlDocument.parse(body);
    } catch (_) {
      return null;
    }
    final ch = doc.findAllElements('channel').firstOrNull;
    if (ch == null) return null;
    XmlElement? el(XmlElement e, String name) => e.childElements.where((c) => c.name.qualified == name).firstOrNull;
    String txt(XmlElement e, String name) => el(e, name)?.innerText.trim() ?? '';
    String? img(XmlElement e) => el(e, 'itunes:image')?.getAttribute('href') ?? el(e, 'image')?.childElements.where((c) => c.name.local == 'url').firstOrNull?.innerText.trim();

    final title = _plain(txt(ch, 'title'));
    final image = img(ch);
    final episodes = <Episode>[];
    for (final it in ch.childElements.where((c) => c.name.local == 'item')) {
      final enc = el(it, 'enclosure');
      final audio = enc?.getAttribute('url')?.trim() ?? '';
      if (audio.isEmpty) continue;
      final type = enc?.getAttribute('type') ?? '';
      if (type.startsWith('video/')) continue;
      final desc = txt(it, 'content:encoded').isNotEmpty ? txt(it, 'content:encoded') : (txt(it, 'description').isNotEmpty ? txt(it, 'description') : txt(it, 'itunes:summary'));
      final guid = txt(it, 'guid');
      episodes.add(Episode(
        guid: guid.isNotEmpty ? guid : audio,
        feedUrl: url,
        title: _plain(txt(it, 'title')),
        audioUrl: audio,
        description: _plain(desc),
        published: parseRssDate(txt(it, 'pubDate')),
        durationMs: parseDuration(txt(it, 'itunes:duration')) * 1000,
        imageUrl: img(it),
        link: txt(it, 'link').isEmpty ? null : txt(it, 'link'),
        podcastTitle: title,
        podcastImage: image,
      ));
    }
    episodes.sort((a, b) => (b.published ?? DateTime(1970)).compareTo(a.published ?? DateTime(1970)));
    return Podcast(
      feedUrl: url,
      title: title,
      author: _plain(txt(ch, 'itunes:author').isNotEmpty ? txt(ch, 'itunes:author') : txt(ch, 'managingEditor')),
      description: _plain(txt(ch, 'description').isNotEmpty ? txt(ch, 'description') : txt(ch, 'itunes:summary')),
      imageUrl: image,
      link: txt(ch, 'link').isEmpty ? null : txt(ch, 'link'),
      categories: ch.childElements.where((c) => c.name.qualified == 'itunes:category').map((c) => c.getAttribute('text') ?? '').where((s) => s.isNotEmpty).toSet().toList(),
      episodes: episodes,
      updatedAt: DateTime.now(),
    );
  }

  /// "Tue, 05 Nov 2024 09:30:00 +0000" (and the GMT / EST variants).
  static DateTime? parseRssDate(String s) {
    final m = RegExp(r'(\d{1,2})\s+([A-Za-z]{3})[a-z]*\s+(\d{4})\s+(\d{1,2}):(\d{2})(?::(\d{2}))?\s*([+-]\d{4}|[A-Z]{1,4})?').firstMatch(s);
    if (m == null) return DateTime.tryParse(s.trim());
    const months = ['jan', 'feb', 'mar', 'apr', 'may', 'jun', 'jul', 'aug', 'sep', 'oct', 'nov', 'dec'];
    final mon = months.indexOf(m[2]!.toLowerCase()) + 1;
    if (mon == 0) return null;
    var d = DateTime.utc(int.parse(m[3]!), mon, int.parse(m[1]!), int.parse(m[4]!), int.parse(m[5]!), int.tryParse(m[6] ?? '') ?? 0);
    final z = m[7] ?? '';
    const zones = {'EST': -5, 'EDT': -4, 'CST': -6, 'CDT': -5, 'MST': -7, 'MDT': -6, 'PST': -8, 'PDT': -7};
    if (z.startsWith('+') || z.startsWith('-')) {
      final sign = z.startsWith('-') ? -1 : 1;
      d = d.subtract(Duration(hours: sign * int.parse(z.substring(1, 3)), minutes: sign * int.parse(z.substring(3, 5))));
    } else if (zones[z] != null) {
      d = d.subtract(Duration(hours: zones[z]!));
    }
    return d;
  }

  /// "1:02:03", "62:03" or "3723" → seconds.
  static int parseDuration(String s) {
    s = s.trim();
    if (s.isEmpty) return 0;
    if (s.contains(':')) return s.split(':').map((x) => int.tryParse(x.trim()) ?? 0).fold(0, (a, x) => a * 60 + x);
    return double.tryParse(s)?.round() ?? 0;
  }

  // ---------------- subscriptions ----------------

  bool subscribed(String feedUrl) => subscriptions.any((s) => s.feedUrl == feedUrl);

  void subscribe(Podcast pod) {
    if (subscribed(pod.feedUrl)) return;
    pod.subscribedAt = DateTime.now();
    subscriptions.insert(0, pod);
    _feeds[pod.feedUrl] = pod;
    _persist();
  }

  void unsubscribe(String feedUrl) {
    subscriptions.removeWhere((s) => s.feedUrl == feedUrl);
    _feeds[feedUrl]?.subscribedAt = null;
    _persist();
  }

  /// Adds a show by its RSS address. Returns it, or null if the address is not a podcast feed.
  Future<Podcast?> addByUrl(String url) async {
    final u = url.trim();
    if (!u.startsWith('http')) return null;
    final pod = await ApiCache.fresh(() => feed(u, refresh: true));
    if (pod == null || pod.episodes.isEmpty) return null;
    subscribe(pod);
    return pod;
  }

  /// Re-reads every subscribed feed.
  Future<void> refreshAll() async {
    if (refreshing || subscriptions.isEmpty) return;
    refreshing = true;
    unreachable = false;
    notifyListeners();
    try {
      final subs = [...subscriptions];
      for (var n = 0; n < subs.length; n += 4) {
        await Future.wait(subs.skip(n).take(4).map((s) => feed(s.feedUrl, refresh: true)));
      }
    } finally {
      refreshing = false;
      notifyListeners();
    }
  }

  /// Newest unplayed episodes across subscriptions.
  List<Episode> get latest {
    final all = [for (final s in subscriptions) ...s.episodes.take(10)].where((e) => !(states[e.guid]?.played ?? false)).toList()
      ..sort((a, b) => (b.published ?? DateTime(1970)).compareTo(a.published ?? DateTime(1970)));
    return all.take(30).toList();
  }

  /// Started but not finished, most recent first.
  List<EpisodeState> get inProgress => states.values.where((s) => s.posMs > 15000 && !s.played).toList()..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));

  List<EpisodeState> get downloaded => states.values.where((s) => s.localPath != null).toList()..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));

  // ---------------- episode state ----------------

  EpisodeState _state(Episode e) => states[e.guid] ??= EpisodeState(episode: e);

  double progressOf(Episode e) {
    final s = states[e.guid];
    if (s == null) return 0;
    if (s.played) return 1;
    return e.durationMs > 0 ? (s.posMs / e.durationMs).clamp(0.0, 1.0) : 0;
  }

  bool played(Episode e) => states[e.guid]?.played ?? false;

  void setPlayed(Episode e, bool v) {
    final s = _state(e)
      ..played = v
      ..posMs = 0
      ..updatedAt = DateTime.now();
    if (v) queue.removeWhere((q) => q.guid == e.guid);
    states[e.guid] = s;
    _persist();
  }

  /// 'played', 'started' (listened to but not finished) or 'unplayed'.
  String stage(Episode e) {
    final s = states[e.guid];
    if (s == null) return 'unplayed';
    if (s.played) return 'played';
    return s.posMs > 15000 ? 'started' : 'unplayed';
  }

  UserMark showMark(String feedUrl) => showMarks[feedUrl] ??= UserMark();

  UserMark episodeMark(Episode e) => _state(e).mark;

  /// Call after changing a [UserMark] in place.
  void marksChanged() => _persist();

  List<String> foldersOf(String feedUrl) => showFolders[feedUrl] ?? const [];

  /// The order a show's episodes are listed in: its own, else the default.
  EpisodeSort sortOf(String feedUrl) => EpisodeSort.parse(showSorts[feedUrl] ?? Settings.i.episodeSort);

  /// Whether the show has an order of its own (rather than following the default).
  bool hasOwnSort(String feedUrl) => showSorts.containsKey(feedUrl);

  /// Remembers [sort] for this show; null goes back to following the default.
  void setSort(String feedUrl, EpisodeSort? sort) {
    sort == null ? showSorts.remove(feedUrl) : showSorts[feedUrl] = sort.name;
    _persist();
  }

  /// Every show goes back to the default order (the setting's "apply to all").
  void clearSorts() {
    if (showSorts.isEmpty) return;
    showSorts.clear();
    _persist();
  }

  void toggleFolder(String feedUrl, String folderId) {
    final cur = foldersOf(feedUrl);
    showFolders[feedUrl] = cur.contains(folderId) ? ([...cur]..remove(folderId)) : [...cur, folderId];
    _persist();
  }

  /// A folder was deleted: no show is in it any more.
  void removeFolder(String folderId) {
    for (final k in showFolders.keys.toList()) {
      showFolders[k] = [...showFolders[k]!]..remove(folderId);
    }
    _persist();
  }

  /// Marks everything older than [e] in its show as played.
  void markOlderPlayed(Podcast pod, Episode e) {
    final i = pod.episodes.indexWhere((x) => x.guid == e.guid);
    for (final x in pod.episodes.skip(i + 1)) {
      _state(x).played = true;
    }
    _persist();
  }

  // ---------------- playback ----------------

  /// The one-track book the player plays for [e].
  Audiobook asBook(Episode e) {
    final s = states[e.guid];
    final local = s?.localPath != null && File(s!.localPath!).existsSync() ? s.localPath : null;
    return Audiobook(
      id: 'ep:${sha1.convert(utf8.encode(e.guid))}',
      title: e.title,
      author: e.podcastTitle,
      description: e.description,
      coverUrl: e.art,
      source: 'podcast',
      sourceKey: e.guid,
      tracks: [AudioTrack(title: e.title, path: local ?? e.audioUrl, ms: e.durationMs)],
      positionMs: s == null || s.played ? 0 : s.posMs,
      speed: speed,
    );
  }

  Episode? episodeFor(Audiobook b) => states[b.sourceKey]?.episode;

  bool isPlaying(Episode e) => Player.i.book?.sourceKey == e.guid && Player.i.playing;

  bool isCurrent(Episode e) => Player.i.book?.sourceKey == e.guid;

  Future<void> play(Episode e) async {
    if (isCurrent(e)) return Player.i.toggle();
    final s = _state(e);
    if (s.played) s.played = false;
    queue.removeWhere((q) => q.guid == e.guid);
    _persist();
    await Player.i.open(asBook(e));
  }

  /// Loads a show's episodes if they aren't here yet (after a restart, for a
  /// show you aren't subscribed to), so the player can move between them.
  Future<void> ensureFeed(String feedUrl) async {
    if (_feeds[feedUrl]?.episodes.isNotEmpty ?? false) return;
    await feed(feedUrl);
    notifyListeners();
  }

  /// The episode a swipe in the player switches to from [e]. Forward (1): the
  /// queue's next, else the show's next newer episode. Back (-1): the show's
  /// next older one. Null when there's none.
  Episode? neighbour(Episode e, int dir) {
    if (dir > 0 && queue.isNotEmpty) return queue.first;
    final eps = _feeds[e.feedUrl]?.episodes ?? const <Episode>[];
    final i = eps.indexWhere((x) => x.guid == e.guid);
    if (i < 0) return null;
    // Newest first, so newer is up the list.
    final j = dir > 0 ? i - 1 : i + 1;
    return j >= 0 && j < eps.length ? eps[j] : null;
  }

  /// Called by the player as it saves.
  void savePosition(Audiobook b) {
    final s = states[b.sourceKey];
    if (s == null) return;
    s
      ..posMs = b.positionMs
      ..updatedAt = DateTime.now();
    // Most shows end in an outro: this close to the end counts as heard.
    final dur = b.tracks.isEmpty ? 0 : b.tracks.first.ms;
    if (dur > 60000 && b.positionMs >= dur - 30000) s.played = true;
    speed = b.speed;
    _persist();
  }

  /// Called by the player at the end of an episode: mark it, then play the queue.
  void finished(Audiobook b) {
    final s = states[b.sourceKey];
    if (s != null) {
      s
        ..played = true
        ..posMs = 0
        ..updatedAt = DateTime.now();
    }
    _persist();
    if (queue.isNotEmpty) play(queue.first);
  }

  // ---------------- queue ----------------

  bool queued(Episode e) => queue.any((q) => q.guid == e.guid);

  void enqueue(Episode e, {bool next = false}) {
    queue.removeWhere((q) => q.guid == e.guid);
    next ? queue.insert(0, e) : queue.add(e);
    _state(e);
    _persist();
  }

  void dequeue(Episode e) {
    queue.removeWhere((q) => q.guid == e.guid);
    _persist();
  }

  void reorderQueue(int from, int to) {
    queue.insert(to, queue.removeAt(from));
    _persist();
  }

  void clearQueue() {
    queue.clear();
    _persist();
  }

  // ---------------- downloads ----------------

  // Remembered once seen: the show page asks this for every episode on each
  // rebuild. Removing a download clears localPath, so a yes stays true.
  bool isDownloaded(Episode e) => fileExists(states[e.guid]?.localPath);

  Future<bool> download(Episode e) async {
    if (Downloads.i.running(e.guid) || isDownloaded(e)) return true;
    final ext = RegExp(r'\.(mp3|m4a|aac|ogg|opus|wav)(\?|$)', caseSensitive: false).firstMatch(e.audioUrl)?.group(1) ?? 'mp3';
    final dest = p.join(Storage.root.path, 'podcasts', '${sha1.convert(utf8.encode(e.guid))}.$ext');
    // Keep the artwork with it, for the lists and the notification when offline.
    if (e.art != null) NetImageCache.get(e.art!).ignore();
    final job = 'ep:${e.guid}';
    _state(e);
    Downloads.i.remember(job);
    final ok = await Downloads.i.fetch(e.guid, e.audioUrl, dest, label: e.title);
    if (ok) {
      _state(e).localPath = dest;
    }
    _persist();
    Downloads.i.settle(job, e.guid, ok);
    return ok;
  }

  /// The [Downloads] key of a show's "download all".
  static String batchKey(String feedUrl) => 'show:$feedUrl';

  /// Episodes in [eps] not saved yet.
  List<Episode> notDownloaded(Iterable<Episode> eps) => eps.where((e) => !isDownloaded(e)).toList();

  /// Saves [eps] one after another (newest first, as given), with overall
  /// progress under [batchKey]. Cancelling that stops the episode in flight too.
  /// False if it stopped early.
  Future<bool> downloadAll(Podcast pod, List<Episode> eps) async {
    final key = batchKey(pod.feedUrl);
    final todo = notDownloaded(eps);
    if (todo.isEmpty || Downloads.i.running(key)) return true;
    Downloads.i.report(key, 0, label: '${pod.title}: ${todo.length} episodes');
    var done = 0;
    var failed = 0;
    try {
      for (final e in todo) {
        if (Downloads.i.cancelled(key)) return false;
        Downloads.i.joinBatch(e.guid, key);
        try {
          if (!await download(e)) failed++;
        } finally {
          Downloads.i.leaveBatch(e.guid);
        }
        done++;
        if (!Downloads.i.cancelled(key)) Downloads.i.report(key, done / todo.length);
      }
      return failed == 0;
    } finally {
      Downloads.i.report(key, null);
    }
  }

  Future<void> removeDownload(Episode e) async {
    final s = states[e.guid];
    final path = s?.localPath;
    if (s == null || path == null) return;
    s.localPath = null;
    _persist();
    final f = File(path);
    if (await f.exists()) await f.delete();
  }
}

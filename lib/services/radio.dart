import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../models/audiobook.dart';
import '../models/radio.dart';
import 'api_cache.dart';
import 'audio.dart';
import 'storage.dart';

/// Live stations from Radio Browser (https://www.radio-browser.info), a free
/// community directory, with TuneIn's public directory as the fallback when
/// Radio Browser is down, which does happen. Neither needs a key.
class RadioDirectory extends ChangeNotifier {
  RadioDirectory._();
  static final RadioDirectory i = RadioDirectory._();

  static const servers = ['de1', 'de2', 'fi1'];
  static const pageSize = 60;

  static const genres = [
    ('news', 'News'), ('talk', 'Talk'), ('pop', 'Pop'), ('rock', 'Rock'), ('jazz', 'Jazz'), ('classical', 'Classical'), //
    ('hiphop', 'Hip hop'), ('afrobeats', 'Afrobeats'), ('rnb', 'R&B'), ('reggae', 'Reggae'), ('dance', 'Dance'), ('ambient', 'Ambient'),
    ('lofi', 'Lo-fi'), ('gospel', 'Gospel'), ('sports', 'Sports'), ('country', 'Country'), ('latin', 'Latin'), ('80s', '80s'), ('90s', '90s'),
  ];

  /// Stations worth keeping: favourited, rated, noted, filed or recently played.
  final Map<String, Station> stations = {};
  final Map<String, UserMark> marks = {};
  final Map<String, List<String>> folders = {};
  final List<String> recent = [];

  /// Every source failed and nothing was saved, so "no stations" isn't the truth.
  bool unreachable = false;

  /// The last list came from the fallback directory.
  bool usingFallback = false;

  /// Radio Browser failed recently: don't make every list wait on it again.
  DateTime? _downUntil;

  @visibleForTesting
  void resetServers() {
    _downUntil = null;
    _server = 0;
    usingFallback = false;
  }

  /// Stations seen in lists, so a mark or a play can find the record again.
  final Map<String, Station> _seen = {};

  Future<void> load() async {
    final j = await Storage.readJson('radio');
    if (j is Map) mergeBackup(j, save: false);
    notifyListeners();
  }

  Map<String, dynamic> toJson() => {
        'stations': {for (final e in stations.entries) e.key: e.value.toJson()},
        'marks': {for (final e in marks.entries) if (!e.value.isEmpty) e.key: e.value.toJson()},
        'folders': {for (final e in folders.entries) if (e.value.isNotEmpty) e.key: e.value},
        'recent': recent,
      };

  /// Adds a backup's stations. Marks and folders here are kept where both exist.
  void mergeBackup(dynamic j, {bool save = true}) {
    if (j is! Map) return;
    for (final e in ((j['stations'] as Map?) ?? const {}).entries) {
      if (e.value is Map) stations.putIfAbsent('${e.key}', () => Station.fromJson(Map<String, dynamic>.from(e.value)));
    }
    for (final e in ((j['marks'] as Map?) ?? const {}).entries) {
      if (e.value is Map && (marks['${e.key}']?.isEmpty ?? true)) marks['${e.key}'] = UserMark.fromJson(Map<String, dynamic>.from(e.value));
    }
    for (final e in ((j['folders'] as Map?) ?? const {}).entries) {
      if (e.value is List) folders['${e.key}'] = {...?folders['${e.key}'], ...(e.value as List).cast<String>()}.toList();
    }
    for (final id in ((j['recent'] as List?) ?? const []).cast<String>()) {
      if (!recent.contains(id)) recent.add(id);
    }
    if (save) _persist();
  }

  Timer? _pending;

  void _persist() {
    _pending?.cancel();
    _pending = Timer(const Duration(milliseconds: 500), () => Storage.writeJson('radio', toJson()));
    notifyListeners();
  }

  // ---------------- the directory ----------------

  int _server = 0;

  /// Asks each server in turn, or null if none answered. The cache is shared
  /// between them, since they mirror the same data, so results saved from one
  /// still show if it goes down.
  Future<List<dynamic>?> _get(String pathAndQuery, Duration ttl) async {
    final down = _downUntil;
    if (down != null && DateTime.now().isBefore(down)) return null;
    for (var n = 0; n < servers.length; n++) {
      final at = (_server + n) % servers.length;
      var noAnswer = false;
      final body = await ApiCache.get(
        'https://${servers[at]}.api.radio-browser.info$pathAndQuery',
        cacheKey: 'radio-browser$pathAndQuery',
        ttl: ttl,
        attempts: 1,
        timeout: const Duration(seconds: 6),
        headers: const {'User-Agent': 'Alexandria-Reader/1.0'},
        onUnreachable: () => noAnswer = true,
      );
      if (noAnswer) continue;
      _server = at;
      if (body == null) return const [];
      try {
        final j = jsonDecode(body);
        return j is List ? j : const [];
      } catch (_) {
        continue;
      }
    }
    _downUntil = DateTime.now().add(const Duration(minutes: 5));
    return null;
  }

  /// Stations, most popular first, optionally narrowed by name, country and genre.
  Future<List<Station>> browse({String? name, String? country, String? tag, String? countryName, int offset = 0}) async {
    // A country picked from the fallback's own list can only be browsed there.
    if (!(country ?? '').startsWith('ti:')) {
      final q = <String, String>{
        'hidebroken': 'true',
        'is_https': 'true',
        'order': 'clickcount',
        'reverse': 'true',
        'limit': '$pageSize',
        'offset': '$offset',
        if (name != null && name.trim().isNotEmpty) 'name': name.trim(),
        if (country != null && country.isNotEmpty) 'countrycode': country,
        if (tag != null && tag.isNotEmpty) ...{'tag': tag, 'tagExact': 'true'},
      };
      final list = await _get(Uri(path: '/json/stations/search', queryParameters: q).toString(), const Duration(days: 1));
      if (list != null) {
        usingFallback = false;
        return _remember(list.whereType<Map>().map(Station.fromDirectory));
      }
    }
    usingFallback = true;
    // The fallback has one page per list.
    return offset > 0 ? const [] : _tuneIn(name: name, country: country, countryName: countryName, tag: tag);
  }

  List<Station> _remember(Iterable<Station?> stations) {
    final seen = <String>{};
    final out = <Station>[];
    for (final s in stations) {
      // Directories list many stations several times under one name.
      if (s == null || !seen.add(s.name.toLowerCase())) continue;
      _seen[s.id] = s;
      out.add(s);
    }
    return out;
  }

  // ---------------- TuneIn ----------------

  static const _tuneInBase = 'https://opml.radiotime.com';

  /// The continents TuneIn files countries under.
  static const _continents = ['r101215', 'r101216', 'r100297', 'r101320', 'r101217', 'r101218', 'r101219'];

  Future<Map?> _tuneInGet(String pathAndQuery, Duration ttl) async {
    var noAnswer = false;
    final body = await ApiCache.get('$_tuneInBase$pathAndQuery${pathAndQuery.contains('?') ? '&' : '?'}render=json', ttl: ttl, headers: const {'User-Agent': 'Alexandria-Reader/1.0'}, timeout: const Duration(seconds: 12), attempts: 1, onUnreachable: () => noAnswer = true);
    if (noAnswer) unreachable = true;
    if (body == null) return null;
    try {
      final j = jsonDecode(body);
      return j is Map ? j : null;
    } catch (_) {
      return null;
    }
  }

  /// Every outline in a response, however deeply nested.
  static Iterable<Map> _outlines(dynamic list) sync* {
    for (final m in (list is List ? list : const []).whereType<Map>()) {
      yield m;
      yield* _outlines(m['children']);
    }
  }

  Future<List<Station>> _tuneIn({String? name, String? country, String? countryName, String? tag}) async {
    final query = (name ?? '').trim();
    final words = (tag ?? '').trim();
    String? region = (country ?? '').startsWith('ti:') ? country!.substring(3) : null;
    if (region == null && (country ?? '').isNotEmpty && (countryName ?? '').isNotEmpty) {
      // A Radio Browser country: find the same one by name.
      final want = countryName!.toLowerCase();
      for (final c in await _tuneInCountries()) {
        if (c.name.toLowerCase() == want) region = c.code.substring(3);
      }
    }

    final Map? j;
    if (region != null) {
      j = await _tuneInGet('/Browse.ashx?id=$region&formats=mp3,aac', const Duration(days: 1));
    } else if (query.isNotEmpty || words.isNotEmpty || (countryName ?? '').isNotEmpty) {
      final q = [query, words, countryName ?? ''].where((x) => x.isNotEmpty).join(' ');
      j = await _tuneInGet('/Search.ashx?query=${Uri.encodeQueryComponent(q)}&types=station&formats=mp3,aac', const Duration(days: 1));
    } else {
      j = await _tuneInGet('/Browse.ashx?c=trending&formats=mp3,aac', const Duration(hours: 6));
    }
    var list = _remember(_outlines(j?['body']).map(Station.fromTuneIn));
    if (region != null) {
      // A country's list can't be searched on the server, so narrow it here.
      for (final w in [query, words]) {
        if (w.isEmpty) continue;
        final lower = w.toLowerCase();
        list = list.where((s) => s.name.toLowerCase().contains(lower) || s.tags.any((t) => t.toLowerCase().contains(lower))).toList();
      }
    }
    return list;
  }

  Future<List<RadioCountry>> _tuneInCountries() async {
    final parts = await Future.wait(_continents.map((c) => _tuneInGet('/Browse.ashx?id=$c', const Duration(days: 30))));
    final seen = <String>{};
    final out = [
      for (final j in parts)
        for (final m in _outlines(j?['body']))
          if ('${m['guide_id'] ?? ''}'.startsWith('r') && seen.add('${m['guide_id']}')) RadioCountry('ti:${m['guide_id']}', '${m['text'] ?? ''}'.trim(), 0),
    ]..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return out;
  }

  /// The address to actually play. TuneIn hands out several; https is the one
  /// phones allow, and a direct stream beats a playlist file.
  Future<String?> _resolve(Station s) async {
    if (!s.needsResolving) return s.url;
    final body = await ApiCache.get(s.url, ttl: const Duration(days: 1), headers: const {'User-Agent': 'Alexandria-Reader/1.0'}, timeout: const Duration(seconds: 12));
    if (body == null) return null;
    try {
      return pickStream(jsonDecode(body));
    } catch (_) {
      return null;
    }
  }

  @visibleForTesting
  static String? pickStream(dynamic j) {
    final options = (j is Map && j['body'] is List ? j['body'] as List : const []).whereType<Map>().where((e) => '${e['url'] ?? ''}'.startsWith('https://')).toList();
    if (options.isEmpty) return null;
    final direct = options.where((e) => e['is_direct'] != false);
    return '${(direct.isNotEmpty ? direct.first : options.first)['url']}';
  }

  Future<List<RadioCountry>> countries() async {
    final list = await _get('/json/countries?hidebroken=true', const Duration(days: 7));
    if (list == null) return _tuneInCountries();
    final out = [
      for (final m in list.whereType<Map>())
        if ('${m['iso_3166_1'] ?? ''}'.length == 2 && (m['stationcount'] is int ? m['stationcount'] as int : 0) > 0) RadioCountry('${m['iso_3166_1']}'.toUpperCase(), '${m['name'] ?? ''}'.trim(), m['stationcount'] as int),
    ]..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return out;
  }

  // ---------------- yours ----------------

  Station? stationFor(String id) => stations[id] ?? _seen[id];

  UserMark markOf(String id) => marks[id] ??= UserMark();

  bool isFavorite(String id) => marks[id]?.favorite ?? false;

  List<String> foldersOf(String id) => folders[id] ?? const [];

  /// Call after a mark changed: a marked station is kept for good.
  void changed(Station s) {
    stations[s.id] = s;
    _persist();
  }

  void toggleFavorite(Station s) {
    final m = markOf(s.id);
    m.favorite = !m.favorite;
    changed(s);
  }

  void toggleFolder(Station s, String folderId) {
    final cur = foldersOf(s.id);
    folders[s.id] = cur.contains(folderId) ? ([...cur]..remove(folderId)) : [...cur, folderId];
    changed(s);
  }

  void removeFolder(String folderId) {
    for (final k in folders.keys.toList()) {
      folders[k] = [...folders[k]!]..remove(folderId);
    }
    _persist();
  }

  List<Station> get favorites => [for (final e in marks.entries) if (e.value.favorite && stations[e.key] != null) stations[e.key]!]..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

  List<Station> get recents => [for (final id in recent) if (stations[id] != null) stations[id]!];

  /// Every station filed in a folder, favourited or played.
  List<Station> get kept => stations.values.toList();

  // ---------------- playing ----------------

  bool isCurrent(String id) => Player.i.book?.source == 'radio' && Player.i.book?.sourceKey == id;

  /// The one-track "book" the shared player plays. Live, so it has no length.
  Audiobook asBook(Station s) => Audiobook(
        id: 'radio:${s.id}',
        title: s.name,
        author: s.subtitle,
        coverUrl: s.favicon,
        source: 'radio',
        sourceKey: s.id,
        tracks: [AudioTrack(title: s.name, path: s.url)],
      );

  Future<void> play(Station s) async {
    if (isCurrent(s.id)) return Player.i.toggle();
    stations[s.id] = s;
    recent
      ..remove(s.id)
      ..insert(0, s.id);
    if (recent.length > 30) recent.removeLast();
    _persist();
    if (!s.needsResolving) _countClick(s.id);
    final book = asBook(s);
    final stream = await _resolve(s);
    if (stream == null) return Player.i.fail(book, 'This station has no secure stream to play.');
    book.tracks.first.path = stream;
    await Player.i.open(book);
  }

  /// Tells the directory a station was played, which feeds its popularity ranking.
  void _countClick(String id) {
    http.get(Uri.parse('https://${servers[_server]}.api.radio-browser.info/json/url/$id'), headers: const {'User-Agent': 'Alexandria-Reader/1.0'}).timeout(const Duration(seconds: 8)).then((_) {}, onError: (_) {});
  }
}

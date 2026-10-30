import 'dart:convert';

import 'package:html/parser.dart' as html;

import '../models/audiobook.dart';
import 'api_cache.dart';

/// A free audiobook from a public catalogue, before it is on the shelf.
class FreeAudiobook {
  FreeAudiobook({
    required this.source,
    required this.key,
    required this.title,
    this.author = '',
    this.description = '',
    this.language = '',
    this.year = '',
    this.coverUrl,
    this.seconds = 0,
    this.sections = 0,
  });

  /// 'librivox' or 'archive'.
  final String source;

  /// LibriVox id, or Internet Archive identifier.
  final String key;
  final String title;
  final String author;
  final String description;
  final String language;
  final String year;
  final String? coverUrl;
  final int seconds;
  final int sections;

  String get sourceName => source == 'librivox' ? 'LibriVox' : 'Internet Archive';
}

const _ua = {'User-Agent': 'Alexandria-Reader/1.0 (personal audiobook player)'};

/// Gets JSON, trying twice: these catalogues are slow and drop connections now and then.
/// A request that never gets an answer sets [FreeAudio.unreachable].
Future<dynamic> _json(String url) async {
  final body = await ApiCache.get(url, ttl: const Duration(days: 7), headers: _ua, onUnreachable: () => FreeAudio.unreachable = true);
  if (body == null) return null;
  try {
    return jsonDecode(body);
  } catch (_) {
    return null;
  }
}

String _plain(String s) => (html.parseFragment(s).text ?? '').replaceAll(RegExp(r'\s+'), ' ').trim();

int _secs(dynamic v) {
  final s = '${v ?? ''}'.trim();
  if (s.isEmpty) return 0;
  if (s.contains(':')) {
    // "hh:mm:ss" or "mm:ss"
    return s.split(':').map((x) => double.tryParse(x) ?? 0).fold(0.0, (a, x) => a * 60 + x).round();
  }
  return (double.tryParse(s) ?? 0).round();
}

String? _archiveId(String? url) {
  if (url == null || url.isEmpty) return null;
  final seg = Uri.tryParse(url)?.pathSegments.where((s) => s.isNotEmpty).toList() ?? const [];
  return seg.length >= 2 && seg[seg.length - 2] == 'details' ? seg.last : null;
}

class FreeAudio {
  /// Set when a request failed to connect; screens reset it before searching
  /// so they can tell "nothing found" from "couldn't reach the catalogue".
  static bool unreachable = false;

  // ---------------- LibriVox ----------------

  static const _lvFields = '{id,title,authors,description,totaltimesecs,num_sections,language,url_iarchive,copyright_year}';

  static FreeAudiobook _lvBook(Map b) {
    final authors = ((b['authors'] as List?) ?? const []).whereType<Map>().map((a) => '${a['first_name'] ?? ''} ${a['last_name'] ?? ''}'.trim()).where((s) => s.isNotEmpty);
    final ia = _archiveId(b['url_iarchive'] as String?);
    return FreeAudiobook(
      source: 'librivox',
      key: '${b['id']}',
      title: _plain('${b['title'] ?? ''}'),
      author: authors.join(', '),
      description: _plain('${b['description'] ?? ''}'),
      language: '${b['language'] ?? ''}',
      year: '${b['copyright_year'] ?? ''}'.replaceAll(RegExp(r'[^0-9]'), ''),
      coverUrl: ia == null ? null : 'https://archive.org/services/img/$ia',
      seconds: _secs(b['totaltimesecs']),
      sections: int.tryParse('${b['num_sections'] ?? ''}') ?? 0,
    );
  }

  /// Searches LibriVox by title and by author. An empty query lists recent releases.
  ///
  /// LibriVox only matches whole titles or title starts ("^…"), so the search
  /// also tries "The …" and fills in from the Internet Archive's LibriVox
  /// collection, which matches words anywhere in a title.
  static Future<List<FreeAudiobook>> librivox(String query) async {
    const base = 'https://librivox.org/api/feed/audiobooks/?format=json&fields=$_lvFields';
    final q = query.trim();
    String enc(String s) => Uri.encodeQueryComponent(s);
    final urls = q.isEmpty
        ? ['$base&limit=30&offset=${DateTime.now().day * 7}']
        : [
            '$base&limit=20&title=${enc('^$q')}',
            if (!q.toLowerCase().startsWith('the ')) '$base&limit=10&title=${enc('^the $q')}',
            '$base&limit=15&author=${enc(q.split(' ').last)}',
          ];
    final apiF = Future.wait(urls.map(_json));
    final iaF = q.isEmpty ? Future.value(<FreeAudiobook>[]) : archive(q, collection: 'librivoxaudio');
    final api = await apiF;
    final ia = await iaF;
    final seen = <String>{};
    final out = <FreeAudiobook>[
      for (final j in api)
        for (final b in ((j is Map ? j['books'] : null) as List? ?? const []).whereType<Map>())
          if (seen.add('${b['id']}')) _lvBook(b),
    ];
    // Archive copies of LibriVox books not already found through the API.
    final titles = out.map((b) => b.title.toLowerCase()).toSet();
    out.addAll(ia.where((b) => !titles.contains(b.title.toLowerCase())));
    return out;
  }

  /// A LibriVox book's chapters, streamed from the Internet Archive.
  static Future<List<AudioTrack>> librivoxTracks(String id) async {
    final j = await _json('https://librivox.org/api/feed/audiobooks/?format=json&extended=1&id=$id');
    final b = ((j is Map ? j['books'] : null) as List?)?.whereType<Map>().firstOrNull;
    final sections = ((b?['sections'] as List?) ?? const []).whereType<Map>().toList()
      ..sort((x, y) => (int.tryParse('${x['section_number']}') ?? 0).compareTo(int.tryParse('${y['section_number']}') ?? 0));
    return [
      for (final s in sections)
        if ('${s['listen_url'] ?? ''}'.startsWith('http'))
          AudioTrack(
            title: _plain('${s['title'] ?? 'Section ${s['section_number']}'}'),
            path: '${s['listen_url']}'.replaceFirst('http://', 'https://'),
            ms: _secs(s['playtime']) * 1000,
          ),
    ];
  }

  // ---------------- Internet Archive ----------------

  /// Searches the Internet Archive's "Audio Books & Poetry" collection, most downloaded first.
  static Future<List<FreeAudiobook>> archive(String query, {String collection = 'audio_bookspoetry'}) async {
    final q = query.trim().replaceAll(RegExp(r'[():"]'), ' ');
    final filter = 'collection:($collection) AND mediatype:(audio)${q.isEmpty ? '' : ' AND (title:($q) OR creator:($q))'}';
    final url = 'https://archive.org/advancedsearch.php?q=${Uri.encodeQueryComponent(filter)}'
        '&fl[]=identifier&fl[]=title&fl[]=creator&fl[]=description&fl[]=year&fl[]=language&sort[]=downloads+desc&rows=30&output=json';
    final j = await _json(url);
    final resp = j is Map ? j['response'] : null;
    final docs = ((resp is Map ? resp['docs'] : null) as List?) ?? const [];
    String one(dynamic v) => v is List ? v.map((e) => '$e').join(', ') : '${v ?? ''}';
    return [
      for (final d in docs.whereType<Map>())
        FreeAudiobook(
          source: 'archive',
          key: '${d['identifier']}',
          title: _plain(one(d['title'])),
          author: one(d['creator']),
          description: _plain(one(d['description'])),
          language: one(d['language']),
          year: one(d['year']),
          coverUrl: 'https://archive.org/services/img/${d['identifier']}',
        ),
    ];
  }

  /// An Internet Archive item's MP3 files, in track order.
  static Future<List<AudioTrack>> archiveTracks(String id) async {
    final j = await _json('https://archive.org/metadata/$id');
    final files = ((j is Map ? j['files'] : null) as List? ?? const []).whereType<Map>().toList();
    // Items usually carry several encodings of the same audio; keep one.
    const prefs = ['VBR MP3', '128Kbps MP3', '64Kbps MP3', 'MP3', 'Ogg Vorbis'];
    final format = prefs.firstWhere((f) => files.any((x) => x['format'] == f), orElse: () => '');
    if (format.isEmpty) return const [];
    final chosen = files.where((f) => f['format'] == format).toList()
      ..sort((a, b) {
        final ta = int.tryParse('${a['track'] ?? ''}'.split('/').first) ?? 1 << 20;
        final tb = int.tryParse('${b['track'] ?? ''}'.split('/').first) ?? 1 << 20;
        return ta != tb ? ta.compareTo(tb) : '${a['name']}'.compareTo('${b['name']}');
      });
    return [
      for (final f in chosen)
        AudioTrack(
          title: '${f['title'] ?? ''}'.trim().isNotEmpty ? '${f['title']}' : cleanTrackTitle('${f['name']}'.split('/').last),
          path: 'https://archive.org/download/$id/${'${f['name']}'.split('/').map(Uri.encodeComponent).join('/')}',
          ms: _secs(f['length']) * 1000,
        ),
    ];
  }

  static Future<List<AudioTrack>> tracks(FreeAudiobook b) => b.source == 'librivox' ? librivoxTracks(b.key) : archiveTracks(b.key);
}

/// "03 - The_Mirror.mp3" → "The Mirror"
String cleanTrackTitle(String file) {
  var s = file.replaceAll(RegExp(r'\.[A-Za-z0-9]{2,4}$'), '').replaceAll(RegExp(r'[_]+'), ' ').trim();
  final stripped = s.replaceFirst(RegExp(r'^\s*(track|chapter|ch|part)?\s*\d+\s*[-.:)_ ]+\s*', caseSensitive: false), '').trim();
  if (stripped.isNotEmpty) s = stripped;
  return s;
}

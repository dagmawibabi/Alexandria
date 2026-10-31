import 'dart:convert';
import 'dart:typed_data';

import 'package:html/parser.dart' as html;
import 'package:http/http.dart' as http;

import 'api_cache.dart';

class BookInfo {
  BookInfo({
    required this.title,
    this.author = '',
    this.description = '',
    this.publisher = '',
    this.year = '',
    this.isbn = '',
    this.coverUrl,
    this.subjects = const [],
    this.pageCount = 0,
    this.source = '',
    this.key = '',
    this.downloadUrl,
  });

  final String title;
  final String author;
  String description;
  final String publisher;
  final String year;
  final String isbn;
  final String? coverUrl;
  final List<String> subjects;
  final int pageCount;
  final String source;
  final String key;

  /// A free EPUB (Project Gutenberg) when known.
  final String? downloadUrl;

  /// Its page on the catalogue it came from.
  String? get webUrl {
    if (key.startsWith('gutenberg:')) return 'https://www.gutenberg.org/ebooks/${key.substring(10)}';
    if (key.startsWith('/')) return 'https://openlibrary.org$key';
    if (source == 'Google Books' && key.isNotEmpty) return 'https://books.google.com/books?id=$key';
    return null;
  }
}

const _ua = {'User-Agent': 'Alexandria-Reader/1.0 (personal ebook reader)'};

/// Catalogue records barely change, so a week-old answer is still a good one.
Future<dynamic> _getJson(String url, {Duration timeout = const Duration(seconds: 12)}) async {
  final body = await ApiCache.get(url, ttl: const Duration(days: 7), headers: _ua, timeout: timeout);
  if (body == null) return null;
  try {
    return jsonDecode(body);
  } catch (_) {
    return null;
  }
}

class Metadata {
  static Future<List<BookInfo>> openLibrary(String query, {int limit = 10}) async {
    final j = await _getJson('https://openlibrary.org/search.json?q=${Uri.encodeQueryComponent(query)}&limit=$limit'
        '&fields=key,title,author_name,first_publish_year,isbn,cover_i,subject,number_of_pages_median,publisher');
    final docs = (j?['docs'] as List?) ?? const [];
    return [
      for (final d in docs)
        BookInfo(
          title: d['title'] ?? '',
          author: ((d['author_name'] as List?) ?? const []).take(3).join(', '),
          year: '${d['first_publish_year'] ?? ''}',
          isbn: ((d['isbn'] as List?) ?? const []).cast<String>().where((s) => s.length == 13).firstOrNull ?? '',
          coverUrl: d['cover_i'] == null ? null : 'https://covers.openlibrary.org/b/id/${d['cover_i']}-L.jpg',
          subjects: ((d['subject'] as List?) ?? const []).cast<String>().take(10).toList(),
          pageCount: d['number_of_pages_median'] ?? 0,
          publisher: ((d['publisher'] as List?) ?? const []).cast<String>().firstOrNull ?? '',
          source: 'Open Library',
          key: d['key'] ?? '',
        ),
    ];
  }

  static Future<String> openLibraryDescription(String workKey) async {
    if (workKey.isEmpty) return '';
    final j = await _getJson('https://openlibrary.org$workKey.json');
    final d = j?['description'];
    if (d is String) return d;
    if (d is Map) return d['value'] ?? '';
    return '';
  }

  static Future<List<BookInfo>> googleBooks(String query, {int limit = 10}) async {
    final j = await _getJson('https://www.googleapis.com/books/v1/volumes?q=${Uri.encodeQueryComponent(query)}&maxResults=$limit&printType=books');
    final items = (j?['items'] as List?) ?? const [];
    return [
      for (final it in items)
        () {
          final v = it['volumeInfo'] ?? {};
          final ids = (v['industryIdentifiers'] as List?) ?? const [];
          var thumb = (v['imageLinks']?['thumbnail'] ?? v['imageLinks']?['smallThumbnail']) as String?;
          thumb = thumb?.replaceFirst('http://', 'https://').replaceAll('&edge=curl', '').replaceAll('zoom=1', 'zoom=2');
          return BookInfo(
            title: v['title'] ?? '',
            author: ((v['authors'] as List?) ?? const []).take(3).join(', '),
            description: v['description'] ?? '',
            publisher: v['publisher'] ?? '',
            year: RegExp(r'\d{4}').firstMatch(v['publishedDate'] ?? '')?.group(0) ?? '',
            isbn: ids.where((e) => e['type'] == 'ISBN_13').map((e) => e['identifier'] as String).firstOrNull ?? '',
            coverUrl: thumb,
            subjects: ((v['categories'] as List?) ?? const []).cast<String>(),
            pageCount: v['pageCount'] ?? 0,
            source: 'Google Books',
            key: it['id'] ?? '',
          );
        }(),
    ];
  }

  /// Candidates from both sources, best first.
  static Future<List<BookInfo>> candidates(String title, String author, {String isbn = ''}) async {
    final q = isbn.isNotEmpty ? 'isbn:$isbn' : [title, author].where((s) => s.isNotEmpty).join(' ');
    final results = await Future.wait([
      googleBooks(isbn.isNotEmpty ? 'isbn:$isbn' : 'intitle:$title${author.isNotEmpty ? ' inauthor:$author' : ''}', limit: 6),
      openLibrary(isbn.isNotEmpty ? isbn : q, limit: 6),
    ]);
    final all = [...results[1], ...results[0]];
    double score(BookInfo b) {
      var s = 0.0;
      if (b.coverUrl != null) s += 2;
      if (b.description.isNotEmpty) s += 1;
      if (_norm(b.title) == _norm(title)) s += 3;
      if (_norm(b.title).contains(_norm(title)) || _norm(title).contains(_norm(b.title))) s += 1;
      if (author.isNotEmpty && _norm(b.author).contains(_norm(author).split(' ').last)) s += 2;
      return s;
    }

    all.sort((a, b) => score(b).compareTo(score(a)));
    return all;
  }

  /// Free-text search across both catalogues, results with covers first.
  static Future<List<BookInfo>> search(String query) async {
    final r = await Future.wait([googleBooks(query, limit: 10), openLibrary(query, limit: 10)]);
    final all = [...r[0], ...r[1]];
    all.sort((a, b) => (b.coverUrl != null ? 1 : 0) + (b.description.isNotEmpty ? 1 : 0) - (a.coverUrl != null ? 1 : 0) - (a.description.isNotEmpty ? 1 : 0));
    return all;
  }

  static Future<BookInfo?> best(String title, String author, {String isbn = ''}) async {
    final all = await candidates(title, author, isbn: isbn);
    if (all.isEmpty) return null;
    final top = all.first;
    if (top.description.isEmpty) {
      top.description = await openLibraryDescription(top.key);
      if (top.description.isEmpty) {
        top.description = all.where((b) => b.description.isNotEmpty && _norm(b.title) == _norm(top.title)).firstOrNull?.description ?? '';
      }
    }
    return top;
  }

  static String _norm(String s) => s.toLowerCase().replaceAll(RegExp(r'[^\p{L}\p{M}\p{N} ]', unicode: true), '').trim();

  static Future<Uint8List?> download(String url) async {
    try {
      final r = await http.get(Uri.parse(url), headers: _ua).timeout(const Duration(seconds: 60));
      return r.statusCode == 200 ? r.bodyBytes : null;
    } catch (_) {
      return null;
    }
  }

  /// Free public-domain books from Project Gutenberg (via Gutendex).
  static Future<List<BookInfo>> gutenberg(String query) =>
      _gutendex('https://gutendex.com/books/${query.trim().isEmpty ? '' : '?search=${Uri.encodeQueryComponent(query.trim())}'}');

  /// Keywords for browsing when nothing has been searched yet.
  static const keywords = [
    'Adventure', 'Mystery', 'Science fiction', 'Philosophy', 'Romance', 'History', 'Poetry', 'Fantasy', //
    'Horror', 'Detective', 'Travel', 'Short stories', 'Gothic', 'Psychology', 'Humor', 'Mythology',
  ];

  /// Free books under a keyword, in a fresh order each time. Gutendex answers
  /// topic lists quickly but can stall; its general list is the fallback.
  static Future<List<BookInfo>> popular(String keyword) async {
    var r = await _gutendex('https://gutendex.com/books/?topic=${Uri.encodeQueryComponent(keyword.toLowerCase())}');
    if (r.isEmpty) r = await _gutendex('https://gutendex.com/books/');
    return [...r]..shuffle();
  }

  /// World catalogue results for a keyword, in a fresh order each time.
  static Future<List<BookInfo>> catalogPopular(String keyword) async => [...await openLibrary('subject:"${keyword.toLowerCase()}"', limit: 30)]..shuffle();

  static Future<List<BookInfo>> _gutendex(String url) async {
    // This service is slow when it has to do real work.
    final j = await _getJson(url, timeout: const Duration(seconds: 30));
    final results = (j?['results'] as List?) ?? const [];
    return [
      for (final r in results)
        if ((r['formats'] as Map?)?['application/epub+zip'] != null)
          BookInfo(
            title: r['title'] ?? '',
            author: ((r['authors'] as List?) ?? const []).map((a) => _flipName(a['name'] ?? '')).join(', '),
            coverUrl: r['formats']['image/jpeg'],
            description: ((r['summaries'] as List?) ?? const []).whereType<String>().firstOrNull?.replaceFirst(RegExp(r'\s*\(This is an automatically generated summary\.\)\s*$'), '') ?? '',
            subjects: ((r['subjects'] as List?) ?? const []).cast<String>().take(5).toList(),
            source: 'Project Gutenberg',
            key: 'gutenberg:${r['id']}',
            downloadUrl: r['formats']['application/epub+zip'],
          ),
    ];
  }

  static String _flipName(String n) {
    final parts = n.split(', ');
    return parts.length == 2 ? '${parts[1]} ${parts[0]}' : n;
  }
}

// ---------------- dictionary ----------------

class Definition {
  Definition(this.partOfSpeech, this.text, {this.example, this.synonyms = const [], this.source = 'Free Dictionary'});
  final String partOfSpeech;
  final String text;
  final String? example;
  final List<String> synonyms;

  /// Which dictionary it came from: 'Free Dictionary' or 'Wiktionary'.
  final String source;
}

class DictEntry {
  DictEntry({required this.word, this.phonetic = '', this.audio, this.definitions = const [], this.wiki, this.wikiImage});
  final String word;
  final String phonetic;
  final String? audio;
  final List<Definition> definitions;
  final String? wiki;
  final String? wikiImage;

  bool get isEmpty => definitions.isEmpty && wiki == null;
}

class Dictionary {
  static final Map<String, DictEntry> _cache = {};

  static Future<DictEntry> lookup(String raw) async {
    final word = raw.trim().replaceAll(RegExp(r'^[^\p{L}\p{M}\p{N}_]+|[^\p{L}\p{M}\p{N}_]+$', unicode: true), '');
    final key = word.toLowerCase();
    if (_cache[key] != null) return _cache[key]!;

    final single = !word.contains(' ');
    final results = await Future.wait([
      single ? _getJson('https://api.dictionaryapi.dev/api/v2/entries/en/${Uri.encodeComponent(key)}') : Future.value(null),
      _getJson('https://en.wikipedia.org/api/rest_v1/page/summary/${Uri.encodeComponent(word.replaceAll(' ', '_'))}'),
      _getJson('https://en.wiktionary.org/api/rest_v1/page/definition/${Uri.encodeComponent(key.replaceAll(' ', '_'))}'),
    ]);

    final defs = <Definition>[];
    var phonetic = '';
    String? audio;
    final d = results[0];
    if (d is List && d.isNotEmpty) {
      for (final e in d) {
        phonetic = phonetic.isEmpty ? (e['phonetic'] ?? '') : phonetic;
        for (final ph in (e['phonetics'] as List? ?? const [])) {
          if (phonetic.isEmpty && (ph['text'] ?? '').isNotEmpty) phonetic = ph['text'];
          if (audio == null && (ph['audio'] ?? '').isNotEmpty) audio = ph['audio'];
        }
        for (final m in (e['meanings'] as List? ?? const [])) {
          for (final def in (m['definitions'] as List? ?? const []).take(4)) {
            defs.add(Definition(m['partOfSpeech'] ?? '', def['definition'] ?? '',
                example: def['example'],
                synonyms: [...((def['synonyms'] as List?) ?? const []), ...((m['synonyms'] as List?) ?? const [])].cast<String>().take(6).toList()));
          }
        }
      }
    }

    defs.addAll(_wiktionary(results[2]));

    String? wiki;
    String? wikiImage;
    final w = results[1];
    if (w is Map && w['type'] != 'disambiguation' && (w['extract'] ?? '').isNotEmpty) {
      wiki = w['extract'];
      wikiImage = w['thumbnail']?['source'];
    }

    return _cache[key] = DictEntry(word: word, phonetic: phonetic, audio: audio, definitions: defs, wiki: wiki, wikiImage: wikiImage);
  }

  /// Wiktionary's definitions: English first, then any other language it lists.
  static List<Definition> _wiktionary(dynamic j) {
    if (j is! Map) return const [];
    String plain(String s) => (html.parseFragment(s).text ?? '').replaceAll(RegExp(r'\s+'), ' ').trim();
    final langs = [if (j['en'] is List) 'en', ...j.keys.where((k) => k != 'en' && j[k] is List)];
    final out = <Definition>[];
    for (final lang in langs) {
      for (final e in (j[lang] as List).whereType<Map>()) {
        final pos = '${e['partOfSpeech'] ?? ''}'.toLowerCase();
        final label = lang == 'en' ? pos : '${e['language'] ?? lang} · $pos';
        for (final d in (e['definitions'] as List? ?? const []).whereType<Map>().take(3)) {
          final text = plain('${d['definition'] ?? ''}');
          if (text.isEmpty) continue;
          final ex = (d['examples'] as List?)?.whereType<String>().map(plain).where((x) => x.isNotEmpty).firstOrNull;
          out.add(Definition(label, text, example: ex, source: 'Wiktionary'));
        }
        if (out.length >= 8) return out;
      }
    }
    return out;
  }
}

// Renders the real app screens with demo data and saves them for the website.
//   flutter test tool/screenshots/capture_test.dart
// Nothing here ships in the app, and nothing touches a device.
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:ui' as ui;

import 'package:alexandria/core/search_box.dart';
import 'package:alexandria/core/settings.dart';
import 'package:alexandria/core/theme.dart';
import 'package:alexandria/core/ui.dart';
import 'package:alexandria/models/annotations.dart';
import 'package:alexandria/models/audiobook.dart';
import 'package:alexandria/models/book.dart';
import 'package:alexandria/models/doc.dart';
import 'package:alexandria/models/podcast.dart';
import 'package:alexandria/screens/ai_sheets.dart';
import 'package:alexandria/screens/book_detail.dart';
import 'package:alexandria/screens/folders_screen.dart';
import 'package:alexandria/screens/listen_sheet.dart';
import 'package:alexandria/screens/reader/reader_sheets.dart';
import 'package:alexandria/services/folders.dart';
import 'package:alexandria/screens/player_screen.dart';
import 'package:alexandria/screens/quote_card.dart';
import 'package:alexandria/screens/reader/reader_screen.dart';
import 'package:alexandria/screens/shell.dart';
import 'package:alexandria/screens/stats_screen.dart';
import 'package:alexandria/screens/widgets_screen.dart';
import 'package:alexandria/services/audio.dart';
import 'package:alexandria/services/library.dart';
import 'package:alexandria/services/podcasts.dart';
import 'package:alexandria/services/storage.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/rendering.dart' show RenderRepaintBoundary, debugDisableShadows;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:material_ui/material_ui.dart';
import 'package:omni_ai/omni_ai.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

const out = 'site/static/assets/shots';
const _lead = 40;
const width = 412.0, height = 892.0, ratio = 2.0;

final _boundary = GlobalKey();
final _nav = GlobalKey<NavigatorState>();

class _RealHttp extends HttpOverrides {}

const mobyDick = [
  'Call me Ishmael. Some years ago, never mind how long precisely, having little or no money in my purse, and nothing particular to interest me on shore, I thought I would sail about a little and see the watery part of the world. It is a way I have of driving off the spleen and regulating the circulation.',
  'Whenever I find myself growing grim about the mouth; whenever it is a damp, drizzly November in my soul; whenever I find myself involuntarily pausing before coffin warehouses, and bringing up the rear of every funeral I meet; then, I account it high time to get to sea as soon as I can.',
  'This is my substitute for pistol and ball. With a philosophical flourish Cato throws himself upon his sword; I quietly take to the ship. There is nothing surprising in this. If they but knew it, almost all men in their degree, some time or other, cherish very nearly the same feelings towards the ocean with me.',
  'There now is your insular city of the Manhattoes, belted round by wharves as Indian isles by coral reefs, commerce surrounds it with her surf. Right and left, the streets take you waterward. Its extreme downtown is the battery, where that noble mole is washed by waves, and cooled by breezes, which a few hours previous were out of sight of land.',
  'Look at the crowds of water-gazers there. Circumambulate the city of a dreamy Sabbath afternoon. Go from Corlears Hook to Coenties Slip, and from thence, by Whitehall, northward. What do you see? Posted like silent sentinels all around the town, stand thousands upon thousands of mortal men fixed in ocean reveries.',
  'Once more. Say you are in the country; in some high land of lakes. Take almost any path you please, and ten to one it carries you down in a dale, and leaves you there by a pool in the stream. There is magic in it. Let the most absent-minded of men be plunged in his deepest reveries, and he will infallibly lead you to water.',
];

Book _book(String id, String title, String author, double progress, {ReadStatus status = ReadStatus.reading, BookFormat format = BookFormat.epub, int pages = 300, bool fav = false, int rating = 0, int ago = 1, List<String> folders = const [], String year = '', List<String> subjects = const [], String desc = ''}) => Book(
      id: id,
      title: title,
      author: author,
      format: format,
      path: 'demo/$id.${format.name}',
      progress: progress,
      status: progress >= 1 ? ReadStatus.finished : status,
      pageCount: pages,
      wordCount: pages * 275,
      favorite: fav,
      rating: rating,
      year: year,
      subjects: subjects,
      description: desc,
      folderIds: folders,
      metadataFetched: true,
      fileSize: 1200000 + pages * 1300,
      addedAt: DateTime.now().subtract(Duration(days: ago + 20)),
      lastOpenedAt: progress > 0 ? DateTime.now().subtract(Duration(hours: ago * 7)) : null,
      finishedAt: progress >= 1 ? DateTime.now().subtract(Duration(days: ago * 9)) : null,
    );

Future<void> _seed() async {
  final lib = Library.i;
  final sea = Folder(id: 'sea', name: 'At sea', color: 0xFF2D6BFF);
  final stoic = Folder(id: 'stoic', name: 'Stoics', color: 0xFFFF5A1F);
  final gothic = Folder(id: 'gothic', name: 'Gothic', color: 0xFFE5243B);
  lib.folders.addAll([sea, stoic, gothic]);
  lib.books.addAll([
    _book('moby', 'Moby-Dick', 'Herman Melville', .34, pages: 635, ago: 0, fav: true, rating: 5, folders: ['sea'], year: '1851', subjects: ['Whaling', 'Sea stories', 'Obsession'], desc: 'A sailor signs on with a captain who has one purpose left: to find the white whale that took his leg.'),
    _book('medit', 'Meditations', 'Marcus Aurelius', .71, pages: 254, ago: 1, fav: true, rating: 5, folders: ['stoic']),
    _book('frank', 'Frankenstein', 'Mary Shelley', .12, pages: 280, ago: 2, folders: ['gothic']),
    _book('odyss', 'The Odyssey', 'Homer', 1, pages: 384, ago: 3, rating: 4, folders: ['sea']),
    _book('walden', 'Walden', 'Henry David Thoreau', .46, format: BookFormat.pdf, pages: 352, ago: 4),
    _book('dracula', 'Dracula', 'Bram Stoker', 1, pages: 418, ago: 5, rating: 4, folders: ['gothic']),
    _book('time', 'The Time Machine', 'H. G. Wells', 0, pages: 118, ago: 6, status: ReadStatus.unread),
    _book('pride', 'Pride and Prejudice', 'Jane Austen', 1, pages: 432, ago: 7, rating: 5),
    _book('epict', 'The Enchiridion', 'Epictetus', .58, format: BookFormat.docx, pages: 62, ago: 8, folders: ['stoic']),
    _book('dorian', 'The Picture of Dorian Gray', 'Oscar Wilde', 0, pages: 254, ago: 9, status: ReadStatus.unread, folders: ['gothic']),
    _book('war', 'The War of the Worlds', 'H. G. Wells', .08, pages: 288, ago: 10),
    _book('alice', "Alice's Adventures in Wonderland", 'Lewis Carroll', 1, pages: 96, ago: 11),
  ]);

  // Earlier and later pages are filler, so the bookmark sits a third of the way in.
  final blocks = <Block>[
    for (var i = 0; i < _lead; i++) Block(BlockType.paragraph, text: mobyDick[i % mobyDick.length]),
    const Block(BlockType.heading, text: 'Loomings', level: 1),
    for (final t in mobyDick) Block(BlockType.paragraph, text: t),
    const Block(BlockType.quote, text: 'Yes, as every one knows, meditation and water are wedded for ever.'),
    for (var i = 0; i < 72; i++) Block(BlockType.paragraph, text: mobyDick[i % mobyDick.length]),
  ];
  final doc = ParsedDoc(blocks: blocks, toc: const [TocEntry('Etymology', 0), TocEntry('Extracts', 14), TocEntry('Loomings', _lead), TocEntry('The Carpet-Bag', _lead + 20), TocEntry('The Spouter-Inn', _lead + 50)], pageCount: 635);
  await File(p.join(Storage.cache.path, 'moby.json')).writeAsString(jsonEncode(doc.toJson()));

  const hit = 'whenever it is a damp, drizzly November in my soul';
  final at = mobyDick[1].indexOf(hit);
  lib.highlights.addAll([
    Highlight(id: 'h1', bookId: 'moby', block: _lead + 2, start: at, end: at + hit.length, text: hit, color: 0, note: 'Best opening mood in English.'),
    Highlight(id: 'h2', bookId: 'moby', block: _lead + 3, start: 0, end: 38, text: mobyDick[2].substring(0, 38), color: 2),
    Highlight(id: 'h3', bookId: 'medit', block: 2, start: 0, end: 20, text: 'You have power over your mind', color: 1),
  ]);
  lib.bookmarks.add(Bookmark(id: 'b1', bookId: 'moby', block: _lead + 5, label: 'Water-gazers', progress: .34));

  // Half a year of sessions, with a live streak.
  final r = Random(11);
  final now = DateTime.now();
  for (var d = 0; d < 180; d++) {
    if (d > 21 && r.nextDouble() < .3) continue;
    final day = now.subtract(Duration(days: d));
    final id = lib.books[r.nextInt(lib.books.length)].id;
    lib.sessions.add(ReadingSession(bookId: id, start: DateTime(day.year, day.month, day.day, 21), seconds: 600 + r.nextInt(2400), words: 2000 + r.nextInt(9000), mode: r.nextBool() ? 'scroll' : 'swipe'));
    if (r.nextDouble() < .5) lib.sessions.add(ReadingSession(bookId: 'nar', start: DateTime(day.year, day.month, day.day, 8), seconds: 900 + r.nextInt(2400), mode: 'audiobook', label: 'The Time Machine'));
    if (r.nextDouble() < .4) lib.sessions.add(ReadingSession(bookId: 'show', start: DateTime(day.year, day.month, day.day, 18), seconds: 900 + r.nextInt(1800), mode: 'podcast', label: 'Slow History'));
  }

  AudioTrack tr(int n, int min) => AudioTrack(title: 'Chapter $n', path: 'demo/$n.mp3', ms: min * 60000);
  final narrated = Audiobook(id: 'nar', title: 'The Time Machine', author: 'H. G. Wells', narrator: 'LibriVox volunteers', source: 'librivox', tracks: [for (var i = 1; i <= 12; i++) tr(i, 14 + i)], trackIndex: 4, positionMs: 520000, speed: 1.25, lastPlayedAt: now, bookId: 'time', mark: UserMark(rating: 4, favorite: true));
  AudioLibrary.i.books.addAll([
    narrated,
    Audiobook(id: 'a2', title: 'Meditations', author: 'Marcus Aurelius', narrator: 'LibriVox volunteers', source: 'librivox', tracks: [for (var i = 1; i <= 12; i++) tr(i, 22)], trackIndex: 7, positionMs: 60000, lastPlayedAt: now.subtract(const Duration(days: 1))),
    Audiobook(id: 'a3', title: 'Sherlock Holmes', author: 'Arthur Conan Doyle', narrator: 'Internet Archive', source: 'archive', tracks: [for (var i = 1; i <= 12; i++) tr(i, 40)], trackIndex: 2, lastPlayedAt: now.subtract(const Duration(days: 3))),
    Audiobook(id: 'a4', title: 'Treasure Island', author: 'Robert Louis Stevenson', source: 'librivox', tracks: [for (var i = 1; i <= 34; i++) tr(i, 12)], finished: true),
  ]);
  lib.byId('moby')!.position = _lead + 1;
  Player.i
    ..book = narrated
    ..position = const Duration(milliseconds: 520000)
    ..duration = Duration(milliseconds: narrated.tracks[4].ms)
    ..playing = true;

  Episode ep(String show, String feed, String title, int days, int min) => Episode(guid: '$feed$title', feedUrl: feed, title: title, audioUrl: 'demo.mp3', podcastTitle: show, published: now.subtract(Duration(days: days)), durationMs: min * 60000, description: 'A long, unhurried conversation.');
  Podcast show(String title, String author, String feed, List<(String, int, int)> eps) => Podcast(feedUrl: feed, title: title, author: author, categories: const ['History'], subscribedAt: now, updatedAt: now, episodes: [for (final e in eps) ep(title, feed, e.$1, e.$2, e.$3)]);
  Podcasts.i.subscriptions.addAll([
    show('Slow History', 'Demo Radio', 'demo://slow', [('The grain ships of Alexandria', 0, 58), ('What the lighthouse was for', 7, 64), ('Papyrus, and who paid for it', 14, 49)]),
    show('Margin Notes', 'Demo Radio', 'demo://margin', [('Reading Melville slowly', 1, 41), ('Why we reread', 8, 37)]),
    show('Night Shift', 'Demo Radio', 'demo://night', [('Four hours past midnight', 2, 73)]),
    show('The Long Table', 'Demo Radio', 'demo://table', [('A meal, in eleven chapters', 3, 88)]),
    show('Field Recordings', 'Demo Radio', 'demo://field', [('Harbour at 5am', 4, 31)]),
    show('Plain Words', 'Demo Radio', 'demo://plain', [('Sentences that hold', 5, 26)]),
  ]);
  // The directories answer from the app's own cache, so these lists are demo data too.
  Future<void> cached(String key, Object body) async {
    final f = File(p.join(Storage.cache.path, 'api', sha1.convert(utf8.encode(key)).toString()));
    await f.parent.create(recursive: true);
    await f.writeAsString(jsonEncode(body));
  }

  await cached('https://rss.marketingtools.apple.com/api/v2/us/podcasts/top/50/podcasts.json', {
    'feed': {
      'results': [
        for (final (i, n) in const ['The Morning Brief', 'Deep Ocean', 'Common Law', 'Small Machines', 'Old Maps', 'Short Wave Stories', 'Open Kitchen', 'Second Draft', 'Quiet Science'].indexed)
          {'id': '$i', 'name': n, 'artistName': 'Demo Radio', 'genres': [{'name': const ['News', 'Science', 'Society', 'Technology', 'History', 'Fiction'][i % 6]}]},
      ],
    },
  });
  await cached('radio-browser${Uri(path: '/json/stations/search', queryParameters: const {'hidebroken': 'true', 'is_https': 'true', 'order': 'clickcount', 'reverse': 'true', 'limit': '60', 'offset': '0'})}', [
    for (final (i, st) in const [('Addis Evening', 'Ethiopia', 'ET', 'news,talk'), ('Lagos Highlife', 'Nigeria', 'NG', 'afrobeats'), ('Kyoto Lo-fi', 'Japan', 'JP', 'lofi'), ('Lisboa Jazz', 'Portugal', 'PT', 'jazz'), ('Nordic Classical', 'Sweden', 'SE', 'classical'), ('Sao Paulo Samba', 'Brazil', 'BR', 'latin'), ('Nairobi Talk', 'Kenya', 'KE', 'talk'), ('Seoul Night', 'South Korea', 'KR', 'pop'), ('Reykjavik Ambient', 'Iceland', 'IS', 'ambient')].indexed)
      {'stationuuid': 'demo$i', 'name': st.$1, 'url_resolved': 'https://demo.invalid/$i', 'url': 'https://demo.invalid/$i', 'country': st.$2, 'countrycode': st.$3, 'tags': st.$4, 'language': '', 'bitrate': 128, 'favicon': '', 'homepage': ''},
  ]);
  SearchHistory.i.add('books', 'melville');
  SearchHistory.i.add('books', 'stoicism');
  SearchHistory.i.add('books', 'shipwreck');
  // Let the debounced saves run before the fake clock takes over.
  await Future<void>.delayed(const Duration(milliseconds: 600));
}

/// A phone falls back to its own emoji font; the test engine needs telling.
ThemeData _emoji(ThemeData t) => _emojiFamily == null ? t : t.copyWith(textTheme: t.textTheme.apply(fontFamilyFallback: [_emojiFamily!]));
String? _emojiFamily;

Widget _app() => ListenableBuilder(
      listenable: Settings.i,
      builder: (context, _) {
        final s = Settings.i;
        return RepaintBoundary(
          key: _boundary,
          child: MaterialApp(
            navigatorKey: _nav,
            debugShowCheckedModeBanner: false,
            themeMode: s.themeMode,
            theme: _emoji(buildTheme(Brightness.light, s)),
            darkTheme: _emoji(buildTheme(Brightness.dark, s)),
            home: const Shell(),
          ),
        );
      },
    );

Future<void> _settle(WidgetTester tester, {int ms = 1200}) async {
  // Real file and network replies arrive between pumps, so alternate in small steps.
  for (var i = 0; i < ms ~/ 50; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pump(const Duration(milliseconds: 16));
  }
  await tester.pump(const Duration(milliseconds: 500));
  await tester.pump(const Duration(milliseconds: 500));
}

Future<void> _save(WidgetTester tester, String name) async {
  await tester.runAsync(() async {
    final b = _boundary.currentContext!.findRenderObject() as RenderRepaintBoundary;
    final ui.Image img = await b.toImage(pixelRatio: ratio);
    final ByteData? data = await img.toByteData(format: ui.ImageByteFormat.png);
    await File('$out/$name.png').writeAsBytes(data!.buffer.asUint8List());
    img.dispose();
  });
  // ignore: avoid_print
  print('saved $name');
}

/// One screenshot: fresh settings, then [open] drives the app to the screen.
void shot(String name, {Map<String, Object?> set = const {}, int tab = 0, Future<void> Function(WidgetTester, BuildContext)? open, int waitMs = 1200}) {
  // SHOTS=radio,player limits a run to those screens.
  final only = Platform.environment['SHOTS'];
  if (only != null && only.isNotEmpty && !only.split(',').contains(name)) return;
  testWidgets(name, (tester) async {
    debugDisableShadows = false;
    tester.view
      ..physicalSize = const Size(width * ratio, height * ratio)
      ..devicePixelRatio = ratio
      ..padding = const FakeViewPadding(top: 30 * ratio, bottom: 14 * ratio)
      ..viewPadding = const FakeViewPadding(top: 30 * ratio, bottom: 14 * ratio);
    final saved = FlutterError.onError;
    final problems = <String>[];
    FlutterError.onError = (d) => problems.add(d.exceptionAsString().split('\n').first);
    Settings.i.reset(Settings.i.exportJson().keys.toList());
    Settings.i.keepAwake = false;
    Settings.i.immersive = false;
    Settings.i.themeMode = ThemeMode.dark;
    set.forEach(Settings.i.set);
    shellTab.value = tab;
    await tester.pumpWidget(_app());
    await _settle(tester, ms: waitMs);
    if (open != null) {
      await open(tester, _nav.currentContext!);
      await _settle(tester, ms: waitMs);
    }
    await _save(tester, name);
    for (final q in problems) {
      // ignore: avoid_print
      print('  note [$name]: $q');
    }
    FlutterError.onError = saved;
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 5));
    tester.takeException();
  }, timeout: const Timeout(Duration(seconds: 60)));
}

Future<void> _push(WidgetTester tester, BuildContext c, Widget w) async {
  Navigator.of(c).push(MaterialPageRoute(builder: (_) => w));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

Widget _page(String title, Widget body) => Scaffold(
      appBar: AppBar(title: AppTitle(title)),
      body: ListView(padding: const EdgeInsets.fromLTRB(20, 4, 20, 40), children: [body]),
    );

Book get _moby => Library.i.byId('moby')!;

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    HttpOverrides.global = _RealHttp();
    await Directory(out).create(recursive: true);
    // Kept between runs so fonts are only fetched once.
    final tmp = await Directory(p.absolute('build', 'tmp', 'shots_data')).create(recursive: true);
    for (final old in ['data', 'cache'].map((d) => Directory(p.join(tmp.path, 'alexandria', d)))) {
      if (old.existsSync()) old.deleteSync(recursive: true);
    }
    final m = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    m.setMockMethodCallHandler(const MethodChannel('plugins.flutter.io/path_provider'), (_) async => tmp.path);
    for (final ch in ['xyz.luan/audioplayers', 'xyz.luan/audioplayers.global', 'alexandria/podcasts', 'alexandria/widgets', 'alexandria/downloads', 'alexandria/intent', 'alexandria/power', 'flutter_tts', 'dev.fluttercommunity.plus/share']) {
      m.setMockMethodCallHandler(MethodChannel(ch), (_) async => null);
    }
    // ignore: invalid_use_of_visible_for_testing_member
    SharedPreferences.setMockInitialValues({});
    await Settings.i.load();
    await Storage.init();
    final icons = FontLoader('MaterialIcons')..addFont(File(p.join(Platform.environment['FLUTTER_ROOT'] ?? r'D:\installs\Flutter\flutter', 'bin', 'cache', 'artifacts', 'material_fonts', 'MaterialIcons-Regular.otf')).readAsBytes().then((b) => ByteData.sublistView(b)));
    await icons.load();
    // Fetched here, outside the fake clock, so no screen ever waits on a font.
    for (final f in ['Space Grotesk', 'JetBrains Mono', 'Inter', 'Literata', 'Newsreader', 'IBM Plex Mono', 'EB Garamond']) {
      for (final w in [FontWeight.w300, FontWeight.w400, FontWeight.w500, FontWeight.w600, FontWeight.w700, FontWeight.w800]) {
        for (final st in [FontStyle.normal, FontStyle.italic]) {
          try {
            GoogleFonts.getFont(f, fontWeight: w, fontStyle: st);
            await GoogleFonts.pendingFonts().timeout(const Duration(seconds: 20));
          } catch (_) {}
        }
      }
    }
    try {
      final e = GoogleFonts.getFont('Noto Color Emoji');
      await GoogleFonts.pendingFonts().timeout(const Duration(seconds: 200));
      _emojiFamily = e.fontFamily;
    } catch (e) {
      // ignore: avoid_print
      print('emoji: $e');
    }
    await _seed();
  });

  shot('library', tab: 0);
  shot('library-light', tab: 0, set: {'themeMode': 1});
  shot('books', tab: 1, waitMs: 6000);
  shot('audio', tab: 2);
  shot('podcasts', tab: 3, waitMs: 5000);
  shot('config', tab: 4);
  shot('zen', tab: 0, set: {'zen': true, 'themeMode': 1});
  shot('mono', tab: 0, set: {'mono': true});
  shot('reader', set: {'themeMode': 1}, open: (t, c) => _push(t, c, ReaderScreen(book: _moby)), waitMs: 3200);
  shot('reader-crt', set: {'night': true, 'nightSurface': 'amber', 'fontFamily': 'JetBrains Mono', 'fontSize': 16.0}, open: (t, c) => _push(t, c, ReaderScreen(book: _moby)), waitMs: 3200);
  shot('reader-phosphor', set: {'night': true, 'nightSurface': 'phosphor', 'fontFamily': 'IBM Plex Mono', 'fontSize': 16.0}, open: (t, c) => _push(t, c, ReaderScreen(book: _moby)), waitMs: 3200);
  shot('swipe', set: {'night': true, 'nightSurface': 'graphite', 'fontFamily': 'Newsreader'}, open: (t, c) async {
    await _push(t, c, ReaderScreen(book: _moby));
    await _settle(t, ms: 400);
    final btn = find.byIcon(Icons.swipe_vertical_outlined);
    if (btn.evaluate().isNotEmpty) await t.tap(btn.first, warnIfMissed: false);
  });
  shot('player', open: (t, c) => _push(t, c, const PlayerScreen()));
  shot('stats', open: (t, c) => _push(t, c, const StatsScreen()));
  shot('widgets', open: (t, c) => _push(t, c, const StatWidgetsScreen()));
  shot('quote', open: (t, c) => _push(t, c, QuoteStudio(book: _moby, text: 'whenever it is a damp, drizzly November in my soul; then, I account it high time to get to sea as soon as I can.', chapter: 'Loomings', progress: .34)));
  shot('radio', tab: 3, waitMs: 9000, open: (t, c) async {
    await t.tap(find.text('GLOBAL RADIO').first, warnIfMissed: false);
  });
  shot('folders', open: (t, c) => _push(t, c, const FoldersScreen(kind: FolderKind.books)));
  shot('detail', open: (t, c) => _push(t, c, BookDetail(book: _moby)));
  shot('type', open: (t, c) => _push(t, c, _page('Type', const TypeControls())));
  shot('surfaces', open: (t, c) => _push(t, c, _page('Light & surface', const LightControls())));
  shot('motion', open: (t, c) => _push(t, c, _page('Motion & gestures', const MotionControls(showListen: false))));
  shot('voices', open: (t, c) => _push(t, c, _page('Read-aloud voice', const ListenPanel())));
  shot('history', tab: 1, waitMs: 3000, open: (t, c) async {
    await t.tap(find.byType(TextField).first, warnIfMissed: false);
  });
  shot('zen-reader', set: {'zen': true, 'themeMode': 1, 'daySurface': 'white', 'fontFamily': 'Inter'}, open: (t, c) => _push(t, c, ReaderScreen(book: _moby)), waitMs: 3200);
  shot('chat', open: (t, c) => _push(t, c, AiChatScreen(book: _moby, seed: [
        Message.user('Why does Ishmael go to sea?'),
        Message.assistant('He goes when he feels **grim about the mouth**. The sea is his cure for a low mood, and he says so with a wink: it is his "substitute for pistol and ball".\n\nSo far the book frames the voyage as a personal remedy, not an adventure.'),
        Message.user('Keep it spoiler-free. What should I watch for?'),
        Message.assistant('Watch how often water pulls people in. Ishmael keeps insisting that everyone, in every town, drifts towards it.\n\nThat pull is worth remembering as the crew assembles.'),
      ])));
}

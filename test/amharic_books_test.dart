import 'dart:convert';
import 'dart:io';

import 'package:alexandria/core/settings.dart';
import 'package:alexandria/core/theme.dart';
import 'package:alexandria/models/audiobook.dart';
import 'package:alexandria/models/book.dart';
import 'package:alexandria/models/doc.dart';
import 'package:alexandria/models/podcast.dart';
import 'package:alexandria/screens/audiobooks_screen.dart';
import 'package:alexandria/screens/discover_screen.dart';
import 'package:alexandria/screens/library_screen.dart';
import 'package:alexandria/screens/podcasts_view.dart';
import 'package:alexandria/screens/recently_added.dart';
import 'package:alexandria/services/podcasts.dart';
import 'package:alexandria/screens/reader/block_view.dart';
import 'package:alexandria/screens/reader/reader_screen.dart';
import 'package:alexandria/screens/reader/swipe_view.dart';
import 'package:alexandria/services/audio.dart';
import 'package:alexandria/services/library.dart';
import 'package:alexandria/services/storage.dart';
import 'package:archive/archive.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:material_ui/material_ui.dart';
import 'package:path/path.dart' as p;
import 'package:pdfrx/pdfrx.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Older typesetting: word and sentence marks with no spaces at all.
const packed = 'ሰላም፡ለዓለም፡እንዴት፡ነህ።መጽሐፍ፡ማንበብ፡ጥሩ፡ነው።ኢትዮጵያ፡ሀገር፡ናት።';
const spaced = 'ሰላም ለዓለም እንዴት ነህ። መጽሐፍ ማንበብ ጥሩ ነው። ኢትዮጵያ ሀገር ናት።';

List<int> zip(Map<String, String> files) {
  final a = Archive();
  files.forEach((name, text) {
    final bytes = utf8.encode(text);
    a.addFile(ArchiveFile(name, bytes.length, bytes));
  });
  return ZipEncoder().encode(a);
}

List<int> amharicEpub(String body) => zip({
      'mimetype': 'application/epub+zip',
      'META-INF/container.xml': '<container><rootfiles><rootfile full-path="book.opf"/></rootfiles></container>',
      'book.opf': '<package xmlns:dc="http://purl.org/dc/elements/1.1/"><metadata><dc:title>ፍቅር እስከ መቃብር</dc:title><dc:language>am</dc:language></metadata>'
          '<manifest><item id="c" href="c.xhtml" media-type="application/xhtml+xml"/></manifest><spine><itemref idref="c"/></spine></package>',
      'c.xhtml': '<html><body><h1>ምዕራፍ አንድ</h1><p>$body</p></body></html>',
    });

void main() {
  late Directory tmp;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    GoogleFonts.config.allowRuntimeFetching = false;
    tmp = await Directory.systemTemp.createTemp('alexandria_amharic');
    final m = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    m.setMockMethodCallHandler(const MethodChannel('plugins.flutter.io/path_provider'), (_) async => tmp.path);
    for (final ch in ['xyz.luan/audioplayers', 'xyz.luan/audioplayers.global', 'xyz.luan/audioplayers.global/events', 'xyz.luan/audioplayers/events/alexandria-audiobooks', 'flutter_tts', 'alexandria/power', 'alexandria/volumekeys']) {
      m.setMockMethodCallHandler(MethodChannel(ch), (_) async => null);
    }
    m.setMockMessageHandler('dev.flutter.pigeon.wakelock_plus_platform_interface.WakelockPlusApi.toggle', (_) async => const StandardMessageCodec().encodeMessage(<Object?>[null]));
    SharedPreferences.setMockInitialValues({});
    await Settings.i.load();
    await Storage.init();
    Settings.i.autoFetchMetadata = false;
    Settings.i.keepAwake = false;
  });

  group('counting and splitting', () {
    test('Ethiopic marks separate words, with or without spaces', () {
      expect(const Block(BlockType.paragraph, text: packed).words, 11);
      expect(const Block(BlockType.paragraph, text: spaced).words, 11);
      expect(const Block(BlockType.paragraph, text: 'plain english words').words, 3);
      expect(const Block(BlockType.paragraph).words, 0);
    });

    test('a book with no spaces still splits into cards, losing nothing', () {
      final doc = ParsedDoc(toc: const [], blocks: [Block(BlockType.paragraph, text: packed * 200)]);
      final chunks = buildChunks(doc, 100);
      expect(chunks.length, greaterThan(10));
      expect(chunks.map((c) => c.text).join(), packed * 200);
    });

    test('spaced Amharic and English still break at sentence ends', () {
      final am = buildChunks(ParsedDoc(toc: const [], blocks: [Block(BlockType.paragraph, text: List.filled(100, spaced).join(' '))]), 100);
      expect(am.length, greaterThan(5));
      for (final c in am.take(am.length - 1)) {
        expect(c.text.trimRight(), endsWith('።'));
      }
      final en = buildChunks(ParsedDoc(toc: const [], blocks: [Block(BlockType.paragraph, text: List.filled(100, 'One two three four. ').join())]), 40);
      expect(en.first.text.trimRight(), endsWith('.'));
    });
  });

  group('adding files', () {
    Future<Book> add(List<int> bytes, String name) async {
      final f = File(p.join(tmp.path, 'in_${DateTime.now().microsecondsSinceEpoch}'));
      await f.writeAsBytes(bytes);
      return Library.i.importFile(f.path, displayName: name);
    }

    test('an Amharic EPUB imports with its title and headings', () async {
      final book = await add(amharicEpub(spaced), 'book.epub');
      expect(book.title, 'ፍቅር እስከ መቃብር');
      expect(book.wordCount, 13);
      final doc = await Library.i.doc(book);
      expect(doc.toc.single.title, 'ምዕራፍ አንድ');
    });

    test('a file with no usable name is recognised by its contents', () async {
      final book = await add(amharicEpub('$spaced ሌላ'), 'document');
      expect(book.format, BookFormat.epub);
      expect(Library.formatFromBytes(utf8.encode('%PDF-1.7 rest')), BookFormat.pdf);
      expect(Library.formatFromBytes(zip({'word/document.xml': '<x/>'})), BookFormat.docx);
      expect(Library.formatFromBytes(zip({'other.txt': 'x'})), isNull);
      expect(Library.formatFromBytes(utf8.encode('just some text')), isNull);
      await expectLater(add(utf8.encode('just some text'), 'document'), throwsFormatException);
    });

    test('what was just added comes first until it is opened', () async {
      final older = Book(id: 'older', title: 'A', format: BookFormat.epub, path: '', addedAt: DateTime(2020));
      final book = await add(amharicEpub('$spaced አዲስ'), 'new.epub');
      expect(Library.i.newFirst([older, book]).first, book);

      book.lastOpenedAt = DateTime.now().add(const Duration(minutes: 1));
      expect(Library.i.newFirst([older, book]).first, older);

      // Added again: a copy already here counts as just added too.
      book.lastOpenedAt = DateTime.now().subtract(const Duration(minutes: 1));
      await add(amharicEpub('$spaced አዲስ'), 'new.epub');
      expect(Library.i.newFirst([older, book]).first, book);
    });
  });

  group('on screen', () {
    Future<void> open(WidgetTester tester, ParsedDoc doc, String id) async {
      tester.view
        ..physicalSize = const Size(412, 892)
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.runAsync(() => File(p.join(Storage.cache.path, '$id.json')).writeAsString(jsonEncode(doc.toJson())));
      final nav = GlobalKey<NavigatorState>();
      await tester.pumpWidget(MaterialApp(navigatorKey: nav, theme: buildTheme(Brightness.light, Settings.i), home: const Scaffold(body: SizedBox())));
      nav.currentState!.push(MaterialPageRoute(builder: (_) => ReaderScreen(book: Book(id: id, title: 'ፍቅር እስከ መቃብር', format: BookFormat.epub, path: ''))));
      await tester.pump();
      for (var i = 0; i < 20; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 10)));
        await tester.pump(const Duration(milliseconds: 16));
      }
      await tester.pump(const Duration(seconds: 3));
    }

    Future<void> close(WidgetTester tester) async {
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 5));
    }

    testWidgets('the reader opens a whole Amharic book with no spaces', (tester) async {
      final doc = ParsedDoc(toc: const [TocEntry('ምዕራፍ አንድ', 0)], blocks: [
        const Block(BlockType.heading, text: 'ምዕራፍ አንድ', level: 1),
        Block(BlockType.paragraph, text: packed * 500),
        Block(BlockType.paragraph, text: spaced * 20),
      ]);
      await open(tester, doc, 'amharic-open');
      expect(tester.takeException(), isNull);
      expect(find.byType(ReaderScreen), findsOneWidget);
      await close(tester);
    });

    testWidgets('a scanned PDF, with no text at all, survives turning pages and closing', (tester) async {
      tester.view
        ..physicalSize = const Size(412, 892)
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      const id = 'scanned-pdf';
      await tester.runAsync(() => File(p.join(Storage.cache.path, '$id.json')).writeAsString(jsonEncode(ParsedDoc(blocks: const [], toc: const [], pageCount: 11).toJson())));
      final book = Book(id: id, title: 'ፍቅር እስከ መቃብር', format: BookFormat.pdf, path: p.join(tmp.path, 'missing.pdf'));
      final nav = GlobalKey<NavigatorState>();
      await tester.pumpWidget(MaterialApp(navigatorKey: nav, theme: buildTheme(Brightness.light, Settings.i), home: const Scaffold(body: SizedBox())));
      nav.currentState!.push(MaterialPageRoute(builder: (_) => ReaderScreen(book: book)));
      await tester.pump();
      for (var i = 0; i < 20; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 10)));
        await tester.pump(const Duration(milliseconds: 16));
      }
      tester.takeException();

      // What the viewer reports when you swipe to page 2, then page 6.
      for (final page in [2, 6]) {
        tester.widget<PdfViewer>(find.byType(PdfViewer)).params.onPageChanged!(page);
        await tester.pump();
        expect(tester.takeException(), isNot(isA<RangeError>()));
      }
      await tester.pump(const Duration(seconds: 3));
      expect(book.position, 5);
      expect(book.progress, closeTo(.5, .001));

      nav.currentState!.pop();
      await tester.pump(const Duration(seconds: 1));
      expect(tester.takeException(), isNot(isA<RangeError>()));
      await close(tester);
      tester.takeException();
      expect(book.position, 5, reason: 'closing must not lose the page');
    });

    testWidgets('opening and closing a book over the Library screen raises no framework errors', (tester) async {
      tester.view
        ..physicalSize = const Size(412, 892)
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      const id = 'open-close';
      final doc = ParsedDoc(toc: const [], blocks: [Block(BlockType.paragraph, text: spaced * 20)]);
      await tester.runAsync(() => File(p.join(Storage.cache.path, '$id.json')).writeAsString(jsonEncode(doc.toJson())));
      final book = Book(id: id, title: 'Open and close', format: BookFormat.epub, path: '');
      Library.i.books
        ..clear()
        ..add(book);

      final nav = GlobalKey<NavigatorState>();
      await tester.pumpWidget(MaterialApp(navigatorKey: nav, theme: buildTheme(Brightness.light, Settings.i), home: const Scaffold(body: LibraryScreen())));
      await tester.pump(const Duration(milliseconds: 100));

      nav.currentState!.push(MaterialPageRoute(builder: (_) => ReaderScreen(book: book)));
      await tester.pump();
      for (var i = 0; i < 20; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 10)));
        await tester.pump(const Duration(milliseconds: 16));
      }
      await tester.pump(const Duration(seconds: 3));
      expect(tester.takeException(), isNull, reason: 'while opening');

      nav.currentState!.pop();
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(tester.takeException(), isNull, reason: 'while closing');

      // The list still hears about it, a moment later.
      expect(book.lastOpenedAt, isNotNull);
      Library.i.books.clear();
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 3));
    });

    testWidgets('each tab shows only its own kind under Recently added', (tester) async {
      tester.view
        ..physicalSize = const Size(412, 1400)
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final now = DateTime.now();
      Library.i.books
        ..clear()
        ..add(Book(id: 'k-book', title: 'Added Book', format: BookFormat.epub, path: '', addedAt: now));
      AudioLibrary.i.books
        ..clear()
        ..add(Audiobook(id: 'k-audio', title: 'Added Audiobook', tracks: const [], addedAt: now));
      Podcasts.i.subscriptions
        ..clear()
        ..addAll([
          Podcast(feedUrl: 'https://example.test/new', title: 'Added Show', subscribedAt: now),
          Podcast(feedUrl: 'https://example.test/old', title: 'Old Show', subscribedAt: now.subtract(const Duration(days: 60))),
        ]);
      addTearDown(() {
        Library.i.books.clear();
        AudioLibrary.i.books.clear();
        Podcasts.i.subscriptions.clear();
      });

      Future<void> check(Widget screen, String expected, List<String> others) async {
        await tester.pumpWidget(MaterialApp(theme: buildTheme(Brightness.light, Settings.i), home: Scaffold(body: screen)));
        await tester.pump(const Duration(milliseconds: 100));
        tester.takeException();
        final section = find.textContaining(RegExp('recently added', caseSensitive: false));
        expect(section, findsOneWidget, reason: expected);
        final rail = find.ancestor(of: section, matching: find.byType(Column)).first;
        expect(find.descendant(of: rail, matching: find.text(expected)), findsWidgets);
        for (final o in others) {
          expect(find.descendant(of: rail, matching: find.text(o)), findsNothing, reason: '$o under $expected');
        }
        await tester.pumpWidget(const SizedBox());
        await tester.pump(const Duration(seconds: 1));
        tester.takeException();
      }

      await check(const DiscoverScreen(), 'Added Book', ['Added Audiobook', 'Added Show']);
      await check(const AudiobooksScreen(), 'Added Audiobook', ['Added Book', 'Added Show']);
      await check(const PodcastsScreen(), 'Added Show', ['Added Book', 'Added Audiobook', 'Old Show']);
      await check(const RecentlyAdded(), 'Added Show', ['Old Show']);
      await tester.pump(const Duration(seconds: 30));
      tester.takeException();
    });

    testWidgets('a new book or audiobook leads the Recently added section', (tester) async {
      tester.view
        ..physicalSize = const Size(412, 892)
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final now = DateTime.now();
      Library.i.books
        ..clear()
        ..addAll([
          Book(id: 'r-old', title: 'Ancient Book', format: BookFormat.epub, path: '', addedAt: now.subtract(const Duration(days: 90))),
          Book(id: 'r-book', title: 'Newer Book', format: BookFormat.epub, path: '', addedAt: now.subtract(const Duration(days: 2))),
        ]);
      AudioLibrary.i.books
        ..clear()
        ..add(Audiobook(id: 'r-audio', title: 'Newest Audiobook', tracks: const [], addedAt: now.subtract(const Duration(hours: 1))));

      await tester.pumpWidget(MaterialApp(theme: buildTheme(Brightness.light, Settings.i), home: const Scaffold(body: LibraryScreen())));
      await tester.pump(const Duration(milliseconds: 100));
      expect(tester.takeException(), isNull);

      final section = find.textContaining(RegExp('recently added', caseSensitive: false));
      expect(section, findsOneWidget);
      final rail = find.ancestor(of: section, matching: find.byType(Column)).first;
      final inRail = find.descendant(of: rail, matching: find.byType(GestureDetector));
      expect(inRail, findsWidgets);
      // A generated cover prints the title too; the caption comes after it.
      Finder tile(String title) => find.descendant(of: rail, matching: find.text(title)).last;
      expect(find.descendant(of: rail, matching: find.text('Ancient Book')), findsNothing, reason: 'older than a month');
      expect(tester.getTopLeft(tile('Newest Audiobook')).dx, lessThan(tester.getTopLeft(tile('Newer Book')).dx));
      expect(tester.getTopLeft(section).dy, lessThan(tester.getTopLeft(find.textContaining(RegExp(r'^books ·', caseSensitive: false))).dy));

      Library.i.books.clear();
      AudioLibrary.i.books.clear();
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 1));
    });

    for (final marked in [null, 0]) {
      testWidgets('the selection menu fills its width with text labels (marked: $marked)', (tester) async {
        tester.view
          ..physicalSize = const Size(360, 800)
          ..devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        await tester.pumpWidget(MaterialApp(
          theme: buildTheme(Brightness.light, Settings.i),
          home: Scaffold(body: SelectionMenu(anchors: const TextSelectionToolbarAnchors(primaryAnchor: Offset(180, 400)), marked: marked, onAction: (_, {int color = 0}) {})),
        ));
        await tester.pump();
        expect(tester.takeException(), isNull);

        final labels = ['Explain', 'Define', 'Card', 'Note', 'Copy', 'Find', 'Speak'].map((l) => find.textContaining(RegExp(l, caseSensitive: false))).toList();
        for (final text in labels) {
          expect(text, findsOneWidget);
          expect(tester.getRect(text).right, lessThanOrEqualTo(360));
        }
        // Text buttons carry no icons; the only icons are the row's own tools.
        expect(find.byIcon(Icons.auto_awesome_outlined), findsNothing);
        expect(find.byIcon(Icons.content_copy_sharp), findsNothing);
        expect(find.byType(ListView), findsNothing);

        // No empty space beside the bookmark: it ends where the labels end.
        final bookmark = tester.getRect(find.byIcon(Icons.bookmark_add_outlined));
        expect(bookmark.right, greaterThan(tester.getRect(labels.last).right - 8));
      });
    }

    test('old highlights keep their colour', () {
      expect(highlightColors.take(5), const [Color(0xFFFFD54A), Color(0xFFFF8A65), Color(0xFF7FD1AE), Color(0xFF7FB2FF), Color(0xFFD59BFF)]);
      expect(highlightColors.length, 7);
    });
  });
}

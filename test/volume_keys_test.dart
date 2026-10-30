import 'dart:convert';
import 'dart:io';

import 'package:alexandria/core/settings.dart';
import 'package:alexandria/core/theme.dart';
import 'package:alexandria/models/book.dart';
import 'package:alexandria/models/doc.dart';
import 'package:alexandria/screens/reader/reader_screen.dart';
import 'package:alexandria/services/audio.dart';
import 'package:alexandria/services/storage.dart';
import 'package:alexandria/services/volume_keys.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:material_ui/material_ui.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  const channel = MethodChannel('alexandria/volumekeys');
  final calls = <bool>[];
  final book = Book(id: 'volume-test', title: 'Test', format: BookFormat.epub, path: '');

  /// What Android sends when a button goes down.
  Future<void> press(WidgetTester tester, int dir) async {
    await tester.binding.defaultBinaryMessenger.handlePlatformMessage(channel.name, channel.codec.encodeMethodCall(MethodCall('turn', dir)), (_) {});
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
  }

  Future<void> openReader(WidgetTester tester, GlobalKey<NavigatorState> nav) async {
    tester.view
      ..physicalSize = const Size(412, 892)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      navigatorKey: nav,
      navigatorObservers: [VolumeKeys.routes],
      theme: buildTheme(Brightness.light, Settings.i),
      home: const Scaffold(body: SizedBox()),
    ));
    nav.currentState!.push(MaterialPageRoute(builder: (_) => ReaderScreen(book: book)));
    await tester.pump();
    for (var i = 0; i < 20; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 10)));
      await tester.pump(const Duration(milliseconds: 16));
    }
    await tester.pump(const Duration(seconds: 3));
  }

  Future<void> closeReader(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 5));
    tester.takeException();
  }

  double scrollOffset(WidgetTester tester) => tester.state<ScrollableState>(find.byType(Scrollable).first).position.pixels;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    GoogleFonts.config.allowRuntimeFetching = false;
    final tmp = await Directory.systemTemp.createTemp('alexandria_volume');
    final m = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    m.setMockMethodCallHandler(const MethodChannel('plugins.flutter.io/path_provider'), (_) async => tmp.path);
    for (final ch in ['xyz.luan/audioplayers', 'xyz.luan/audioplayers.global', 'flutter_tts', 'alexandria/power']) {
      m.setMockMethodCallHandler(MethodChannel(ch), (_) async => null);
    }
    m.setMockMethodCallHandler(channel, (c) async {
      if (c.method == 'capture') calls.add(c.arguments as bool);
      return null;
    });
    m.setMockMessageHandler('dev.flutter.pigeon.wakelock_plus_platform_interface.WakelockPlusApi.toggle', (_) async => const StandardMessageCodec().encodeMessage(<Object?>[null]));
    SharedPreferences.setMockInitialValues({});
    await Settings.i.load();
    await Storage.init();
    final doc = ParsedDoc(blocks: [for (var i = 0; i < 80; i++) Block(BlockType.paragraph, text: 'Call me Ishmael. ' * 40)], toc: const [TocEntry('One', 0)]);
    await File(p.join(Storage.cache.path, '${book.id}.json')).writeAsString(jsonEncode(doc.toJson()));
  });

  setUp(() {
    calls.clear();
    Settings.i.reset(Settings.i.exportJson().keys.toList());
    Settings.i.keepAwake = false;
    Player.i.playing = false;
    book.position = 0;
    book.positionOffset = 0;
  });

  test('on by default, and the setting sticks', () {
    expect(Settings.i.volumePaging, isTrue);
    Settings.i.volumePaging = false;
    expect(Settings.i.volumePaging, isFalse);
  });

  test('only wanted when on, uncovered and silent', () {
    expect(VolumeKeys.wanted(enabled: true, covered: false, audioPlaying: false), isTrue);
    expect(VolumeKeys.wanted(enabled: false, covered: false, audioPlaying: false), isFalse);
    expect(VolumeKeys.wanted(enabled: true, covered: true, audioPlaying: false), isFalse);
    expect(VolumeKeys.wanted(enabled: true, covered: false, audioPlaying: true), isFalse);
  });

  testWidgets('down pages forward, up pages back, and closing gives the buttons back', (tester) async {
    await openReader(tester, GlobalKey<NavigatorState>());
    expect(calls, [true]);
    final before = scrollOffset(tester);
    await press(tester, 1);
    final after = scrollOffset(tester);
    expect(after, greaterThan(before));
    await press(tester, -1);
    expect(scrollOffset(tester), lessThan(after));
    await closeReader(tester);
    expect(calls, [true, false]);
  });

  testWidgets('the direction can be swapped, and it applies straight away', (tester) async {
    await openReader(tester, GlobalKey<NavigatorState>());
    Settings.i.volumePagingSwapped = true;
    await tester.pump();
    final before = scrollOffset(tester);
    await press(tester, -1); // volume up
    final after = scrollOffset(tester);
    expect(after, greaterThan(before));
    await press(tester, 1); // volume down
    expect(scrollOffset(tester), lessThan(after));
    await closeReader(tester);
  });

  testWidgets('the toggle releases the buttons straight away, and they do nothing', (tester) async {
    await openReader(tester, GlobalKey<NavigatorState>());
    Settings.i.volumePaging = false;
    await tester.pump();
    expect(calls, [true, false]);
    final before = scrollOffset(tester);
    await press(tester, 1);
    expect(scrollOffset(tester), before);
    Settings.i.volumePaging = true;
    await tester.pump();
    expect(calls, [true, false, true]);
    await closeReader(tester);
  });

  testWidgets('a sheet on top takes them back until it closes', (tester) async {
    final nav = GlobalKey<NavigatorState>();
    await openReader(tester, nav);
    showModalBottomSheet<void>(context: nav.currentContext!, builder: (_) => const SizedBox(height: 100));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(calls, [true, false]);
    nav.currentState!.pop();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(calls, [true, false, true]);
    await closeReader(tester);
  });

  testWidgets('audio playing keeps them for the volume', (tester) async {
    await openReader(tester, GlobalKey<NavigatorState>());
    Player.i.playing = true;
    // ignore: invalid_use_of_protected_member, invalid_use_of_visible_for_testing_member
    Player.i.notifyListeners();
    await tester.pump();
    expect(calls, [true, false]);
    Player.i.playing = false;
    // ignore: invalid_use_of_protected_member, invalid_use_of_visible_for_testing_member
    Player.i.notifyListeners();
    await tester.pump();
    expect(calls, [true, false, true]);
    await closeReader(tester);
  });

  testWidgets('swipe mode moves one card at a time', (tester) async {
    await openReader(tester, GlobalKey<NavigatorState>());
    await tester.tap(find.byIcon(Icons.swipe_vertical_outlined).first, warnIfMissed: false);
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    final pages = tester.widget<PageView>(find.byType(PageView).first).controller!;
    final start = pages.page!;
    await press(tester, 1);
    expect(pages.page, start + 1);
    await press(tester, -1);
    expect(pages.page, start);
    await closeReader(tester);
  });
}

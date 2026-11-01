import 'dart:io';

import 'package:alexandria/core/settings.dart';
import 'package:alexandria/core/theme.dart';
import 'package:alexandria/models/podcast.dart';
import 'package:alexandria/screens/podcasts_view.dart';
import 'package:alexandria/services/podcasts.dart';
import 'package:alexandria/services/storage.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

Episode episode(String title, {String notes = ''}) => Episode(guid: title, feedUrl: 'https://example.test/feed', title: title, audioUrl: 'https://example.test/$title.mp3', description: notes);

void main() {
  group('Episode.matches', () {
    final e = episode('The Roman Empire', notes: 'How Augustus took power.');

    test('looks in the title and the show notes, ignoring case', () {
      expect(e.matches('roman'), isTrue);
      expect(e.matches('AUGUSTUS'), isTrue);
      expect(e.matches('vikings'), isFalse);
    });

    test('every word has to appear, in any order and either place', () {
      expect(e.matches('augustus roman'), isTrue);
      expect(e.matches('roman vikings'), isFalse);
    });

    test('works for scripts without capitals', () {
      expect(episode('የኢትዮጵያ ታሪክ').matches('ታሪክ'), isTrue);
    });
  });

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    GoogleFonts.config.allowRuntimeFetching = false;
    final tmp = await Directory.systemTemp.createTemp('alexandria_episode_search');
    final m = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    m.setMockMethodCallHandler(const MethodChannel('plugins.flutter.io/path_provider'), (_) async => tmp.path);
    for (final ch in ['xyz.luan/audioplayers', 'xyz.luan/audioplayers.global', 'xyz.luan/audioplayers.global/events', 'xyz.luan/audioplayers/events/alexandria-audiobooks', 'flutter_tts']) {
      m.setMockMethodCallHandler(MethodChannel(ch), (_) async => null);
    }
    SharedPreferences.setMockInitialValues({});
    await Settings.i.load();
    await Storage.init();
  });

  testWidgets('searching a show narrows its episodes and clearing brings them back', (tester) async {
    tester.view
      ..physicalSize = const Size(412, 1600)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    const url = 'https://example.test/feed';
    Podcasts.i.subscribe(Podcast(feedUrl: url, title: 'History Show', episodes: [
      episode('The Roman Empire', notes: 'Augustus takes power.'),
      episode('Vikings at Sea'),
      episode('Silk Road Traders'),
    ]));

    await tester.pumpWidget(MaterialApp(theme: buildTheme(Brightness.light, Settings.i), home: const PodcastScreen(feedUrl: url)));
    for (var i = 0; i < 5; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pump(const Duration(milliseconds: 50));
    }
    tester.takeException();
    expect(find.text('Vikings at Sea'), findsOneWidget);

    final box = find.widgetWithText(TextField, 'Search this show');
    await tester.enterText(box, 'augustus');
    await tester.pump();
    expect(find.text('The Roman Empire'), findsOneWidget);
    expect(find.text('Vikings at Sea'), findsNothing);
    expect(find.textContaining(RegExp('1 found', caseSensitive: false)), findsOneWidget);

    // The keyboard closing must not lose the search.
    tester.view.viewInsets = const FakeViewPadding(bottom: 300);
    await tester.pump();
    tester.view.resetViewInsets();
    await tester.pump();
    expect(find.text('Vikings at Sea'), findsNothing);

    await tester.enterText(find.byType(TextField), 'dragons');
    await tester.pump();
    expect(find.textContaining('No episodes match'), findsOneWidget);

    await tester.tap(find.byTooltip('Clear'));
    await tester.pump();
    expect(find.text('Vikings at Sea'), findsOneWidget);
    expect(find.text('Silk Road Traders'), findsOneWidget);

    Podcasts.i.unsubscribe(url);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 5));
    tester.takeException();
  });
}

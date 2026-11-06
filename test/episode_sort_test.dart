import 'dart:io';

import 'package:alexandria/core/settings.dart';
import 'package:alexandria/core/theme.dart';
import 'package:alexandria/models/podcast.dart';
import 'package:alexandria/screens/podcasts_view.dart';
import 'package:alexandria/services/backup.dart';
import 'package:alexandria/services/podcasts.dart';
import 'package:alexandria/services/storage.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

Episode ep(String title, int day) => Episode(guid: 'sort-$title', feedUrl: 'https://example.test/sort', title: title, audioUrl: 'https://example.test/$day.mp3', published: DateTime(2026, 1, day));

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    GoogleFonts.config.allowRuntimeFetching = false;
    final tmp = await Directory.systemTemp.createTemp('alexandria_episode_sort');
    final m = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    m.setMockMethodCallHandler(const MethodChannel('plugins.flutter.io/path_provider'), (_) async => tmp.path);
    SharedPreferences.setMockInitialValues({});
    await Settings.i.load();
    await Storage.init();
  });

  tearDown(() {
    Podcasts.i.clearSorts();
    Settings.i.episodeSort = 'newest';
  });

  group('naturalCompare', () {
    List<String> sorted(List<String> xs) => [...xs]..sort(naturalCompare);

    test('numbers by value, not digit by digit', () {
      expect(sorted(['Episode 10', 'Episode 9', 'Episode 100', 'Episode 1']), ['Episode 1', 'Episode 9', 'Episode 10', 'Episode 100']);
      expect(sorted(['#11', '#2', '#02b']), ['#2', '#02b', '#11']);
    });

    test('ignores case', () {
      expect(sorted(['banana', 'Apple', 'cherry']), ['Apple', 'banana', 'cherry']);
    });
  });

  group('EpisodeSort', () {
    // Feeds come newest first.
    final eps = [ep('Episode 10', 3), ep('Aardvarks', 2), ep('Episode 2', 1)];

    test('each order', () {
      List<String> titles(EpisodeSort s) => s.apply(eps).map((e) => e.title).toList();
      expect(titles(EpisodeSort.newest), ['Episode 10', 'Aardvarks', 'Episode 2']);
      expect(titles(EpisodeSort.oldest), ['Episode 2', 'Aardvarks', 'Episode 10']);
      expect(titles(EpisodeSort.az), ['Aardvarks', 'Episode 2', 'Episode 10']);
      expect(titles(EpisodeSort.za), ['Episode 10', 'Episode 2', 'Aardvarks']);
    });

    test('an unknown saved name falls back to newest', () {
      expect(EpisodeSort.parse('sideways'), EpisodeSort.newest);
      expect(EpisodeSort.parse(null), EpisodeSort.newest);
    });
  });

  group('per-show order', () {
    const a = 'https://example.test/a', b = 'https://example.test/b';

    test('a show keeps its own order; others follow the default', () {
      Podcasts.i.setSort(a, EpisodeSort.az);
      expect(Podcasts.i.sortOf(a), EpisodeSort.az);
      expect(Podcasts.i.sortOf(b), EpisodeSort.newest);

      Settings.i.episodeSort = 'oldest';
      expect(Podcasts.i.sortOf(a), EpisodeSort.az, reason: 'its own choice wins');
      expect(Podcasts.i.sortOf(b), EpisodeSort.oldest, reason: 'follows the new default');

      Podcasts.i.setSort(a, null);
      expect(Podcasts.i.hasOwnSort(a), isFalse);
      expect(Podcasts.i.sortOf(a), EpisodeSort.oldest);
    });

    test('is saved, and comes back from a backup without overriding this device', () {
      Podcasts.i.setSort(a, EpisodeSort.za);
      expect(Podcasts.i.toJson()['showSorts'], {a: 'za'});

      Podcasts.i.mergeBackup({'showSorts': {a: 'az', b: 'oldest'}}, ImportResult());
      expect(Podcasts.i.sortOf(a), EpisodeSort.za, reason: 'set here, so kept');
      expect(Podcasts.i.sortOf(b), EpisodeSort.oldest, reason: 'only in the backup, so restored');
    });

    test('apply to all puts every show back on the default', () {
      Podcasts.i.setSort(a, EpisodeSort.az);
      Podcasts.i.setSort(b, EpisodeSort.za);
      Settings.i.episodeSort = 'oldest';
      Podcasts.i.clearSorts();
      expect(Podcasts.i.sortOf(a), EpisodeSort.oldest);
      expect(Podcasts.i.sortOf(b), EpisodeSort.oldest);
    });
  });

  testWidgets('the show page orders episodes from its chip, and remembers it for that show', (tester) async {
    tester.view
      ..physicalSize = const Size(412, 1600)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    const url = 'https://example.test/sort';
    Podcasts.i.subscribe(Podcast(feedUrl: url, title: 'Sorted Show', episodes: [ep('Episode 10', 3), ep('Aardvarks', 2), ep('Episode 2', 1)]));

    await tester.pumpWidget(MaterialApp(theme: buildTheme(Brightness.light, Settings.i), home: const PodcastScreen(feedUrl: url)));
    for (var i = 0; i < 5; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pump(const Duration(milliseconds: 50));
    }
    tester.takeException();

    List<String> shown() => [for (final r in tester.widgetList<EpisodeRow>(find.byType(EpisodeRow))) r.episode.title];
    expect(shown(), ['Episode 10', 'Aardvarks', 'Episode 2']);

    await tester.tap(find.textContaining(RegExp('newest first', caseSensitive: false)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Title A–Z'));
    await tester.pumpAndSettle();
    expect(shown(), ['Aardvarks', 'Episode 2', 'Episode 10']);
    expect(Podcasts.i.sortOf(url), EpisodeSort.az);

    // Back to the default, which is now set to oldest first.
    Settings.i.episodeSort = 'oldest';
    await tester.tap(find.textContaining(RegExp('title a–z', caseSensitive: false)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Use default'));
    await tester.pumpAndSettle();
    expect(shown(), ['Episode 2', 'Aardvarks', 'Episode 10']);

    Podcasts.i.unsubscribe(url);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 5));
    tester.takeException();
  });
}

import 'dart:io';

import 'package:alexandria/core/settings.dart';
import 'package:alexandria/models/podcast.dart';
import 'package:alexandria/models/radio.dart';
import 'package:alexandria/services/podcasts.dart';
import 'package:alexandria/services/radio.dart';
import 'package:alexandria/services/storage.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// What swiping the cover in the player moves to.
void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    final tmp = await Directory.systemTemp.createTemp('alexandria_swipe');
    final m = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    m.setMockMethodCallHandler(const MethodChannel('plugins.flutter.io/path_provider'), (_) async => tmp.path);
    SharedPreferences.setMockInitialValues({});
    await Settings.i.load();
    await Storage.init();
  });

  group('podcast episodes', () {
    const feed = 'https://example.test/swipe';
    Episode ep(int n) => Episode(guid: 'swipe-$n', feedUrl: feed, title: 'Episode $n', audioUrl: 'https://example.test/$n.mp3', published: DateTime(2026, 1, n));
    // Feeds list newest first.
    final eps = [ep(3), ep(2), ep(1)];

    setUpAll(() => Podcasts.i.subscribe(Podcast(feedUrl: feed, title: 'Swipe Show', episodes: eps)));
    tearDown(Podcasts.i.clearQueue);

    test('forward is the next newer episode, back the next older', () {
      expect(Podcasts.i.neighbour(eps[1], 1)?.guid, 'swipe-3');
      expect(Podcasts.i.neighbour(eps[1], -1)?.guid, 'swipe-1');
    });

    test('nothing past the newest or the oldest', () {
      expect(Podcasts.i.neighbour(eps[0], 1), isNull);
      expect(Podcasts.i.neighbour(eps[2], -1), isNull);
    });

    test('forward plays the queue first, like the next button', () {
      final other = Episode(guid: 'queued', feedUrl: 'https://example.test/other', title: 'Queued', audioUrl: 'https://example.test/q.mp3');
      Podcasts.i.enqueue(other);
      expect(Podcasts.i.neighbour(eps[1], 1)?.guid, 'queued');
      expect(Podcasts.i.neighbour(eps[1], -1)?.guid, 'swipe-1');
    });
  });

  group('radio stations', () {
    Station st(String id) => Station(id: id, name: id, url: 'https://example.test/$id');

    test('turns through favourites like a dial, wrapping around', () {
      final dir = RadioDirectory.i;
      for (final id in ['b', 'a', 'c']) {
        dir.toggleFavorite(st(id));
      }
      dir.changed(st('kept-only'));
      // Favourites go by name.
      expect(dir.neighbour('a', 1)?.id, 'b');
      expect(dir.neighbour('c', 1)?.id, 'a');
      expect(dir.neighbour('a', -1)?.id, 'c');
    });

    test('a station that is not a favourite moves through every kept one', () {
      expect(RadioDirectory.i.neighbour('kept-only', 1), isNotNull);
      expect(RadioDirectory.i.neighbour('never-seen', 1), isNull);
    });
  });
}

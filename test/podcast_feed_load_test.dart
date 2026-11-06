import 'dart:io';

import 'package:alexandria/services/podcasts.dart';
import 'package:alexandria/services/storage.dart';
import 'package:flutter_test/flutter_test.dart';

// Loads feeds from a local server, so no real network is needed.
String _rss(int episodes) => '''<?xml version="1.0"?>
<rss xmlns:itunes="http://www.itunes.com/dtds/podcast-1.0.dtd"><channel>
<title>Local Show</title><itunes:author>Someone</itunes:author><description>About it</description>
${[for (var i = 0; i < episodes; i++) '<item><title>Episode $i</title><guid>g$i</guid><pubDate>Tue, 05 Nov 2024 09:30:00 +0000</pubDate><description>${'<p>Notes for $i.</p>' * 20}</description><enclosure url="https://x.test/$i.mp3" type="audio/mpeg"/></item>'].join('\n')}
</channel></rss>''';

void main() {
  late HttpServer server;
  var hits = 0;

  setUpAll(() async {
    final d = Directory.systemTemp.createTempSync('feedtest');
    Storage.cache = d;
    Storage.data = d;
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((r) async {
      hits++;
      // Big enough to take the background-isolate path.
      final n = r.uri.path.contains('big') ? 1200 : 5;
      r.response.headers.contentType = ContentType('application', 'rss+xml', charset: 'utf-8');
      r.response.write(_rss(n));
      await r.response.close();
    });
  });

  tearDownAll(() => server.close(force: true));

  String url(String name) => 'http://127.0.0.1:${server.port}/$name.xml';

  test('a feed loads and its future completes', () async {
    final pod = await Podcasts.i.feed(url('small'), refresh: true).timeout(const Duration(seconds: 10));
    expect(pod?.title, 'Local Show');
    expect(pod!.episodes, hasLength(5));
  });

  test('a big feed parses in the background and completes', () async {
    final pod = await Podcasts.i.feed(url('big'), refresh: true).timeout(const Duration(seconds: 30));
    expect(pod!.episodes, hasLength(1200));
  });

  test('two callers at once share one download, and both complete', () async {
    hits = 0;
    final u = url('shared');
    final both = await Future.wait([Podcasts.i.feed(u, refresh: true), Podcasts.i.feed(u, refresh: true)]).timeout(const Duration(seconds: 10));
    expect(both[0], same(both[1]));
    expect(hits, 1);
    // And a later call is not stuck behind the finished one.
    await Podcasts.i.feed(u, refresh: true).timeout(const Duration(seconds: 10));
  });
}

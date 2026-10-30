import 'package:alexandria/models/podcast.dart';
import 'package:alexandria/services/podcasts.dart';
import 'package:flutter_test/flutter_test.dart';

const _feed = '''<?xml version="1.0" encoding="UTF-8"?>
<rss version="2.0" xmlns:itunes="http://www.itunes.com/dtds/podcast-1.0.dtd" xmlns:content="http://purl.org/rss/1.0/modules/content/">
  <channel>
    <title>Slow &amp; Steady</title>
    <link>https://example.com</link>
    <description><![CDATA[<p>A show about <b>patience</b>.</p>]]></description>
    <itunes:author>Sam Lee</itunes:author>
    <itunes:image href="https://example.com/show.jpg"/>
    <itunes:category text="Science"/>
    <item>
      <title>Older one</title>
      <guid>ep-1</guid>
      <pubDate>Mon, 01 Jan 2024 10:00:00 +0200</pubDate>
      <enclosure url="https://example.com/1.mp3" type="audio/mpeg"/>
      <itunes:duration>1:02:03</itunes:duration>
      <description>First.</description>
    </item>
    <item>
      <title>Newer one</title>
      <pubDate>Tue, 02 Jan 2024 10:00:00 GMT</pubDate>
      <enclosure url="https://example.com/2.mp3" type="audio/mpeg"/>
      <itunes:duration>125</itunes:duration>
      <itunes:image href="https://example.com/2.jpg"/>
      <content:encoded><![CDATA[<p>Second <i>notes</i></p>]]></content:encoded>
      <description>Short.</description>
    </item>
    <item>
      <title>Video, skipped</title>
      <enclosure url="https://example.com/3.mp4" type="video/mp4"/>
    </item>
    <item><title>No audio, skipped</title></item>
  </channel>
</rss>''';

void main() {
  test('parses a show and its episodes, newest first', () {
    final pod = Podcasts.parseFeed('https://example.com/feed', _feed)!;
    expect(pod.title, 'Slow & Steady');
    expect(pod.author, 'Sam Lee');
    expect(pod.description, 'A show about patience.');
    expect(pod.imageUrl, 'https://example.com/show.jpg');
    expect(pod.categories, ['Science']);
    expect(pod.episodes.map((e) => e.title), ['Newer one', 'Older one']);

    final newer = pod.episodes.first;
    expect(newer.guid, 'https://example.com/2.mp3'); // falls back to the audio URL
    expect(newer.description, 'Second notes');
    expect(newer.durationMs, 125000);
    expect(newer.art, 'https://example.com/2.jpg');

    final older = pod.episodes.last;
    expect(older.durationMs, 3723000);
    expect(older.art, 'https://example.com/show.jpg');
    expect(older.published, DateTime.utc(2024, 1, 1, 8));
  });

  test('episodes are unplayed, started or played', () {
    final pods = Podcasts.i;
    final pod = Podcasts.parseFeed('https://example.com/feed', _feed)!;
    final fresh = pod.episodes.first;
    final other = pod.episodes.last;
    expect(pods.stage(fresh), 'unplayed');

    // A few seconds' listen is not "started"; more is, and it leaves Unplayed.
    pods.states[fresh.guid] = EpisodeState(episode: fresh, posMs: 5000);
    expect(pods.stage(fresh), 'unplayed');
    pods.states[fresh.guid] = EpisodeState(episode: fresh, posMs: 60000);
    expect(pods.stage(fresh), 'started');

    pods.states[other.guid] = EpisodeState(episode: other, played: true);
    expect(pods.stage(other), 'played');
    pods.states.clear();
  });

  test('rejects things that are not feeds', () {
    expect(Podcasts.parseFeed('u', '<html><body>nope</body></html>'), isNull);
    expect(Podcasts.parseFeed('u', 'not xml at all'), isNull);
  });

  test('reads the date and duration forms feeds use', () {
    expect(Podcasts.parseRssDate('Wed, 5 Jun 2024 09:30 EST'), DateTime.utc(2024, 6, 5, 14, 30));
    expect(Podcasts.parseRssDate('2024-06-05T09:30:00Z'), DateTime.utc(2024, 6, 5, 9, 30));
    expect(Podcasts.parseRssDate('sometime'), isNull);
    expect(Podcasts.parseDuration('62:03'), 3723);
    expect(Podcasts.parseDuration(''), 0);
  });
}

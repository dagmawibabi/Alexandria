import 'package:alexandria/services/podcasts.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('reads feeds from nested, oddly-cased OPML and skips duplicates', () {
    const opml = '﻿<?xml version="1.0"?>\n<opml version="1.0"><head><title>x</title></head><body>'
        '<outline text="Folder"><outline type="rss" text="Show A" xmlUrl="https://a.example/feed"/>'
        '<outline text="Show B &amp; Co" xmlurl="https://b.example/rss"/></outline>'
        '<outline title="Dup" xmlUrl="https://a.example/feed"/><outline text="no feed"/></body></opml>';
    final feeds = Podcasts.parseOpml(opml);
    expect(feeds.map((f) => f.url), ['https://a.example/feed', 'https://b.example/rss']);
    expect(feeds.map((f) => f.title), ['Show A', 'Show B & Co']);
  });

  test('rejects files that are not OPML', () {
    expect(() => Podcasts.parseOpml('{"a":1}'), throwsFormatException);
    expect(() => Podcasts.parseOpml('<rss><channel/></rss>'), throwsFormatException);
  });
}

import 'dart:convert';
import 'dart:io';

import 'package:alexandria/core/settings.dart';
import 'package:alexandria/models/annotations.dart';
import 'package:alexandria/models/audiobook.dart';
import 'package:alexandria/models/book.dart';
import 'package:alexandria/models/podcast.dart';
import 'package:alexandria/services/audio.dart';
import 'package:alexandria/services/backup.dart';
import 'package:alexandria/services/library.dart';
import 'package:alexandria/services/podcasts.dart';
import 'package:alexandria/services/storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late Directory dir;

  setUp(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    await Settings.i.load();
    dir = Directory.systemTemp.createTempSync('backup');
    Storage.root = dir;
    Storage.data = dir;
    Storage.cache = dir;
    Storage.covers = dir;
    Storage.books = dir;
    Library.i.books.clear();
    Library.i.highlights.clear();
    Library.i.sessions.clear();
    AudioLibrary.i.books.clear();
    Podcasts.i.subscriptions.clear();
    Podcasts.i.states.clear();
    Podcasts.i.showMarks.clear();
  });

  File file(String name) => File('${dir.path}/$name')..writeAsStringSync('x');

  Book book(String id, {DateTime? opened, double progress = 0}) => Book(id: id, title: id, format: BookFormat.epub, path: file('$id.epub').path, lastOpenedAt: opened, progress: progress);

  Episode episode(String guid) => Episode(guid: guid, feedUrl: 'https://f', title: guid, audioUrl: 'https://f/$guid.mp3');

  /// A backup as it would come back through the file: real JSON, no live objects.
  Map<String, dynamic> roundTrip() => Map<String, dynamic>.from(jsonDecode(jsonEncode(Backup.export())));

  test('the export covers books, audiobooks, podcasts and settings', () {
    Library.i.books.add(book('a'));
    AudioLibrary.i.books.add(Audiobook(id: 'x', title: 'X', tracks: [AudioTrack(title: 't', path: 'https://s/t.mp3')], mark: UserMark(rating: 4, notes: [AudioNote(text: 'n')])));
    Podcasts.i.subscriptions.add(Podcast(feedUrl: 'https://f', title: 'Show'));
    Podcasts.i.states['g'] = EpisodeState(episode: episode('g'), posMs: 5000);
    Settings.i.zen = true;

    final j = roundTrip();
    expect(j['app'], 'alexandria');
    expect(j['version'], Backup.version);
    expect((j['books'] as List).length, 1);
    expect((j['audiobooks'] as List).first['mark']['rating'], 4);
    expect((j['podcasts'] as Map)['subscriptions'], hasLength(1));
    expect(j['settings']['zen'], true);
  });

  test('restoring brings everything back onto an empty app', () async {
    Library.i.books.add(book('a'));
    Library.i.highlights.add(Highlight(id: 'h', bookId: 'a', block: 0, start: 0, end: 1, text: 'hi'));
    AudioLibrary.i.books.add(Audiobook(id: 'x', title: 'X', tracks: [AudioTrack(title: 't', path: 'https://s/t.mp3')]));
    Podcasts.i.subscriptions.add(Podcast(feedUrl: 'https://f', title: 'Show'));
    Podcasts.i.states['g'] = EpisodeState(episode: episode('g'), posMs: 5000);
    final j = roundTrip();

    Library.i.books.clear();
    Library.i.highlights.clear();
    AudioLibrary.i.books.clear();
    Podcasts.i.subscriptions.clear();
    Podcasts.i.states.clear();

    final r = await Backup.restore(j);
    expect([r.books, r.audiobooks, r.shows, r.episodes, r.notes], [1, 1, 1, 1, 1]);
    expect(Library.i.books.single.id, 'a');
    expect(Podcasts.i.states['g']!.posMs, 5000);
  });

  test('restoring merges: nothing is lost and the newer copy wins', () async {
    final old = DateTime(2024), recent = DateTime(2025);
    Library.i.books.add(book('a', opened: old, progress: .1));
    final j = roundTrip();
    (j['books'] as List).first['progress'] = .9;
    (j['books'] as List).first['lastOpenedAt'] = recent.toIso8601String();

    Library.i.books.add(book('only-here'));
    await Backup.restore(j);
    expect(Library.i.books.map((b) => b.id), containsAll(['a', 'only-here']));
    expect(Library.i.byId('a')!.progress, .9);

    // An older backup must not roll progress back.
    (j['books'] as List).first['progress'] = .2;
    (j['books'] as List).first['lastOpenedAt'] = old.toIso8601String();
    await Backup.restore(j);
    expect(Library.i.byId('a')!.progress, .9);
  });

  test('restoring twice adds nothing new', () async {
    Library.i.books.add(book('a'));
    Library.i.sessions.add(ReadingSession(bookId: 'a', start: DateTime(2025), seconds: 60));
    Library.i.highlights.add(Highlight(id: 'h', bookId: 'a', block: 0, start: 0, end: 1, text: 'hi'));
    final j = roundTrip();
    final r = await Backup.restore(j);
    expect([r.books, r.notes], [0, 0]);
    expect(Library.i.sessions, hasLength(1));
  });

  test('media files that are gone are handled, and their data is kept', () async {
    final b = book('gone');
    Library.i.books.add(b);
    Library.i.highlights.add(Highlight(id: 'h', bookId: 'gone', block: 0, start: 0, end: 1, text: 'hi'));
    final saved = file('t.mp3');
    AudioLibrary.i.books.addAll([
      Audiobook(id: 'files', title: 'Files', tracks: [AudioTrack(title: 't', path: '${dir.path}/never.mp3')]),
      Audiobook(id: 'dl', title: 'Downloaded', source: 'librivox', tracks: [AudioTrack(title: 't', path: saved.path, url: 'https://s/t.mp3')]),
    ]);
    final j = roundTrip();
    File(b.path).deleteSync();
    saved.deleteSync();
    Library.i.books.clear();
    Library.i.highlights.clear();
    AudioLibrary.i.books.clear();

    final r = await Backup.restore(j);
    expect(r.missingBooks, 1);
    expect(Library.i.books, isEmpty);
    expect(Library.i.highlights.single.bookId, 'gone'); // reattaches when the file is re-added
    expect(r.missingAudiobooks, 1);
    expect(AudioLibrary.i.books.single.id, 'dl');
    expect(AudioLibrary.i.books.single.tracks.single.remote, isTrue); // streams again
  });

  test('other files are refused', () async {
    final f = File('${dir.path}/other.json')..writeAsStringSync('{"hello": 1}');
    await expectLater(Backup.read(f.path), throwsA(contains('not an Alexandria backup')));
    final g = File('${dir.path}/bad.json')..writeAsStringSync('nope');
    await expectLater(Backup.read(g.path), throwsA(contains('not valid JSON')));
  });
}

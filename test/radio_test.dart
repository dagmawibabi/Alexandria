import 'dart:convert';
import 'dart:io';

import 'package:alexandria/models/radio.dart';
import 'package:alexandria/services/folders.dart';
import 'package:alexandria/services/library.dart';
import 'package:alexandria/services/radio.dart';
import 'package:alexandria/services/storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

Map<String, dynamic> station(String id, String name, {String url = 'https://s.test/live', String code = 'ET', String tags = 'news,talk,amharic'}) => {
      'stationuuid': id,
      'name': name,
      'url_resolved': url,
      'favicon': 'https://s.test/i.png',
      'country': 'Ethiopia',
      'countrycode': code,
      'tags': tags,
      'language': 'amharic',
      'bitrate': 128,
      'homepage': 'https://s.test',
    };

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final dir = RadioDirectory.i;

  setUp(() {
    final d = Directory.systemTemp.createTempSync('radio');
    Storage.cache = d;
    Storage.data = d;
    dir.stations.clear();
    dir.marks.clear();
    dir.folders.clear();
    dir.recent.clear();
    dir.unreachable = false;
    dir.resetServers();
    Library.i.folders.clear();
  });

  Station sample(String id) => Station.fromDirectory(station(id, 'Station $id'))!;

  test('reads a station from the directory', () {
    final s = Station.fromDirectory(station('1', ' Sheger FM '))!;
    expect(s.name, 'Sheger FM');
    expect(s.tags, ['news', 'talk', 'amharic']);
    expect(s.flag, '🇪🇹');
    expect(s.subtitle, 'news · talk • 🇪🇹 Ethiopia');
    expect(s.bitrate, 128);
  });

  test('plain-http streams and nameless entries are left out', () {
    expect(Station.fromDirectory(station('1', 'A', url: 'http://s.test/live')), isNull);
    expect(Station.fromDirectory(station('1', '  ')), isNull);
  });

  test('a station survives saving', () {
    final s = Station.fromJson(jsonDecode(jsonEncode(sample('1').toJson())));
    expect([s.id, s.name, s.countryCode, s.bitrate], ['1', 'Station 1', 'ET', 128]);
    expect(s.tags, hasLength(3));
  });

  test('browsing asks for what you chose, https only, and removes duplicate names', () async {
    late Uri asked;
    final r = await http.runWithClient(() => dir.browse(name: 'jazz', country: 'ET', tag: 'news'), () => MockClient((req) async {
          asked = req.url;
          return http.Response(jsonEncode([station('1', 'Jazz FM'), station('2', 'jazz fm'), station('3', 'Other')]), 200);
        }));
    expect(asked.queryParameters['name'], 'jazz');
    expect(asked.queryParameters['countrycode'], 'ET');
    expect(asked.queryParameters['tag'], 'news');
    expect(asked.queryParameters['is_https'], 'true');
    expect(r.map((s) => s.id), ['1', '3']);
  });

  test('a server that is down fails over to the next', () async {
    final hosts = <String>[];
    final r = await http.runWithClient(() => dir.browse(), () => MockClient((req) async {
          hosts.add(req.url.host);
          return hosts.length == 1 ? http.Response('no available server', 503) : http.Response(jsonEncode([station('1', 'A')]), 200);
        }));
    expect(hosts.toSet().length, 2);
    expect(r.single.id, '1');
    expect(dir.unreachable, isFalse);
  });

  group('when Radio Browser is down', () {
    Map<String, dynamic> outline(String id, String name, {String? subtext}) => {
          'element': 'outline',
          'type': 'audio',
          'item': 'station',
          'text': name,
          'guide_id': id,
          'URL': 'http://opml.radiotime.com/Tune.ashx?id=$id',
          'image': 'http://cdn-profiles.tunein.com/$id/q.png',
          'subtext': subtext ?? 'Addis Ababa',
          'bitrate': '128',
        };

    Future<T> withTuneIn<T>(Future<T> Function() f, Map<String, dynamic> Function(Uri) tuneIn, {List<Uri>? asked}) => http.runWithClient(f, () => MockClient((req) async {
          asked?.add(req.url);
          return req.url.host.contains('radio-browser') ? http.Response('no available server', 503) : http.Response(jsonEncode(tuneIn(req.url)), 200);
        }));

    test('the top list comes from TuneIn, and says so', () async {
      final r = await withTuneIn(dir.browse, (_) => {'body': [outline('s1', 'Sheger FM'), {'type': 'link', 'text': 'Not a station', 'guide_id': 'c1'}]});
      expect(r.single.id, 'ti:s1');
      expect(r.single.needsResolving, isTrue);
      expect(r.single.favicon, startsWith('https://')); // http images are blocked on phones
      expect(dir.usingFallback, isTrue);
      expect(dir.unreachable, isFalse);
    });

    test('a search goes to TuneIn search', () async {
      final asked = <Uri>[];
      await withTuneIn(() => dir.browse(name: 'jazz'), (_) => {'body': [outline('s1', 'Jazz')]}, asked: asked);
      final q = asked.lastWhere((u) => u.host.contains('radiotime'));
      expect(q.path, '/Search.ashx');
      expect(q.queryParameters['query'], 'jazz');
    });

    test('a country finds its TuneIn region by name, nested stations included', () async {
      final r = await withTuneIn(() => dir.browse(country: 'ET', countryName: 'Ethiopia'), (u) {
        if (u.queryParameters['id'] == 'r101215') return {'body': [{'type': 'link', 'text': 'Ethiopia', 'guide_id': 'r100339'}]};
        if (u.queryParameters['id'] == 'r100339') {
          return {'body': [{'key': 'stations', 'text': 'All Stations', 'children': [outline('s1', 'Sheger'), outline('s2', 'Fana')]}]};
        }
        return {'body': []};
      });
      expect(r.map((s) => s.id), ['ti:s1', 'ti:s2']);
    });

    test('searching within a fallback country narrows it here', () async {
      final r = await withTuneIn(() => dir.browse(country: 'ti:r1', name: 'fana'), (_) => {'body': [outline('s1', 'Sheger'), outline('s2', 'Fana FM')]});
      expect(r.single.id, 'ti:s2');
    });

    test('countries come from TuneIn too, with flags found by name', () async {
      final r = await withTuneIn(dir.countries, (u) => u.queryParameters['id'] == 'r101215' ? {'body': [{'type': 'link', 'text': 'Kenya', 'guide_id': 'r2'}, {'type': 'link', 'text': 'Ethiopia', 'guide_id': 'r1'}]} : {'body': []});
      expect(r.map((c) => c.name), ['Ethiopia', 'Kenya']);
      expect(r.first.code, 'ti:r1');
      expect(r.first.flag, '🇪🇹');
      expect(r.first.count, 0);
    });

    test('later lists do not wait on the dead servers again', () async {
      await withTuneIn(dir.browse, (_) => {'body': []});
      final asked = <Uri>[];
      await withTuneIn(() => dir.browse(name: 'x'), (_) => {'body': []}, asked: asked);
      expect(asked.where((u) => u.host.contains('radio-browser')), isEmpty);
    });

    test('there is only one page, so Load more stops', () async {
      final r = await withTuneIn(() => dir.browse(offset: 60), (_) => {'body': [outline('s1', 'A')]});
      expect(r, isEmpty);
    });
  });

  test('a TuneIn stream prefers https and direct', () {
    expect(RadioDirectory.pickStream({'body': [{'url': 'http://a.test/live', 'is_direct': true}, {'url': 'https://b.test/x.pls', 'is_direct': false}, {'url': 'https://c.test/live', 'is_direct': true}]}), 'https://c.test/live');
    expect(RadioDirectory.pickStream({'body': [{'url': 'http://a.test/live'}]}), isNull);
    expect(RadioDirectory.pickStream({'body': []}), isNull);
  });

  test('every source down says so rather than "no stations"', () async {
    final r = await http.runWithClient(() => dir.browse(name: 'nothing-cached'), () => MockClient((_) async => http.Response('down', 503)));
    expect(r, isEmpty);
    expect(dir.unreachable, isTrue);
  });

  test('results saved from one server still show when that server is down', () async {
    await http.runWithClient(() => dir.browse(country: 'KE'), () => MockClient((_) async => http.Response(jsonEncode([station('1', 'A')]), 200)));
    final r = await http.runWithClient(() => dir.browse(country: 'KE'), () => MockClient((_) async => throw const SocketException('offline')));
    expect(r.single.id, '1');
  });

  test('countries are sorted and empty ones dropped', () async {
    final r = await http.runWithClient(dir.countries, () => MockClient((_) async => http.Response(jsonEncode([
              {'name': 'Kenya', 'iso_3166_1': 'KE', 'stationcount': 40},
              {'name': 'Ethiopia', 'iso_3166_1': 'ET', 'stationcount': 12},
              {'name': 'Nowhere', 'iso_3166_1': 'NW', 'stationcount': 0},
            ]), 200)));
    expect(r.map((c) => c.name), ['Ethiopia', 'Kenya']);
    expect(r.first.flag, '🇪🇹');
  });

  test('favourites toggle and are kept', () {
    final s = sample('1');
    dir.toggleFavorite(s);
    expect(dir.isFavorite('1'), isTrue);
    expect(dir.favorites.single.id, '1');
    dir.toggleFavorite(s);
    expect(dir.favorites, isEmpty);
  });

  test('stations go in the shared folders, and deleting a folder clears them', () {
    final f = Library.i.addFolder('Morning');
    final s = sample('1');
    dir.toggleFolder(s, f.id);
    expect(folderCount(FolderKind.radio, f.id), 1);
    expect(folderContents(f), '1 station');
    expect(unfiledCount(FolderKind.radio), 0);
    Library.i.deleteFolder(f);
    expect(dir.foldersOf('1'), isEmpty);
    expect(dir.stationFor('1'), isNotNull); // the station itself stays
  });

  test('a backup brings stations, marks and folders back, keeping what is here', () {
    final s = sample('1');
    dir.toggleFavorite(s);
    dir.toggleFolder(s, 'f');
    final saved = jsonDecode(jsonEncode(dir.toJson()));
    dir.stations.clear();
    dir.marks.clear();
    dir.folders.clear();
    dir.mergeBackup(saved);
    expect(dir.favorites.single.id, '1');
    expect(dir.foldersOf('1'), ['f']);
    dir.mergeBackup(saved);
    expect(dir.foldersOf('1'), ['f']); // merging twice adds nothing
  });
}

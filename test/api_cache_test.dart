import 'dart:io';

import 'package:alexandria/services/api_cache.dart';
import 'package:alexandria/services/storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  late Directory dir;
  const day = Duration(days: 1);

  setUp(() {
    dir = Directory.systemTemp.createTempSync('api_cache');
    Storage.cache = dir;
  });
  tearDown(() => dir.deleteSync(recursive: true));

  Future<T> withServer<T>(http.Response Function() respond, Future<T> Function() f, void Function() hit) => http.runWithClient(f, () => MockClient((_) async {
        hit();
        return respond();
      }));

  test('a fresh answer is served without touching the network', () async {
    var calls = 0;
    await withServer(() => http.Response('one', 200), () async {
      expect(await ApiCache.get('https://x.test/a', ttl: day), 'one');
      expect(await ApiCache.get('https://x.test/a', ttl: day), 'one');
    }, () => calls++);
    expect(calls, 1);
  });

  test('fresh() goes back to the network', () async {
    var calls = 0;
    await withServer(() => http.Response('v$calls', 200), () async {
      await ApiCache.get('https://x.test/b', ttl: day);
      expect(await ApiCache.fresh(() => ApiCache.get('https://x.test/b', ttl: day)), 'v2');
    }, () => calls++);
    expect(calls, 2);
  });

  test('an old copy backs up a failed request', () async {
    await withServer(() => http.Response('saved', 200), () => ApiCache.get('https://x.test/c', ttl: day), () {});
    var unreachable = false;
    final got = await withServer(() => http.Response('down', 503), () => ApiCache.get('https://x.test/c', ttl: Duration.zero, onUnreachable: () => unreachable = true), () {});
    expect(got, 'saved');
    expect(unreachable, isFalse);
  });

  test('no copy and no connection reports unreachable', () async {
    var unreachable = false;
    final got = await withServer(() => throw const SocketException('offline'), () => ApiCache.get('https://x.test/d', ttl: day, onUnreachable: () => unreachable = true), () {});
    expect(got, isNull);
    expect(unreachable, isTrue);
  });

  test('a 404 is remembered, a rate limit is not', () async {
    var calls = 0;
    await withServer(() => http.Response('', 404), () async {
      expect(await ApiCache.get('https://x.test/e', ttl: day), isNull);
      expect(await ApiCache.get('https://x.test/e', ttl: day), isNull);
    }, () => calls++);
    expect(calls, 1);

    calls = 0;
    await withServer(() => http.Response('slow down', 429), () async {
      await ApiCache.get('https://x.test/f', ttl: day);
      await ApiCache.get('https://x.test/f', ttl: day);
    }, () => calls++);
    expect(calls, 2);
  });
}

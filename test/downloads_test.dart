import 'dart:async';
import 'dart:io';

import 'package:alexandria/services/downloads.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// A pretend server: [respond] gets each request's headers.
Future<T> serve<T>(Future<http.StreamedResponse> Function(http.BaseRequest) respond, Future<T> Function() f) =>
    http.runWithClient(f, () => MockClient.streaming((req, _) => respond(req)));

http.StreamedResponse reply(List<int> body, int code, {Map<String, String> headers = const {}, int? length}) =>
    http.StreamedResponse(Stream.value(body), code, headers: headers, contentLength: length ?? body.length);

/// Sends [first] bytes, then the connection drops.
http.StreamedResponse dropAfter(List<int> first, int total, {Map<String, String> headers = const {}}) {
  final c = StreamController<List<int>>();
  c.add(first);
  c.addError(const SocketException('connection lost'));
  c.close();
  return http.StreamedResponse(c.stream, 200, headers: headers, contentLength: total);
}

void main() {
  late Directory dir;
  late String dest;
  final dl = Downloads.i;
  const url = 'https://x.test/a.mp3';

  setUp(() {
    Downloads.retryDelay = Duration.zero;
    dir = Directory.systemTemp.createTempSync('dl');
    dest = '${dir.path}/a.mp3';
  });
  tearDown(() => dir.deleteSync(recursive: true));

  test('a plain download arrives whole, with no partial file left', () async {
    final ok = await serve((_) async => reply([1, 2, 3], 200), () => dl.fetch('a', url, dest));
    expect(ok, isTrue);
    expect(File(dest).readAsBytesSync(), [1, 2, 3]);
    expect(File('$dest.part').existsSync(), isFalse);
  });

  test('a dropped connection resumes from where it stopped', () async {
    final ranges = <String?>[];
    final ok = await serve((req) async {
      ranges.add(req.headers['Range']);
      if (ranges.length == 1) return dropAfter([1, 2], 4, headers: {'etag': '"v1"'});
      return reply([3, 4], 206, headers: {'content-range': 'bytes 2-3/4'});
    }, () => dl.fetch('a', url, dest));
    expect(ok, isTrue);
    expect(ranges, [null, 'bytes=2-']);
    expect(File(dest).readAsBytesSync(), [1, 2, 3, 4]);
  });

  test('a later launch carries on from the saved partial file', () async {
    File('$dest.part').writeAsBytesSync([1, 2]);
    File('$dest.part.tag').writeAsStringSync('"v1"');
    Map<String, String>? seen;
    final ok = await serve((req) async {
      seen = req.headers;
      return reply([3], 206, headers: {'content-range': 'bytes 2-2/3'});
    }, () => dl.fetch('a', url, dest));
    expect(ok, isTrue);
    expect(seen!['If-Range'], '"v1"');
    expect(File(dest).readAsBytesSync(), [1, 2, 3]);
    expect(File('$dest.part.tag').existsSync(), isFalse);
  });

  test('a server that ignores ranges sends it whole, and nothing is doubled', () async {
    File('$dest.part').writeAsBytesSync([9, 9]);
    final ok = await serve((_) async => reply([1, 2, 3], 200), () => dl.fetch('a', url, dest));
    expect(ok, isTrue);
    expect(File(dest).readAsBytesSync(), [1, 2, 3]);
  });

  test('the wrong range is not appended', () async {
    File('$dest.part').writeAsBytesSync([1, 2]);
    var calls = 0;
    final ok = await serve((_) async {
      calls++;
      return calls == 1 ? reply([7], 206, headers: {'content-range': 'bytes 5-5/9'}) : reply([1, 2, 3], 200);
    }, () => dl.fetch('a', url, dest));
    expect(ok, isTrue);
    expect(File(dest).readAsBytesSync(), [1, 2, 3]);
  });

  test('giving up keeps the partial file for next time', () async {
    final ok = await serve((_) async => dropAfter([1, 2], 9), () => dl.fetch('a', url, dest));
    expect(ok, isFalse);
    expect(File(dest).existsSync(), isFalse);
    expect(File('$dest.part').existsSync(), isTrue);
    expect(dl.gone('a'), isFalse);
  });

  test('a file that no longer exists is not retried', () async {
    var calls = 0;
    final ok = await serve((_) async {
      calls++;
      return reply(const [], 404);
    }, () => dl.fetch('a', url, dest));
    expect(ok, isFalse);
    expect(calls, 1);
    expect(dl.gone('a'), isTrue);
  });

  test('cancelling stops the download and throws the partial file away', () async {
    final body = StreamController<List<int>>();
    final run = serve((_) async => http.StreamedResponse(body.stream, 200, contentLength: 4), () => dl.fetch('a', url, dest));
    await Future.delayed(const Duration(milliseconds: 20));
    body.add([1]);
    await Future.delayed(const Duration(milliseconds: 20));
    dl.cancel('a');
    body.add([2]);
    expect(await run, isFalse);
    expect(dl.cancelled('a'), isTrue);
    expect(File('$dest.part').existsSync(), isFalse);
    await body.close();
  });
}

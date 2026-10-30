import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

import 'storage.dart';

/// Network responses kept on disk, so catalogue pages open instantly, work
/// offline, and only ask the network again once their answer has gone stale.
class ApiCache {
  ApiCache._();

  static const _bypass = #apiCacheBypass;

  /// Runs [f] with the cache's fresh copies ignored (pull to refresh).
  /// Stale copies still back it up if the network fails.
  static Future<T> fresh<T>(Future<T> Function() f) => runZoned(f, zoneValues: {_bypass: true});

  static Directory get _dir => Directory(p.join(Storage.cache.path, 'api'));

  static File _file(String url) => File(p.join(_dir.path, sha1.convert(utf8.encode(url)).toString()));

  /// The body at [url], from cache if younger than [ttl].
  ///
  /// Returns null when there is nothing to show. If the network never answered
  /// and no old copy exists, [onUnreachable] runs, so screens can tell
  /// "couldn't connect" from "nothing found".
  ///
  /// [cacheKey] shares one saved copy between mirrors of the same data; [attempts]
  /// is how many tries before giving up on this address.
  static Future<String?> get(String url, {required Duration ttl, Map<String, String>? headers, Duration timeout = const Duration(seconds: 25), void Function()? onUnreachable, String? cacheKey, int attempts = 2}) async {
    final f = _file(cacheKey ?? url);
    final exists = await f.exists();
    if (exists && Zone.current[_bypass] != true && DateTime.now().difference(await f.lastModified()) < ttl) {
      final body = await f.readAsString();
      return body.isEmpty ? null : body;
    }

    var answered = false;
    for (var attempt = 0; attempt < attempts && !answered; attempt++) {
      try {
        final r = await http.get(Uri.parse(url), headers: headers).timeout(timeout);
        if (r.statusCode == 200) {
          final body = utf8.decode(r.bodyBytes, allowMalformed: true);
          await _store(f, body);
          return body;
        }
        if (r.statusCode == 404) {
          // A definite "no such thing" is worth remembering too.
          await _store(f, '');
          return null;
        }
        // Other 4xx (rate limits) are real answers but must not overwrite good data.
        if (r.statusCode < 500) answered = true;
      } catch (_) {}
    }
    if (exists) {
      final body = await f.readAsString();
      if (body.isNotEmpty) return body;
    }
    if (!answered) onUnreachable?.call();
    return null;
  }

  static Future<void> _store(File f, String body) async {
    await f.parent.create(recursive: true);
    final tmp = File('${f.path}.tmp');
    await tmp.writeAsString(body, flush: true);
    await tmp.rename(f.path);
  }

  /// Drops anything not refreshed in a month.
  static Future<void> prune() async {
    final dir = _dir;
    if (!await dir.exists()) return;
    final cutoff = DateTime.now().subtract(const Duration(days: 30));
    await for (final e in dir.list()) {
      if (e is File && (await e.lastModified()).isBefore(cutoff)) e.delete().ignore();
    }
  }
}

import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

import '../core/settings.dart';

/// Background downloads with progress, shared by audiobooks and podcasts.
///
/// Each job has a key (an audiobook id, an episode guid…); [progress] maps
/// running keys to 0..1, or -1 while the size is unknown.
class Downloads extends ChangeNotifier {
  Downloads._();
  static final Downloads i = Downloads._();

  final Map<String, double> progress = {};
  final Set<String> _cancelled = {};

  /// What each running job is, for the notification and the downloads page.
  final Map<String, String> labels = {};

  /// Bytes, speed and retries of each running single-file job, for the downloads page.
  final Map<String, DownloadStat> stats = {};

  static const _channel = MethodChannel('alexandria/downloads');
  bool _handlerSet = false;
  DateTime _lastPush = DateTime(0);
  bool _serviceOn = false;

  /// Keeps the app alive and shows progress while anything is downloading.
  void _syncService({bool force = false}) {
    if (!Platform.isAndroid) return;
    if (!_handlerSet) {
      _handlerSet = true;
      _channel.setMethodCallHandler((call) async {
        if (call.method == 'cancelAll') progress.keys.toList().forEach(cancel);
      });
    }
    if (progress.isEmpty) {
      if (_serviceOn) _channel.invokeMethod('stop').catchError((_) {});
      _serviceOn = false;
      return;
    }
    // Android rate-limits notification updates, and once a second is plenty.
    final now = DateTime.now();
    if (!force && _serviceOn && now.difference(_lastPush).inMilliseconds < 1000) return;
    _lastPush = now;
    _serviceOn = true;
    final known = progress.values.where((v) => v >= 0);
    final percent = known.isEmpty ? -1 : (known.reduce((a, b) => a + b) / known.length * 100).round();
    final n = progress.length;
    _channel.invokeMethod('update', {
      'title': n == 1 ? (labels[progress.keys.first] ?? 'Downloading') : 'Downloading $n items',
      'text': percent < 0 ? 'Alexandria' : '$percent%',
      'percent': percent,
    }).catchError((_) {});
  }

  bool running(String key) => progress.containsKey(key);

  void cancel(String key) {
    if (running(key)) _cancelled.add(key);
  }

  bool cancelled(String key) => _cancelled.contains(key);

  /// Jobs run as part of a batch: cancelling the batch cancels them too.
  final Map<String, String> _batchOf = {};

  void joinBatch(String key, String batch) => _batchOf[key] = batch;

  void leaveBatch(String key) => _batchOf.remove(key);

  bool _stopped(String key) => _cancelled.contains(key) || (_batchOf[key] != null && _cancelled.contains(_batchOf[key]));

  /// For jobs made of several files: report overall progress under [key].
  void report(String key, double? v, {String? label}) {
    final starting = v != null && !progress.containsKey(key);
    if (label != null) labels[key] = label;
    if (v == null) {
      progress.remove(key);
      labels.remove(key);
      stats.remove(key);
    } else {
      if (starting) _cancelled.remove(key);
      progress[key] = v;
    }
    notifyListeners();
    _syncService(force: starting || v == null);
  }

  /// Waits between attempts after a dropped connection.
  static Duration retryDelay = const Duration(seconds: 4);
  static const _attempts = 5;

  final Set<String> _gone = {};

  /// The server said this file doesn't exist any more, so retrying is pointless.
  bool gone(String key) => _gone.contains(key);

  /// Saves [url] to [dest], resuming wherever an earlier try stopped: a dropped
  /// connection retries by itself, and what arrived stays in `dest.part` for next
  /// time, even after the app closes. Cancelling discards it.
  ///
  /// With [onProgress] the caller reports progress itself (under its own key);
  /// otherwise it is shown under [key]. Returns false on failure or when
  /// [cancelKey] (default [key]) is cancelled.
  Future<bool> fetch(String key, String url, String dest, {void Function(double)? onProgress, String? cancelKey, String? label}) async {
    final stop = cancelKey ?? key;
    _gone.remove(key);
    if (onProgress == null) report(key, 0, label: label);
    final part = File('$dest.part');
    final tag = File('$dest.part.tag');
    Future<void> discard() async {
      if (await part.exists()) await part.delete();
      if (await tag.exists()) await tag.delete();
    }

    try {
      await part.parent.create(recursive: true);
      for (var attempt = 0; attempt < _attempts; attempt++) {
        if (attempt > 0) await Future.delayed(retryDelay);
        if (_stopped(stop)) break;
        if (attempt > 0) {
          (stats[key] ??= DownloadStat()).attempt = attempt + 1;
          notifyListeners();
        }
        final result = await _attempt(key, url, part, tag, stop, onProgress);
        if (result == _Attempt.done) {
          await part.rename(dest);
          if (await tag.exists()) await tag.delete();
          return true;
        }
        if (result == _Attempt.gone) {
          _gone.add(key);
          await discard();
          return false;
        }
        if (result == _Attempt.cancelled) break;
      }
      if (_stopped(stop)) await discard();
      return false;
    } catch (_) {
      return false;
    } finally {
      stats.remove(key);
      if (onProgress == null) report(key, null);
    }
  }

  Future<_Attempt> _attempt(String key, String url, File part, File tag, String stop, void Function(double)? onProgress) async {
    final client = http.Client();
    IOSink? sink;
    try {
      var have = await part.exists() ? await part.length() : 0;
      final req = http.Request('GET', Uri.parse(url));
      if (have > 0) {
        req.headers['Range'] = 'bytes=$have-';
        // Only continue if it's still the same file; otherwise the server sends it whole.
        if (await tag.exists()) req.headers['If-Range'] = await tag.readAsString();
      }
      final res = await client.send(req).timeout(const Duration(seconds: 30));
      final code = res.statusCode;
      if (code == 416) {
        // Our partial copy doesn't fit this file: start again.
        await part.delete();
        return _Attempt.retry;
      }
      if (code == 404 || code == 410) return _Attempt.gone;
      if (code != 200 && code != 206) return _Attempt.retry;

      var total = res.contentLength ?? 0;
      if (code == 206) {
        final range = RegExp(r'bytes (\d+)-\d+/(\d+|\*)').firstMatch(res.headers['content-range'] ?? '');
        if (range == null || int.parse(range[1]!) != have) {
          // Not the bytes we asked for: appending them would corrupt the file.
          await part.delete();
          return _Attempt.retry;
        }
        total = int.tryParse(range[2]!) ?? (total > 0 ? have + total : 0);
      } else {
        have = 0; // the whole file, from the top
        final etag = res.headers['etag'];
        final stamp = etag != null && !etag.startsWith('W/') ? etag : res.headers['last-modified'];
        if (stamp != null) await tag.writeAsString(stamp);
      }

      sink = part.openWrite(mode: have > 0 ? FileMode.append : FileMode.write);
      var got = have;
      var last = -1.0;
      final stat = (stats[key] ??= DownloadStat())
        ..got = have
        ..total = total;
      await for (final chunk in res.stream.timeout(const Duration(seconds: 45))) {
        if (_stopped(stop)) return _Attempt.cancelled;
        sink.add(chunk);
        got += chunk.length;
        stat.add(got);
        final v = total > 0 ? got / total : -1.0;
        if (v < 0 || v - last >= .01) {
          last = v;
          onProgress != null ? onProgress(v) : report(key, v);
        }
      }
      return total > 0 && got < total ? _Attempt.retry : _Attempt.done;
    } catch (_) {
      return _Attempt.retry;
    } finally {
      await sink?.close();
      client.close();
    }
  }

  // ---------------- jobs that outlive the app ----------------

  /// Downloads to pick up next launch: `book:<id>`, `track:<id>#<n>`, `ep:<guid>`.
  void remember(String job) {
    final jobs = Settings.i.pendingDownloads;
    if (!jobs.contains(job)) Settings.i.pendingDownloads = [...jobs, job];
  }

  void forget(String job) {
    final jobs = Settings.i.pendingDownloads;
    if (jobs.contains(job)) Settings.i.pendingDownloads = [...jobs]..remove(job);
  }

  /// Forgets a finished job. A failed one stays, to try again next launch.
  void settle(String job, String key, bool ok) {
    if (ok || cancelled(key) || gone(key)) forget(job);
  }
}

enum _Attempt { done, retry, gone, cancelled }

/// How one file's download is going.
class DownloadStat {
  int got = 0;

  /// 0 while the size is unknown.
  int total = 0;

  /// Bytes a second, smoothed so the figure doesn't jump about.
  double rate = 0;

  /// 1 on the first try; higher after a dropped connection.
  int attempt = 1;

  int _lastBytes = 0;
  DateTime? _lastAt;

  void add(int bytes) {
    final now = DateTime.now();
    final at = _lastAt;
    got = bytes;
    if (at == null) {
      _lastAt = now;
      _lastBytes = bytes;
      return;
    }
    final ms = now.difference(at).inMilliseconds;
    // Sampled every half second: chunks arrive far too often to time one by one.
    if (ms < 500) return;
    final r = (bytes - _lastBytes) * 1000 / ms;
    rate = rate == 0 ? r : rate * .7 + r * .3;
    _lastAt = now;
    _lastBytes = bytes;
  }

  /// Time left at the current speed, or null when it can't be told.
  Duration? get left => total > 0 && rate > 1 ? Duration(seconds: ((total - got) / rate).round()) : null;
}

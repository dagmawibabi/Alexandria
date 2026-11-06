import 'dart:async';
import 'dart:io';

import 'package:audio_session/audio_session.dart';
import 'package:just_audio/just_audio.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../core/settings.dart';
import '../models/audiobook.dart';
import '../models/book.dart';
import 'backup.dart';
import 'downloads.dart';
import 'free_audio.dart';
import 'library.dart';
import 'metadata.dart';
import 'podcasts.dart';
import 'read_aloud.dart';
import 'storage.dart';

/// The audiobook shelf: your own audio files, plus streamed free books.
class AudioLibrary extends ChangeNotifier {
  AudioLibrary._();
  static final AudioLibrary i = AudioLibrary._();

  final List<Audiobook> books = [];

  /// Copy progress (0..1) while audio files are being added; null when idle.
  final ValueNotifier<double?> importing = ValueNotifier(null);

  Directory get _root => Directory(p.join(Storage.root.path, 'audio'));

  Future<void> load() async {
    final j = await Storage.readJson('audiobooks');
    if (j is List) books.addAll(j.whereType<Map>().map((e) => Audiobook.fromJson(Map<String, dynamic>.from(e))));
    notifyListeners();
  }

  /// Merges a backup's audiobooks. Streamed ones always come back; ones made from
  /// files need those files to still be here.
  void mergeBackup(dynamic list, ImportResult r) {
    if (list is! List) return;
    for (final b in list.whereType<Map>().map((e) => Audiobook.fromJson(Map<String, dynamic>.from(e)))) {
      // A download whose file is gone goes back to streaming.
      for (final t in b.tracks) {
        if (t.downloaded && !File(t.path).existsSync()) {
          t.path = t.url!;
          t.url = null;
        }
      }
      if (b.coverPath != null && !File(b.coverPath!).existsSync()) b.coverPath = null;
      final at = books.indexWhere((x) => x.id == b.id);
      if (at >= 0) {
        final mine = books[at];
        if ((b.lastPlayedAt ?? b.addedAt).isAfter(mine.lastPlayedAt ?? mine.addedAt) && Player.i.book?.id != b.id) books[at] = b;
        continue;
      }
      if (b.tracks.any((t) => !t.remote && !File(t.path).existsSync())) {
        r.missingAudiobooks++;
        continue;
      }
      books.add(b);
      r.audiobooks++;
    }
    if (books.isNotEmpty) touch(books.first);
  }

  Timer? _pending;

  void touch(Audiobook b) {
    _pending?.cancel();
    _pending = Timer(const Duration(milliseconds: 400), () => Storage.writeJson('audiobooks', books.map((e) => e.toJson()).toList()));
    notifyListeners();
  }

  Audiobook? byId(String id) => books.where((b) => b.id == id).firstOrNull;

  /// Most recently played first.
  List<Audiobook> get recent => [...books]..sort((a, b) => (b.lastPlayedAt ?? b.addedAt).compareTo(a.lastPlayedAt ?? a.addedAt));

  /// Makes an audiobook from picked files. They are copied into app storage,
  /// because the picker's copies live in a cache the system may clear.
  Future<Audiobook> createLocal({
    required List<({String path, String name})> files,
    required String title,
    String author = '',
    String description = '',
    String year = '',
    String? coverUrl,
    String? coverFile,
  }) async {
    final id = newId();
    final dir = Directory(p.join(_root.path, id));
    await dir.create(recursive: true);
    final tracks = <AudioTrack>[];
    importing.value = 0;
    try {
      for (var n = 0; n < files.length; n++) {
        final f = files[n];
        final dest = p.join(dir.path, '${n.toString().padLeft(3, '0')}_${p.basename(f.name)}');
        await File(f.path).copy(dest);
        tracks.add(AudioTrack(title: cleanTrackTitle(f.name), path: dest));
        importing.value = (n + 1) / files.length;
      }
    } finally {
      importing.value = null;
    }
    final b = Audiobook(id: id, title: title, author: author, description: description, year: year, tracks: tracks, coverUrl: coverUrl);
    if (coverFile != null) {
      b.coverPath = await _saveCoverFile(id, coverFile);
    } else if (coverUrl != null) {
      b.coverPath = await _downloadCover(id, coverUrl);
    }
    books.add(b);
    touch(b);
    unawaited(probeDurations(b));
    return b;
  }

  /// Adds a free catalogue book (streamed). Returns the existing one if already shelved.
  Future<Audiobook> addFree(FreeAudiobook f, List<AudioTrack> tracks) async {
    final existing = books.where((b) => b.source == f.source && b.sourceKey == f.key).firstOrNull;
    if (existing != null) return existing;
    final b = Audiobook(
      id: newId(),
      title: f.title,
      author: f.author,
      description: f.description,
      year: f.year,
      tracks: tracks,
      coverUrl: f.coverUrl,
      source: f.source,
      sourceKey: f.key,
    );
    books.add(b);
    touch(b);
    return b;
  }

  bool shelved(FreeAudiobook f) => books.any((b) => b.source == f.source && b.sourceKey == f.key);

  /// Applies a catalogue record (title, author, description, cover).
  Future<void> applyInfo(Audiobook b, BookInfo info) async {
    if (info.title.isNotEmpty) b.title = info.title;
    if (info.author.isNotEmpty) b.author = info.author;
    if (info.description.isNotEmpty) b.description = info.description;
    if (info.year.isNotEmpty) b.year = info.year;
    if (info.coverUrl != null) {
      b.coverUrl = info.coverUrl;
      b.coverPath = await _downloadCover(b.id, info.coverUrl!) ?? b.coverPath;
    }
    touch(b);
  }

  Future<void> setCover(Audiobook b, String file) async {
    b.coverPath = await _saveCoverFile(b.id, file);
    touch(b);
  }

  Future<void> remove(Audiobook b) async {
    if (Player.i.book?.id == b.id) await Player.i.close();
    books.removeWhere((x) => x.id == b.id);
    touch(b);
    final dir = Directory(p.join(_root.path, b.id));
    if (await dir.exists()) await dir.delete(recursive: true);
    if (b.coverPath != null) File(b.coverPath!).delete().ignore();
  }

  Future<String?> _downloadCover(String id, String url) async {
    final bytes = await Metadata.download(url);
    if (bytes == null || bytes.length < 2000) return null;
    final c = File(p.join(Storage.covers.path, 'audio-$id-${DateTime.now().millisecondsSinceEpoch}.img'));
    await c.writeAsBytes(bytes);
    return c.path;
  }

  Future<String> _saveCoverFile(String id, String file) async {
    final c = File(p.join(Storage.covers.path, 'audio-$id-${DateTime.now().millisecondsSinceEpoch}.img'));
    await File(file).copy(c.path);
    return c.path;
  }

  // ---------------- downloads ----------------

  String _trackDest(Audiobook b, int n) {
    final ext = RegExp(r'\.(mp3|m4a|m4b|ogg|opus|aac|wav)(\?|$)', caseSensitive: false).firstMatch(b.tracks[n].path)?.group(1) ?? 'mp3';
    return p.join(_root.path, b.id, '${n.toString().padLeft(3, '0')}.$ext');
  }

  void _trackSaved(Audiobook b, int n, String dest) {
    final t = b.tracks[n];
    t.url = t.path;
    t.path = dest;
    touch(b);
  }

  static String trackKey(Audiobook b, int n) => '${b.id}#$n';

  /// Saves a streamed book's tracks to the device, one after another.
  /// Progress shows in [Downloads] under the book's id.
  Future<bool> download(Audiobook b) async {
    final todo = [for (var n = 0; n < b.tracks.length; n++) if (b.tracks[n].remote && !Downloads.i.running(trackKey(b, n))) n];
    if (todo.isEmpty || Downloads.i.running(b.id)) return true;
    final job = 'book:${b.id}';
    Downloads.i.remember(job);
    var done = 0;
    var ok = false;
    Downloads.i.report(b.id, 0, label: b.title);
    // Keep the cover too, for the shelf and the notification when offline.
    if (b.coverPath == null && b.coverUrl != null) b.coverPath = await _downloadCover(b.id, b.coverUrl!);
    try {
      for (final n in todo) {
        final dest = _trackDest(b, n);
        final saved = await Downloads.i.fetch(b.id, b.tracks[n].path, dest, onProgress: (v) => Downloads.i.report(b.id, (done + (v < 0 ? 0 : v)) / todo.length));
        if (!saved) return false;
        _trackSaved(b, n, dest);
        done++;
      }
      ok = true;
      return true;
    } finally {
      Downloads.i.settle(job, b.id, ok);
      Downloads.i.report(b.id, null);
    }
  }

  /// Saves one chapter.
  Future<bool> downloadTrack(Audiobook b, int n) async {
    final key = trackKey(b, n);
    if (!b.tracks[n].remote || Downloads.i.running(key) || Downloads.i.running(b.id)) return true;
    final job = 'track:$key';
    Downloads.i.remember(job);
    if (b.coverPath == null && b.coverUrl != null) b.coverPath = await _downloadCover(b.id, b.coverUrl!);
    final dest = _trackDest(b, n);
    final ok = await Downloads.i.fetch(key, b.tracks[n].path, dest, label: '${b.title}: ${b.tracks[n].title}');
    if (ok) _trackSaved(b, n, dest);
    Downloads.i.settle(job, key, ok);
    return ok;
  }

  /// Deletes one downloaded chapter; it streams again.
  Future<void> removeTrackDownload(Audiobook b, int n) async {
    final t = b.tracks[n];
    if (!t.downloaded) return;
    final f = File(t.path);
    t.path = t.url!;
    t.url = null;
    if (await f.exists()) await f.delete();
    touch(b);
  }

  /// Picks up downloads that were running when the app last closed.
  void resumeDownloads() {
    for (final job in Settings.i.pendingDownloads) {
      if (job.startsWith('book:')) {
        final b = byId(job.substring(5));
        b == null ? Downloads.i.forget(job) : download(b);
      } else if (job.startsWith('track:')) {
        final at = job.lastIndexOf('#');
        final b = byId(job.substring(6, at));
        final n = int.tryParse(job.substring(at + 1)) ?? -1;
        b == null || n < 0 || n >= b.tracks.length ? Downloads.i.forget(job) : downloadTrack(b, n);
      } else if (job.startsWith('ep:')) {
        final e = Podcasts.i.states[job.substring(3)]?.episode;
        e == null ? Downloads.i.forget(job) : Podcasts.i.download(e);
      }
    }
  }

  /// Deletes downloaded tracks; they stream again from where they came from.
  Future<void> removeDownload(Audiobook b) async {
    for (final t in b.tracks.where((t) => t.downloaded)) {
      final f = File(t.path);
      t.path = t.url!;
      t.url = null;
      if (await f.exists()) await f.delete();
    }
    touch(b);
  }

  // ---------------- the book's text ----------------

  /// A folder was deleted: no audiobook is in it any more.
  void removeFolder(String folderId) {
    for (final b in books.where((b) => b.folderIds.contains(folderId))) {
      b.folderIds = [...b.folderIds]..remove(folderId);
    }
    if (books.isNotEmpty) touch(books.first);
  }

  void toggleFolder(Audiobook b, String folderId) {
    b.folderIds = b.folderIds.contains(folderId) ? ([...b.folderIds]..remove(folderId)) : [...b.folderIds, folderId];
    touch(b);
  }

  void linkBook(Audiobook b, Book? book) {
    b.bookId = book?.id;
    touch(b);
  }

  Book? bookFor(Audiobook b) => b.bookId == null ? null : Library.i.byId(b.bookId!);

  /// Finds the public-domain text on Project Gutenberg, adds it to the library
  /// and links it. Null if no confident match.
  Future<Book?> attachFreeText(Audiobook b) async {
    String norm(String s) => s.toLowerCase().replaceAll(RegExp(r'\(.*?\)|[^a-z0-9 ]'), ' ').replaceAll(RegExp(r'\s+'), ' ').trim();
    final want = norm(b.title);
    if (want.isEmpty) return null;
    final last = b.author.split(',').first.trim().split(' ').last.toLowerCase();
    final hits = await Metadata.gutenberg([b.title, last].where((s) => s.isNotEmpty).join(' '));
    final hit = hits.where((h) {
      final got = norm(h.title);
      final sameTitle = got == want || got.startsWith('$want ') || want.startsWith('$got ');
      return h.downloadUrl != null && sameTitle && (last.isEmpty || h.author.toLowerCase().contains(last));
    }).firstOrNull;
    if (hit == null) return null;
    final have = Library.i.books.where((x) => norm(x.title) == norm(hit.title)).firstOrNull;
    if (have != null) {
      linkBook(b, have);
      return have;
    }
    final bytes = await Metadata.download(hit.downloadUrl!);
    if (bytes == null) return null;
    final f = File(p.join(Storage.cache.path, '${hit.key.replaceAll(':', '_')}.epub'));
    await f.writeAsBytes(bytes);
    final book = await Library.i.importFile(f.path, displayName: '${hit.title}.epub');
    if (hit.coverUrl != null && book.coverPath == null) {
      await Library.i.enrich(book, onlyMissing: true, choice: BookInfo(title: book.title, author: hit.author, coverUrl: hit.coverUrl, subjects: hit.subjects));
    }
    linkBook(b, book);
    return book;
  }

  /// Reads each local track's length so progress and time-left are exact.
  Future<void> probeDurations(Audiobook b) async {
    final todo = b.tracks.where((t) => t.ms == 0 && !t.remote).toList();
    if (todo.isEmpty) return;
    final probe = AudioPlayer();
    try {
      for (final t in todo) {
        try {
          final d = await probe.setFilePath(t.path);
          if (d != null && d > Duration.zero) t.ms = d.inMilliseconds;
        } catch (_) {}
      }
    } finally {
      await probe.dispose();
    }
    touch(b);
  }
}

/// Audiobook playback: one book at a time, remembering position per book.
///
/// Built on just_audio (ExoPlayer on Android), which starts a stream after a
/// short buffer and seeks inside remote files with range requests. Android's
/// MediaPlayer, used before, buffered far more before starting and crawled
/// when resuming a podcast halfway through.
class Player extends ChangeNotifier {
  Player._();

  static final Player i = Player._();

  AudioPlayer? _player;

  /// Made on first use, so nothing touches the platform until something plays.
  AudioPlayer get _p => _player ??= _create();

  AudioPlayer _create() {
    final p = AudioPlayer();
    // Spoken word: ducks under notifications, pauses for calls.
    AudioSession.instance.then((s) => s.configure(const AudioSessionConfiguration.speech())).ignore();
    p.durationStream.listen((d) {
      if (d == null || _loadingSource) return;
      duration = d;
      final t = current;
      if (t != null && d > Duration.zero && book?.source != 'radio' && (t.ms - d.inMilliseconds).abs() > 1000) {
        t.ms = d.inMilliseconds;
        _save();
      }
      notifyListeners();
    });
    p.playerStateStream.listen((s) {
      final done = s.processingState == ProcessingState.completed;
      final was = playing;
      playing = s.playing && !done;
      _buffering = s.processingState == ProcessingState.loading || s.processingState == ProcessingState.buffering;
      if (playing) {
        _startTicker();
      } else {
        _stopTicker();
        if (was) {
          _lastTick = null;
          _logListening();
          _save();
        }
      }
      notifyListeners();
      if (done && _loaded && !_loadingSource && !_completedHandled) {
        _completedHandled = true;
        _ended();
      }
    }, onError: (_) {});
    // A stream that drops mid-play; errors while opening are caught in _load.
    p.errorStream.listen((e) {
      final t = current;
      if (t == null || _loadingSource) return;
      error = t.remote ? 'Lost the stream. Check your connection and press play.' : 'Could not play this file.';
      _loaded = false;
      notifyListeners();
    });
    p.playbackEventStream.listen((_) {}, onError: (_) {});
    return p;
  }

  // Position ticks from a timer, not screen frames, which stop with the screen
  // off: saved positions, stats and the notification all rely on it while locked.
  Timer? _ticker;

  void _startTicker() => _ticker ??= Timer.periodic(const Duration(milliseconds: 400), (_) => _tick());

  void _stopTicker() {
    if (_ticker == null) return;
    _ticker!.cancel();
    _ticker = null;
    // One last read, so a pause lands on the exact spot.
    _tick();
  }

  void _tick() {
    final b = book;
    if (b == null || !_loaded || _loadingSource) return;
    final d = _p.position;
    position = d;
    b.positionMs = d.inMilliseconds;
    _tickListening();
    if (DateTime.now().difference(_lastSave).inSeconds >= 5) _save();
    _ticks.ping();
    // Everyone else hears about the position every couple of seconds: the
    // pages listening here show percentages and minutes left, not seconds.
    if (DateTime.now().difference(_lastNotified) >= const Duration(seconds: 2)) notifyListeners();
  }

  final _ticks = _Ticks();
  DateTime _lastNotified = DateTime(0);

  /// Fires on every position update (a few times a second) as well as on every
  /// change the player itself announces. For what shows the exact playing
  /// position: the seek bar, the mini player's progress line, read-along.
  /// Listening to the player itself gets changes at once but the position only
  /// every two seconds, which keeps whole pages from redrawing as it plays.
  late final Listenable ticks = Listenable.merge([this, _ticks]);

  @override
  void notifyListeners() {
    _lastNotified = DateTime.now();
    super.notifyListeners();
  }

  bool _completedHandled = false;
  bool _buffering = false;
  bool _loadingSource = false;

  Audiobook? book;
  Duration position = Duration.zero;
  Duration duration = Duration.zero;
  bool playing = false;
  String? error;

  /// Opening a source, or waiting on the network mid-play.
  bool get loading => _loadingSource || (_buffering && _loaded);

  /// When the sleep timer stops playback, or null.
  DateTime? sleepAt;

  /// Sleep at the end of the current chapter instead of after a time.
  bool sleepAtTrackEnd = false;

  Timer? _sleep;

  // Real listening time not yet recorded in the stats.
  double _unlogged = 0;
  DateTime? _lastTick;
  Audiobook? _unloggedBook;

  void _tickListening() {
    final now = DateTime.now();
    final last = _lastTick;
    _lastTick = playing ? now : null;
    if (last == null) return;
    final dt = now.difference(last).inMilliseconds / 1000;
    // Long gaps are the app being suspended or a stall, not listening.
    if (dt > 0 && dt < 5) _unlogged += dt;
    _unloggedBook = book;
    if (_unlogged >= 30) _logListening();
  }

  void _logListening() {
    final b = _unloggedBook;
    final secs = _unlogged.floor();
    if (b == null || secs < 1) return;
    _unlogged -= secs;
    if (b.source == 'radio') {
      Library.i.addListening('radio:${b.sourceKey}', 'radio', b.title, secs);
    } else if (b.source == 'podcast') {
      final feed = Podcasts.i.episodeFor(b)?.feedUrl ?? b.author;
      Library.i.addListening('pod:$feed', 'podcast', b.author, secs);
    } else {
      Library.i.addListening(b.id, 'audiobook', b.title, secs);
    }
  }

  bool _loaded = false;
  DateTime _lastSave = DateTime(0);

  AudioTrack? get current {
    final b = book;
    if (b == null || b.tracks.isEmpty) return null;
    return b.tracks[b.trackIndex.clamp(0, b.tracks.length - 1)];
  }

  /// Plays [b] from where it was left, or from [track] if given.
  Future<void> open(Audiobook b, {bool play = true, int? track}) async {
    if (play && ReadAloud.i.active) await ReadAloud.i.stop();
    if (book?.id == b.id && track == null && _loaded) {
      if (play && !playing) await resume();
      return;
    }
    if (book != null) {
      _logListening();
      _save();
    }
    book = b;
    error = null;
    if (track != null) {
      b.trackIndex = track;
      b.positionMs = 0;
    }
    if (b.finished) {
      b.finished = false;
      b.trackIndex = 0;
      b.positionMs = 0;
    }
    await _load(play: play);
  }

  /// Shows why [b] can't play, without playing it.
  Future<void> fail(Audiobook b, String why) async {
    if (playing) await _p.stop();
    book = b;
    _loaded = false;
    _loadingSource = false;
    playing = false;
    error = why;
    notifyListeners();
  }

  Future<void> _load({required bool play}) async {
    final b = book;
    final t = current;
    if (b == null || t == null) return;
    // Live radio always joins at now.
    if (b.source == 'radio') b.positionMs = 0;
    _loadingSource = true;
    _loaded = false;
    _completedHandled = false;
    position = Duration(milliseconds: b.positionMs);
    duration = Duration(milliseconds: t.ms);
    notifyListeners();
    try {
      // A new source inherits "playing"; only start it when asked to.
      if (!play && _p.playing) await _p.pause();
      await _p.setSpeed(b.speed);
      // Opening at the saved spot is one request; loading and then seeking was two.
      final source = t.remote ? AudioSource.uri(Uri.parse(t.path)) : AudioSource.file(t.path);
      final d = await _p.setAudioSource(source, initialPosition: b.positionMs > 0 ? Duration(milliseconds: b.positionMs) : null);
      // Something else was opened while this one loaded.
      if (!identical(book, b) || !identical(current, t)) return;
      _loaded = true;
      error = null;
      if (d != null && d > Duration.zero) {
        duration = d;
        if (b.source != 'radio' && (t.ms - d.inMilliseconds).abs() > 1000) t.ms = d.inMilliseconds;
      }
      // play() completes only when playback stops, so it isn't awaited.
      if (play) _p.play().ignore();
    } catch (e) {
      if (!identical(book, b)) return;
      error = t.remote ? 'Could not stream this. Check your connection.' : 'Could not play this file: $e';
      _loaded = false;
    } finally {
      if (identical(book, b) && identical(current, t)) _loadingSource = false;
      notifyListeners();
    }
  }

  Future<void> toggle() => playing ? pause() : resume();

  Future<void> resume() async {
    if (book == null) return;
    if (ReadAloud.i.active) await ReadAloud.i.stop();
    // Resuming live radio reconnects, rather than playing what was buffered at pause.
    if (!_loaded || book!.source == 'radio') return _load(play: true);
    // At the very end: play from the top again.
    if (_p.processingState == ProcessingState.completed) {
      _completedHandled = false;
      await _p.seek(Duration.zero);
    }
    _p.play().ignore();
  }

  Future<void> pause() async {
    if (_player == null) return;
    await _p.pause();
    _save();
  }

  Future<void> seek(Duration d) async {
    final b = book;
    if (b == null) return;
    final max = duration > Duration.zero ? duration : Duration(milliseconds: current?.ms ?? 0);
    final to = d < Duration.zero ? Duration.zero : (max > Duration.zero && d > max ? max : d);
    position = to;
    b.positionMs = to.inMilliseconds;
    notifyListeners();
    if (_loaded) {
      _completedHandled = false;
      await _p.seek(to);
    }
    _save();
  }

  /// Skips by [seconds], crossing into the next or previous chapter if needed.
  Future<void> skip(int seconds) async {
    final b = book;
    if (b == null || b.source == 'radio') return;
    final to = position + Duration(seconds: seconds);
    if (duration > Duration.zero && to > duration && b.trackIndex < b.tracks.length - 1) return next();
    if (to < Duration.zero && seconds < 0 && b.trackIndex > 0 && position.inSeconds < 2) return previous();
    await seek(to);
  }

  Future<void> next() async {
    final b = book;
    if (b == null || b.trackIndex >= b.tracks.length - 1) return;
    await jumpTo(b.trackIndex + 1);
  }

  /// Back to the chapter start, or the previous chapter if already there.
  Future<void> previous() async {
    final b = book;
    if (b == null) return;
    if (position.inSeconds > 3 || b.trackIndex == 0) return seek(Duration.zero);
    await jumpTo(b.trackIndex - 1);
  }

  Future<void> jumpTo(int track) async {
    final b = book;
    if (b == null) return;
    final wasPlaying = playing || !_loaded;
    b.trackIndex = track.clamp(0, b.tracks.length - 1);
    b.positionMs = 0;
    b.finished = false;
    await _load(play: wasPlaying);
    _save();
  }

  /// Goes to a saved moment (a note), switching chapter if needed.
  Future<void> goTo(int track, int ms) async {
    final b = book;
    if (b == null) return;
    if (track == b.trackIndex) return seek(Duration(milliseconds: ms));
    b.trackIndex = track.clamp(0, b.tracks.length - 1);
    b.positionMs = ms;
    b.finished = false;
    await _load(play: playing);
    _save();
  }

  Future<void> setSpeed(double v) async {
    final b = book;
    if (b == null) return;
    b.speed = v;
    if (_loaded) await _p.setSpeed(v);
    _save();
    notifyListeners();
  }

  /// Stops playback after [after], at the chapter's end ([trackEnd]), or cancels (both null/false).
  void setSleep(Duration? after, {bool trackEnd = false}) {
    _sleep?.cancel();
    sleepAt = null;
    sleepAtTrackEnd = trackEnd;
    if (after != null) {
      sleepAt = DateTime.now().add(after);
      _sleep = Timer(after, () {
        sleepAt = null;
        pause();
        notifyListeners();
      });
    }
    notifyListeners();
  }

  void _ended() {
    final b = book;
    if (b == null) return;
    // just_audio keeps "playing" on at the end; switch it off so the next
    // source doesn't start by itself.
    _p.pause().ignore();
    if (b.source == 'radio') {
      playing = false;
      error = 'This station stopped broadcasting.';
      notifyListeners();
      return;
    }
    if (b.source == 'podcast') {
      playing = false;
      notifyListeners();
      Podcasts.i.finished(b);
      return;
    }
    if (b.trackIndex >= b.tracks.length - 1) {
      b.finished = true;
      b.finishedAt = DateTime.now();
      b.positionMs = 0;
      playing = false;
      _save();
      notifyListeners();
      return;
    }
    final stop = sleepAtTrackEnd;
    sleepAtTrackEnd = false;
    b.trackIndex++;
    b.positionMs = 0;
    _load(play: !stop);
    _save();
  }

  Future<void> close() async {
    _logListening();
    _save();
    _sleep?.cancel();
    sleepAt = null;
    _stopTicker();
    if (_player != null) await _p.stop();
    book = null;
    _loaded = false;
    playing = false;
    notifyListeners();
  }

  void _save() {
    final b = book;
    if (b == null) return;
    _lastSave = DateTime.now();
    b.lastPlayedAt = DateTime.now();
    // Podcast episodes play as one-track books; their progress lives with the podcast.
    if (b.source == 'radio') return; // nothing to resume on a live stream
    b.source == 'podcast' ? Podcasts.i.savePosition(b) : AudioLibrary.i.touch(b);
  }
}

class _Ticks extends ChangeNotifier {
  void ping() => notifyListeners();
}

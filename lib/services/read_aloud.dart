import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../models/book.dart';
import '../models/doc.dart';
import 'audio.dart';
import 'library.dart';
import 'speech.dart';

/// Reading a book aloud, paragraph after paragraph.
///
/// Lives outside the reader screen so it carries on when you leave the reader or
/// lock the phone, and so the notification can control it.
class ReadAloud extends ChangeNotifier {
  ReadAloud._();
  static final ReadAloud i = ReadAloud._();

  static const _power = MethodChannel('alexandria/power');

  Book? book;
  ParsedDoc? doc;

  /// The paragraph being read.
  int block = 0;
  bool playing = false;

  /// A cloud voice failed and the device voice took over. Cleared once shown.
  bool fellBack = false;

  int _part = 0;
  int _gen = 0;
  double _unlogged = 0;

  bool get active => book != null;

  bool isOn(Book b) => book?.id == b.id;

  /// How far through the book, by words.
  double get fraction {
    final d = doc;
    if (d == null || d.wordCount == 0) return 0;
    return d.wordOffsets[block.clamp(0, d.blocks.length)] / d.wordCount;
  }

  String get chapter => doc?.chapterAt(block)?.title ?? '';

  /// About how long the whole book takes aloud, for the notification's progress bar.
  Duration get length {
    final words = doc?.wordCount ?? 0;
    return Duration(seconds: (words * 60 / (170 * Speech.rate)).round());
  }

  int _forward(int from) {
    final d = doc!;
    var b = from;
    while (b < d.blocks.length && d.blocks[b].text.trim().isEmpty) {
      b++;
    }
    return b;
  }

  int _back(int from) {
    final d = doc!;
    var b = from;
    while (b > 0 && d.blocks[b].text.trim().isEmpty) {
      b--;
    }
    return b.clamp(0, d.blocks.length - 1);
  }

  void _hold(bool on) {
    if (!Platform.isAndroid) return;
    // Between sentences nothing is playing, so the phone could otherwise sleep and never start the next one.
    _power.invokeMethod(on ? 'hold' : 'release').catchError((_) {});
  }

  Future<void> start(Book b, ParsedDoc d, int from) async {
    if (Player.i.playing) await Player.i.pause();
    await Speech.stop();
    book = b;
    doc = d;
    block = _forward(from);
    _part = 0;
    fellBack = false;
    _run();
  }

  Future<void> _run() async {
    final gen = ++_gen;
    final d = doc;
    final b = book;
    if (d == null || b == null) return;
    playing = true;
    _hold(true);
    Speech.lastError = null;
    notifyListeners();
    try {
      while (gen == _gen) {
        if (block >= d.blocks.length) {
          await stop();
          return;
        }
        _savePosition();
        notifyListeners();
        final parts = Speech.partsOf(d.blocks[block].text);
        while (_part < parts.length) {
          // Have the next clip ready, so cloud voices don't pause between sentences.
          if (_part + 1 < parts.length) {
            Speech.prepare(parts[_part + 1]);
          } else {
            final n = _forward(block + 1);
            if (n < d.blocks.length) Speech.prepare(d.blocks[n].text);
          }
          final started = DateTime.now();
          await Speech.say(parts[_part]);
          if (gen != _gen) return;
          _log(DateTime.now().difference(started));
          if (Speech.lastError != null && !fellBack) {
            fellBack = true;
            notifyListeners();
          }
          _part++;
        }
        block = _forward(block + 1);
        _part = 0;
      }
    } catch (e) {
      debugPrint('[read aloud] $e');
      if (gen == _gen) await pause();
    }
  }

  void _log(Duration d) {
    _unlogged += d.inMilliseconds / 1000;
    if (_unlogged >= 30) _flushLog();
  }

  void _flushLog() {
    final b = book;
    final secs = _unlogged.floor();
    if (b == null || secs < 1) return;
    _unlogged -= secs;
    Library.i.addListening(b.id, 'listen', b.title, secs);
  }

  void _savePosition() {
    final b = book;
    if (b == null) return;
    b.position = block;
    b.positionOffset = 0;
    b.progress = fraction.clamp(0, 1);
    Library.i.touch(b);
  }

  Future<void> toggle() => playing ? pause() : resume();

  /// Picks up at the sentence it stopped on.
  Future<void> pause() async {
    _gen++;
    playing = false;
    _hold(false);
    _flushLog();
    await Speech.stop();
    notifyListeners();
  }

  Future<void> resume() async {
    if (!active) return;
    if (Player.i.playing) await Player.i.pause();
    _run();
  }

  Future<void> _goTo(int to) async {
    final was = playing;
    _gen++;
    await Speech.stop();
    block = to;
    _part = 0;
    _savePosition();
    if (was) {
      _run();
    } else {
      notifyListeners();
    }
  }

  Future<void> next() async {
    if (doc == null) return;
    final n = _forward(block + 1);
    if (n < doc!.blocks.length) await _goTo(n);
  }

  /// Back to this paragraph's start, or the one before if already there.
  Future<void> previous() async {
    if (doc == null) return;
    await _goTo(_part > 0 ? block : _back((block - 1).clamp(0, doc!.blocks.length - 1)));
  }

  /// Jumps to a fraction of the book (the notification's progress bar).
  Future<void> seek(double f) async {
    final d = doc;
    if (d == null || d.wordCount == 0) return;
    final target = f.clamp(0.0, 1.0) * d.wordCount;
    var b = 0;
    while (b + 1 < d.blocks.length && d.wordOffsets[b + 1] <= target) {
      b++;
    }
    await _goTo(_forward(b));
  }

  Future<void> stop() async {
    _gen++;
    playing = false;
    _hold(false);
    _flushLog();
    _savePosition();
    await Speech.stop();
    book = null;
    doc = null;
    notifyListeners();
  }
}

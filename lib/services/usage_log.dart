import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:omni_ai/omni_ai.dart' show Usage;

import 'storage.dart';

/// One model's use on one day.
class UsageRow {
  UsageRow({required this.day, required this.model, this.calls = 0, this.input = 0, this.output = 0, this.usd = 0, this.unpriced = 0, this.estimated = 0, this.chars = 0, this.seconds = 0});

  /// "2026-10-30".
  final String day;

  /// `google:gemini-2.5-flash`, or `speech:addis` / `speech:elevenlabs`.
  final String model;
  int calls;
  int input;
  int output;
  double usd;

  /// Calls with no price known, so [usd] is a lower bound.
  int unpriced;

  /// Calls priced from the catalog's list price rather than reported by the provider.
  int estimated;

  /// Text sent to a voice.
  int chars;

  /// Audio played from a voice.
  double seconds;

  bool get isSpeech => model.startsWith('speech:');

  Map<String, dynamic> toJson() => {'d': day, 'm': model, 'n': calls, 'i': input, 'o': output, 'u': usd, 'x': unpriced, 'e': estimated, 'c': chars, 's': seconds};

  factory UsageRow.fromJson(Map<String, dynamic> j) => UsageRow(
        day: j['d'] ?? '',
        model: j['m'] ?? '',
        calls: j['n'] ?? 0,
        input: j['i'] ?? 0,
        output: j['o'] ?? 0,
        usd: (j['u'] ?? 0).toDouble(),
        unpriced: j['x'] ?? 0,
        estimated: j['e'] ?? 0,
        chars: j['c'] ?? 0,
        seconds: (j['s'] ?? 0).toDouble(),
      );
}

/// A sum of rows for one period.
class UsageTotal {
  int calls = 0, input = 0, output = 0, unpriced = 0, estimated = 0;
  double usd = 0;
  int get tokens => input + output;

  void add(UsageRow r) {
    calls += r.calls;
    input += r.input;
    output += r.output;
    usd += r.usd;
    unpriced += r.unpriced;
    estimated += r.estimated;
  }
}

/// What your own API keys have been used for, kept only on this device.
class UsageLog extends ChangeNotifier {
  UsageLog._();
  static final UsageLog i = UsageLog._();

  /// Addis AI Voices 2 list price, per generated minute (docs.addisassistant.com).
  static const addisEtbPerMinute = 5.0;

  final List<UsageRow> rows = [];

  Future<void> load() async {
    final j = await Storage.readJson('usage');
    if (j is List) rows.addAll(j.whereType<Map>().map((e) => UsageRow.fromJson(Map<String, dynamic>.from(e))));
    notifyListeners();
  }

  Timer? _pending;

  void _changed() {
    _pending?.cancel();
    _pending = Timer(const Duration(milliseconds: 500), () => Storage.writeJson('usage', rows.map((r) => r.toJson()).toList()));
    notifyListeners();
  }

  static String dayKey(DateTime d) => '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  UsageRow _row(String model, DateTime at) {
    final day = dayKey(at);
    final hit = rows.where((r) => r.day == day && r.model == model).firstOrNull;
    if (hit != null) return hit;
    final r = UsageRow(day: day, model: model);
    rows.add(r);
    return r;
  }

  /// Records a text call. [listPrice] is the cost from the catalog, used when the
  /// provider doesn't report one itself.
  void addText(String model, Usage u, {double? listPrice, DateTime? at}) {
    if (u.totalTokens == 0 && u.cost == null) return;
    final r = _row(model, at ?? DateTime.now())
      ..calls += 1
      ..input += u.inputTokens
      ..output += u.outputTokens;
    if (u.cost != null) {
      r.usd += u.cost!;
    } else if (listPrice != null) {
      r.usd += listPrice;
      r.estimated += 1;
    } else {
      r.unpriced += 1;
    }
    _changed();
  }

  /// Records text sent to a voice ('addis' or 'elevenlabs').
  void addSpeechChars(String engine, int chars, {DateTime? at}) {
    final r = _row('speech:$engine', at ?? DateTime.now())
      ..calls += 1
      ..chars += chars;
    assert(r.isSpeech);
    _changed();
  }

  void addSpeechSeconds(String engine, double seconds, {DateTime? at}) {
    _row('speech:$engine', at ?? DateTime.now()).seconds += seconds;
    _changed();
  }

  /// Rows on or after [from]; everything if null.
  Iterable<UsageRow> since(DateTime? from) {
    if (from == null) return rows;
    final key = dayKey(from);
    return rows.where((r) => r.day.compareTo(key) >= 0);
  }

  void clear() {
    rows.clear();
    _changed();
  }

  /// Merges rows from a backup: for the same model and day, the larger count wins.
  void mergeBackup(dynamic list) {
    if (list is! List) return;
    for (final o in list.whereType<Map>().map((e) => UsageRow.fromJson(Map<String, dynamic>.from(e)))) {
      final at = rows.indexWhere((r) => r.day == o.day && r.model == o.model);
      if (at < 0) {
        rows.add(o);
      } else if (o.calls > rows[at].calls) {
        rows[at] = o;
      }
    }
    _changed();
  }
}

import 'dart:io';

import 'package:alexandria/services/storage.dart';
import 'package:alexandria/services/usage_log.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omni_ai/omni_ai.dart' show Usage;

void main() {
  final log = UsageLog.i;
  final day = DateTime(2026, 3, 10);

  setUp(() {
    Storage.data = Directory.systemTemp.createTempSync('usage');
    log.rows.clear();
  });

  UsageTotal total([DateTime? from]) {
    final t = UsageTotal();
    log.since(from).where((r) => !r.isSpeech).forEach(t.add);
    return t;
  }

  test('a reported cost is used as is, and is not an estimate', () {
    log.addText('gateway:x', const Usage(inputTokens: 100, outputTokens: 50, cost: .02), listPrice: 99, at: day);
    expect(total().tokens, 150);
    expect(total().usd, .02);
    expect(total().estimated, 0);
  });

  test('otherwise the list price counts, flagged as an estimate', () {
    log.addText('google:y', const Usage(inputTokens: 10, outputTokens: 5), listPrice: .001, at: day);
    expect(total().usd, .001);
    expect(total().estimated, 1);
  });

  test('no price at all is counted separately, not as free', () {
    log.addText('google:z', const Usage(inputTokens: 10, outputTokens: 5), at: day);
    expect(total().usd, 0);
    expect(total().unpriced, 1);
  });

  test('same model and day share a row; a new day starts another', () {
    log.addText('m', const Usage(inputTokens: 1), at: day);
    log.addText('m', const Usage(inputTokens: 2), at: day);
    log.addText('m', const Usage(inputTokens: 4), at: day.add(const Duration(days: 1)));
    expect(log.rows, hasLength(2));
    expect(total().input, 7);
    expect(total().calls, 3);
    expect(total(day.add(const Duration(days: 1))).input, 4);
  });

  test('calls with nothing to report are not logged', () {
    log.addText('m', const Usage(), at: day);
    expect(log.rows, isEmpty);
  });

  test('speech keeps characters and seconds apart from tokens', () {
    log.addSpeechChars('addis', 500, at: day);
    log.addSpeechSeconds('addis', 90, at: day);
    final r = log.rows.single;
    expect([r.chars, r.seconds, r.isSpeech], [500, 90.0, true]);
    expect(total().calls, 0);
  });

  test('a backup merges without double counting', () {
    log.addText('m', const Usage(inputTokens: 5), at: day);
    final saved = log.rows.map((r) => r.toJson()).toList();
    log.mergeBackup(saved);
    expect(total().input, 5);
    log.rows.clear();
    log.mergeBackup(saved);
    expect(total().input, 5);
  });
}

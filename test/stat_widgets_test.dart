import 'package:alexandria/models/annotations.dart';
import 'package:alexandria/services/stat_widgets.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final now = DateTime(2026, 3, 10, 15);
  ReadingSession at(int daysAgo, int seconds, {String mode = 'scroll'}) => ReadingSession(bookId: 'b', start: DateTime(2026, 3, 10 - daysAgo, 9), seconds: seconds, mode: mode);

  test('today, the week and the total add up', () {
    final s = ScopeStats.compute([at(0, 600), at(0, 60), at(6, 100), at(7, 999)], now);
    expect(s.today, 660);
    expect(s.week, 760); // the 7-days-ago session is outside the week
    expect(s.total, 1759);
  });

  test('a streak survives until today is over', () {
    expect(ScopeStats.compute([at(1, 60), at(2, 60), at(3, 60)], now).streak, 3);
    expect(ScopeStats.compute([at(0, 60), at(1, 60)], now).streak, 2);
  });

  test('a gap, or under a minute, breaks the streak', () {
    expect(ScopeStats.compute([at(0, 60), at(2, 60)], now).streak, 1);
    expect(ScopeStats.compute([at(0, 59), at(1, 60)], now).streak, 1); // today doesn't count yet, yesterday does
    expect(ScopeStats.compute([at(5, 600)], now).streak, 0);
  });

  test('streaks run across a month boundary', () {
    final first = DateTime(2026, 3, 1, 15);
    final s = ScopeStats.compute([
      ReadingSession(bookId: 'b', start: DateTime(2026, 3, 1, 9), seconds: 60),
      ReadingSession(bookId: 'b', start: DateTime(2026, 2, 28, 9), seconds: 60),
    ], first);
    expect(s.streak, 2);
  });

  test('a widget style survives saving, and unset colours stay automatic', () {
    final st = WidgetStyle.fromJson(WidgetStyle(background: const Color(0xFFFFFFFF), accent: const Color(0xFF112233), font: 'Literata', opacity: .5, radius: 8, showWeek: false).toJson());
    expect(st.background, const Color(0xFFFFFFFF));
    expect(st.text, isNull);
    expect(st.accent, const Color(0xFF112233));
    expect(st.font, 'Literata');
    expect(st.opacity, .5);
    expect(st.showWeek, isFalse);
    expect(st.showGoal, isTrue);
    // Automatic text is dark on a light background and light on a dark one.
    expect(st.fg.computeLuminance(), lessThan(.2));
    expect(WidgetStyle().fg.computeLuminance(), greaterThan(.7));
  });
}

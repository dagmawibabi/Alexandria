import 'dart:io';

import 'package:alexandria/core/color_picker.dart';
import 'package:alexandria/core/search_box.dart';
import 'package:alexandria/core/settings.dart';
import 'package:alexandria/core/theme.dart';
import 'package:alexandria/models/radio.dart';
import 'package:alexandria/services/storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  final h = SearchHistory.i;

  setUp(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    await Settings.i.load();
    Storage.data = Directory.systemTemp.createTempSync('hist');
    h.clear('a');
    h.clear('b');
  });

  group('search history', () {
    test('newest first, each bar separate', () {
      h.add('a', 'dune');
      h.add('a', 'emma');
      h.add('b', 'jazz');
      expect(h.of('a'), ['emma', 'dune']);
      expect(h.of('b'), ['jazz']);
    });

    test('a repeat moves to the top rather than doubling, ignoring case', () {
      h.add('a', 'Dune');
      h.add('a', 'emma');
      h.add('a', 'dune');
      expect(h.of('a'), ['dune', 'emma']);
    });

    test('blank and one-letter searches are not kept; the list stays short', () {
      h.add('a', '  ');
      h.add('a', 'x');
      expect(h.of('a'), isEmpty);
      for (var i = 0; i < 30; i++) {
        h.add('a', 'search $i');
      }
      expect(h.of('a').length, 12);
      expect(h.of('a').first, 'search 29');
    });

    test('one can be removed, or all cleared', () {
      h.add('a', 'dune');
      h.add('a', 'emma');
      h.remove('a', 'dune');
      expect(h.of('a'), ['emma']);
      h.clear('a');
      expect(h.of('a'), isEmpty);
    });

    test('it survives a backup', () {
      h.add('a', 'dune');
      final saved = h.toJson();
      h.clear('a');
      h.mergeBackup(saved);
      expect(h.of('a'), ['dune']);
    });
  });

  group('the search box', () {
    Widget app(Widget child) => MaterialApp(theme: ThemeData(), home: Material(child: Center(child: SizedBox(width: 300, child: child))));

    testWidgets('history only shows while focused, and picking one searches it', (tester) async {
      h.add('a', 'dune');
      String? searched;
      await tester.pumpWidget(_withTokens(app(SearchBox(historyKey: 'a', onSubmitted: (v) => searched = v))));
      expect(find.text('dune'), findsNothing);
      await tester.tap(find.byType(TextField));
      await tester.pump();
      expect(find.text('dune'), findsOneWidget);
      await tester.tap(find.text('dune'));
      await tester.pump();
      expect(searched, 'dune');
      expect(find.text('Recent'), findsNothing); // closed again
      await tester.pump(const Duration(seconds: 1)); // lets the save run
    });

    testWidgets('submitting saves; the X removes', (tester) async {
      await tester.pumpWidget(_withTokens(app(const SearchBox(historyKey: 'a'))));
      await tester.tap(find.byType(TextField));
      await tester.enterText(find.byType(TextField), 'emma');
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pump();
      expect(h.of('a'), ['emma']);
      await tester.enterText(find.byType(TextField), '');
      await tester.pump();
      await tester.tap(find.byIcon(Icons.close_sharp));
      await tester.pump();
      expect(h.of('a'), isEmpty);
      await tester.pump(const Duration(seconds: 1)); // lets the save run
    });
  });

  group('colours', () {
    test('hex reads and writes', () {
      expect(colorHex(const Color(0xFF2D6BFF)), '#2D6BFF');
      expect(parseHex('#2d6bff'), const Color(0xFF2D6BFF));
      expect(parseHex('2D6BFF'), const Color(0xFF2D6BFF));
      expect(parseHex('#fff'), const Color(0xFFFFFFFF));
      expect(parseHex('#12'), isNull);
      expect(parseHex('zzzzzz'), isNull);
    });

    test('white is an accent, and never vanishes on a light surface', () {
      expect(accents, contains(const Color(0xFFFFFFFF)));
      Settings.i.mono = false;
      Settings.i.accent = const Color(0xFFFFFFFF);
      const lightInk = Color(0xFFEDEDED), darkInk = Color(0xFF1A1A1A);
      expect(Settings.i.signalOn(lightInk), const Color(0xFFFFFFFF)); // dark surface: really white
      expect(Settings.i.signalOn(darkInk), darkInk); // light surface: follows the ink
    });

    test('a black accent does the same on a dark surface; normal colours are untouched', () {
      Settings.i.mono = false;
      const lightInk = Color(0xFFEDEDED), darkInk = Color(0xFF1A1A1A);
      Settings.i.accent = const Color(0xFF000000);
      expect(Settings.i.signalOn(lightInk), lightInk);
      Settings.i.accent = const Color(0xFF2D6BFF);
      expect(Settings.i.signalOn(lightInk), const Color(0xFF2D6BFF));
      expect(Settings.i.signalOn(darkInk), const Color(0xFF2D6BFF));
    });
  });

  group('flags', () {
    test('from a code or a name', () {
      expect(countryFlag('ET', ''), '🇪🇹');
      expect(countryFlag('ti:r1', 'Ethiopia'), '🇪🇹');
      expect(countryFlag('ti:r1', 'The Bahamas'), '🇧🇸');
      expect(countryFlag('ti:r1', "Cote d'Ivoire"), '🇨🇮');
      expect(countryFlag('', 'Atlantis'), '');
    });
  });
}

/// Tokens on the theme, which every shared control reads.
Widget _withTokens(Widget app) {
  final a = app as MaterialApp;
  return MaterialApp(
    theme: ThemeData(extensions: const []).copyWith(extensions: _tokens),
    home: a.home,
  );
}

const _tokens = [Tokens(bg: Colors.black, surface: Colors.black, raised: Colors.black, ink: Colors.white, muted: Colors.grey, line: Colors.grey, accent: Colors.orange, onAccent: Colors.black, radius: 2, dark: true)];

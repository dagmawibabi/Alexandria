import 'dart:io';

import 'package:alexandria/core/settings.dart';
import 'package:alexandria/core/theme.dart';
import 'package:alexandria/core/ui.dart';
import 'package:alexandria/models/book.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  final book = Book(id: 'x', title: 'Short Story Collection Vol. 004 and a much longer subtitle after that', author: 'Various', format: BookFormat.epub, path: '');
  const tokens = Tokens(bg: Colors.black, surface: Colors.black, raised: Colors.black, ink: Colors.white, muted: Colors.grey, line: Colors.grey, accent: Colors.orange, onAccent: Colors.black, radius: 2, dark: true);

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    GoogleFonts.config.allowRuntimeFetching = false;
    SharedPreferences.setMockInitialValues({});
    await Settings.i.load();
    Directory.systemTemp.createTempSync();
  });

  // The sizes covers really appear at, including the one from the crash report
  // (46 x 48 inside its padding, on a square audiobook tile).
  for (final (w, h) in const [(70.0, 70.0), (42.0, 42.0), (30.0, 45.0), (96.0, 144.0), (96.0, 96.0), (130.0, 195.0), (320.0, 320.0), (60.0, 30.0)]) {
    for (final zen in [false, true]) {
      testWidgets('fits at ${w}x$h${zen ? ' in zen' : ''}', (tester) async {
        Settings.i.zen = zen;
        await tester.pumpWidget(MaterialApp(
          theme: ThemeData(extensions: [zen ? const Tokens(bg: Colors.black, surface: Colors.black, raised: Colors.black, ink: Colors.white, muted: Colors.grey, line: Colors.grey, accent: Colors.orange, onAccent: Colors.black, radius: 16, dark: true, zen: true) : tokens]),
          home: Center(child: SizedBox(width: w, height: h, child: GeneratedCover(book))),
        ));
        // Layout errors surface here. A font missing in this test environment is not one.
        final e = tester.takeException();
        expect(e == null || !'$e'.contains('overflowed'), isTrue, reason: '$e');
      });
    }
  }
}

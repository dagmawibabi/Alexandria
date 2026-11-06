// ignore_for_file: invalid_use_of_protected_member, invalid_use_of_visible_for_testing_member
import 'dart:io';

import 'package:alexandria/core/image_viewer.dart';
import 'package:alexandria/core/settings.dart';
import 'package:alexandria/core/theme.dart';
import 'package:alexandria/models/audiobook.dart';
import 'package:alexandria/screens/player_parts.dart';
import 'package:alexandria/screens/quote_card.dart';
import 'package:alexandria/services/audio.dart';
import 'package:alexandria/services/storage.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

// A 1×1 PNG.
const _png = [
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01, 0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4, //
  0x89, 0x00, 0x00, 0x00, 0x0D, 0x49, 0x44, 0x41, 0x54, 0x78, 0x9C, 0x63, 0xF8, 0xCF, 0xC0, 0xF0, 0x1F, 0x00, 0x05, 0x00, 0x01, 0xFF, 0x89, 0x99, 0x3D, 0x1D, 0x00, 0x00, 0x00, 0x00, 0x49, 0x45, //
  0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82,
];

void main() {
  late Directory tmp;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    GoogleFonts.config.allowRuntimeFetching = false;
    tmp = await Directory.systemTemp.createTemp('alexandria_player_viewer');
    final m = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    m.setMockMethodCallHandler(const MethodChannel('plugins.flutter.io/path_provider'), (_) async => tmp.path);
    SharedPreferences.setMockInitialValues({});
    await Settings.i.load();
    await Storage.init();
  });

  Widget app(Widget child) => MaterialApp(theme: buildTheme(Brightness.light, Settings.i), home: Scaffold(body: child));

  group('player controls as const children', () {
    tearDown(() {
      Player.i
        ..book = null
        ..position = Duration.zero
        ..duration = Duration.zero
        ..playing = false;
    });

    // The normal player builds these as const; a parent rebuild skips them, so
    // they have to follow the player themselves (they stuck at 0:00 before).
    testWidgets('the time follows playback', (tester) async {
      Player.i
        ..book = Audiobook(id: 'ep:test', title: 'Test', tracks: [AudioTrack(title: 'Test', path: 'https://example.test/a.mp3', ms: 600000)])
        ..duration = const Duration(minutes: 10);
      await tester.pumpWidget(app(const Column(children: [PlayerScrubber(), PlayerControls()])));
      expect(find.text('0:00'), findsOneWidget);
      expect(find.byIcon(Icons.play_arrow_sharp), findsOneWidget);

      Player.i
        ..position = const Duration(minutes: 1, seconds: 5)
        ..playing = true
        ..notifyListeners();
      await tester.pump();
      expect(find.text('1:05'), findsOneWidget);
      expect(find.byIcon(Icons.pause_sharp), findsOneWidget);
    });
  });

  group('image viewer', () {
    testWidgets('a tapped image opens full screen, with share and save, and double tap zooms', (tester) async {
      final f = File('${tmp.path}/cover.png');
      await tester.runAsync(() => f.writeAsBytes(_png));
      await tester.pumpWidget(app(Center(child: ViewableImage(path: f.path, title: 'My Show', child: const SizedBox(width: 80, height: 80, child: ColoredBox(color: Colors.red))))));

      await tester.tap(find.byType(ViewableImage));
      // The viewer reads the file from disk (a spinner meanwhile): let that real IO finish.
      for (var i = 0; i < 50 && find.byType(InteractiveViewer).evaluate().isEmpty; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
        await tester.pump(const Duration(milliseconds: 20));
      }
      await tester.pumpAndSettle();
      expect(find.byType(ImageViewer), findsOneWidget);
      expect(find.text('My Show'), findsOneWidget);
      expect(find.byTooltip('Save to device'), findsOneWidget);
      expect(find.byTooltip('Share'), findsOneWidget);

      final viewer = tester.widget<InteractiveViewer>(find.byType(InteractiveViewer));
      final zoom = viewer.transformationController!;
      expect(zoom.value.getMaxScaleOnAxis(), 1);
      final at = tester.getCenter(find.byType(InteractiveViewer));
      await tester.tapAt(at);
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tapAt(at);
      await tester.pumpAndSettle();
      expect(zoom.value.getMaxScaleOnAxis(), greaterThan(2));

      await tester.tap(find.byTooltip('Close'));
      await tester.pumpAndSettle();
      expect(find.byType(ImageViewer), findsNothing);
    });

    testWidgets('without an image there is nothing to open', (tester) async {
      await tester.pumpWidget(app(const ViewableImage(title: 'None', child: Text('art'))));
      expect(find.byType(GestureDetector), findsNothing);
    });
  });

  test('the share card picker lists Cover first, without moving saved styles', () {
    expect(cardStyles[cardStyleOrder.first].name, 'Cover');
    expect(cardStyleOrder.toSet(), {for (var i = 0; i < cardStyles.length; i++) i});
    // Saved choices are positions in cardStyles, so that order stays put.
    expect(cardStyles.first.name, 'Spec');
  });
}

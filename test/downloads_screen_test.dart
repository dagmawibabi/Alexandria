// ignore_for_file: invalid_use_of_protected_member, invalid_use_of_visible_for_testing_member
import 'dart:io';

import 'package:alexandria/core/settings.dart';
import 'package:alexandria/core/theme.dart';
import 'package:alexandria/models/podcast.dart';
import 'package:alexandria/screens/downloads_screen.dart';
import 'package:alexandria/services/downloads.dart';
import 'package:alexandria/services/podcasts.dart';
import 'package:alexandria/services/storage.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The downloads page while an episode is still arriving.
void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    GoogleFonts.config.allowRuntimeFetching = false;
    final tmp = await Directory.systemTemp.createTemp('alexandria_downloads_page');
    final m = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    m.setMockMethodCallHandler(const MethodChannel('plugins.flutter.io/path_provider'), (_) async => tmp.path);
    SharedPreferences.setMockInitialValues({});
    await Settings.i.load();
    await Storage.init();
  });

  testWidgets('an episode in progress shows its show, title, size, speed and time left', (tester) async {
    final e = Episode(guid: 'dl-1', feedUrl: 'https://example.test/feed', title: 'The Long Interview', audioUrl: 'https://example.test/1.mp3', podcastTitle: 'Talk Show');
    Podcasts.i.setPlayed(e, false); // gives it a state, as starting a download does
    Downloads.i.report(e.guid, .45, label: e.title);
    Downloads.i.stats[e.guid] = DownloadStat()
      ..got = 12 << 20
      ..total = 27 << 20
      ..rate = 1.5 * (1 << 20);
    Downloads.i.notifyListeners();

    await tester.pumpWidget(MaterialApp(theme: buildTheme(Brightness.light, Settings.i), home: const EpisodeDownloadsScreen()));
    await tester.pump();

    expect(find.text('The Long Interview'), findsOneWidget);
    // Status lines are Labels, shown in capitals in this theme.
    expect(find.text('TALK SHOW'), findsOneWidget);
    expect(find.text('45% · 12.0 MB OF 27.0 MB · 1.5 MB/S · 10S LEFT'), findsOneWidget);
    expect(find.byTooltip('Cancel'), findsOneWidget);

    // A dropped connection says so instead of a speed.
    Downloads.i.stats[e.guid]!
      ..rate = 0
      ..attempt = 2;
    Downloads.i.notifyListeners();
    await tester.pump();
    expect(find.text('CONNECTION DROPPED · RETRYING (TRY 2 OF 5)'), findsOneWidget);

    Downloads.i.report(e.guid, null);
    await tester.pump();
    expect(find.text('The Long Interview'), findsNothing);
    // Let the delayed save that marking the episode started finish.
    await tester.pump(const Duration(seconds: 5));
  });
}

import 'dart:io';

import 'package:alexandria/core/settings.dart';
import 'package:alexandria/core/skeleton.dart';
import 'package:alexandria/core/theme.dart';
import 'package:alexandria/models/podcast.dart';
import 'package:alexandria/screens/podcasts_view.dart';
import 'package:alexandria/services/storage.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Loading shows the shape of what's coming, not a lone spinner.
void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    GoogleFonts.config.allowRuntimeFetching = false;
    final tmp = await Directory.systemTemp.createTemp('alexandria_skeleton');
    final m = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    m.setMockMethodCallHandler(const MethodChannel('plugins.flutter.io/path_provider'), (_) async => tmp.path);
    SharedPreferences.setMockInitialValues({});
    await Settings.i.load();
    await Storage.init();
  });

  Widget app(Widget home, {bool still = false}) => MaterialApp(
        theme: buildTheme(Brightness.light, Settings.i),
        builder: (context, child) => MediaQuery(data: MediaQuery.of(context).copyWith(disableAnimations: still), child: child!),
        home: home,
      );

  testWidgets('a show opening from the charts shows its title at once, and a skeleton for the rest', (tester) async {
    tester.view
      ..physicalSize = const Size(360, 740)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final hit = PodcastHit(id: '1', title: 'Chart Show', author: 'Some Host', feedUrl: 'https://example.test/never-loads');
    await tester.pumpWidget(app(PodcastScreen(hit: hit, feedUrl: hit.feedUrl)));

    expect(find.text('Chart Show'), findsOneWidget);
    expect(find.text('Some Host'), findsOneWidget);
    expect(find.byType(Shimmer), findsWidgets);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(tester.takeException(), isNull, reason: 'fits a small phone');

    // Let the (failing) load finish so nothing is left running.
    for (var i = 0; i < 5; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pump(const Duration(milliseconds: 50));
    }
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 5));
    tester.takeException();
  });

  testWidgets('the skeletons fit a narrow screen', (tester) async {
    tester.view
      ..physicalSize = const Size(320, 2400)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(app(const Scaffold(
      body: SingleChildScrollView(
        child: Column(children: [
          SkeletonRows(count: 4, art: 64, lines: 3, padding: EdgeInsets.symmetric(horizontal: 20)),
          SkeletonRows(count: 3, art: 44, artAspect: 2 / 3),
          SkeletonRows(count: 3, art: null, lines: 1),
          SkeletonGrid(count: 6, padding: EdgeInsets.symmetric(horizontal: 20)),
          SkeletonText(lines: 4, paragraphs: 2),
        ]),
      ),
    )));
    await tester.pump(const Duration(milliseconds: 300));
    expect(tester.takeException(), isNull);
  });

  testWidgets('the shimmer holds still with reduce motion on', (tester) async {
    await tester.pumpWidget(app(const Scaffold(body: SkeletonText()), still: true));
    // Nothing is animating, so the frame settles at once.
    await tester.pumpAndSettle();
    expect(tester.hasRunningAnimations, isFalse);

    await tester.pumpWidget(app(const Scaffold(body: SkeletonText())));
    await tester.pump(const Duration(milliseconds: 100));
    expect(tester.hasRunningAnimations, isTrue);
    await tester.pumpWidget(const SizedBox());
  });
}

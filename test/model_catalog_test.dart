import 'dart:convert';
import 'dart:io';

import 'package:alexandria/core/settings.dart';
import 'package:alexandria/core/theme.dart';
import 'package:alexandria/screens/ai_sheets.dart';
import 'package:alexandria/services/ai.dart';
import 'package:alexandria/services/storage.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:material_ui/material_ui.dart';
import 'package:omni_ai/omni_ai.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  ModelInfo model(String provider, String id, String name) => ModelInfo(provider: provider, modelId: id, name: name, types: const {ModelType.text});

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    GoogleFonts.config.allowRuntimeFetching = false;
    final tmp = await Directory.systemTemp.createTemp('alexandria_catalog');
    final m = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    m.setMockMethodCallHandler(const MethodChannel('plugins.flutter.io/path_provider'), (_) async => tmp.path);
    m.setMockMethodCallHandler(const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'), (_) async => null);
    SharedPreferences.setMockInitialValues({});
    await Settings.i.load();
    await Storage.init();
    await Ai.ready;
    await Ai.omni.setApiKey('google', 'test-key', persist: false);
  });

  test('a saved list without a connected provider is fetched again', () async {
    final catalog = Ai.omni.catalog;
    Ai.omni.register(GoogleProvider(
      apiKey: 'test-key',
      httpClient: MockClient((_) async => http.Response(
            jsonEncode({
              'models': [
                {'name': 'models/gemini-test', 'displayName': 'Gemini Test', 'supportedGenerationMethods': ['generateContent']},
              ],
            }),
            200,
          )),
    ));
    catalog.fetchedAt = DateTime.now();

    // Nothing to do yet. This must not stop the fetch below from happening.
    catalog.models = [model('google', 'gemini-old', 'Gemini Old'), model('gateway', 'openai/gpt-test', 'GPT Test')];
    await Ai.loadCatalog();
    expect(catalog.ofProvider('google').map((m) => m.id), ['google:gemini-old']);

    // Fresh by its date, but saved before the Google key was added.
    catalog.models = [model('gateway', 'openai/gpt-test', 'GPT Test')];
    await Ai.loadCatalog();
    expect(catalog.ofProvider('google').map((m) => m.id), ['google:gemini-test']);
  });

  testWidgets('hiding the keyboard keeps the search, and a tap picks the result it landed on', (tester) async {
    tester.view
      ..physicalSize = const Size(412, 892)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final catalog = Ai.omni.catalog;
    catalog.models = [model('google', 'alpha', 'Alpha Model'), model('google', 'beta', 'Beta Model')];
    catalog.fetchedAt = DateTime.now();
    Settings.i.aiModel = 'google:gemini-2.5-flash';

    Future<void> settle() async {
      for (var i = 0; i < 10; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 5)));
        await tester.pump(const Duration(milliseconds: 100));
      }
    }

    final nav = GlobalKey<NavigatorState>();
    await tester.pumpWidget(MaterialApp(navigatorKey: nav, theme: buildTheme(Brightness.light, Settings.i), home: const Scaffold(body: SizedBox())));
    pickModel(nav.currentContext!);
    await settle();
    await tester.tap(find.textContaining(RegExp('browse full catalog', caseSensitive: false)));
    await settle();
    expect(find.text('Alpha Model'), findsOneWidget);

    tester.view.viewInsets = const FakeViewPadding(bottom: 300);
    await tester.enterText(find.byType(TextField), 'beta');
    await settle();
    expect(find.text('Alpha Model'), findsNothing);

    tester.view.resetViewInsets();
    await settle();
    expect(find.text('Alpha Model'), findsNothing, reason: 'the keyboard closing must not clear the search');
    expect(find.text('Beta Model'), findsOneWidget);

    await tester.tap(find.text('Beta Model'));
    await settle();
    expect(Settings.i.aiModel, 'google:beta');

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
    tester.takeException();
  });
}

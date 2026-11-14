import 'dart:ui' show PointerDeviceKind;

import 'package:flutter/services.dart';
import 'package:just_audio_media_kit/just_audio_media_kit.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pdfrx/pdfrx.dart';

import 'core/search_box.dart';
import 'core/settings.dart';
import 'core/theme.dart';
import 'core/ui.dart';
import 'screens/reader/reader_screen.dart';
import 'screens/shell.dart';
import 'services/ai.dart';
import 'services/api_cache.dart';
import 'services/audio.dart';
import 'services/audio_handler.dart';
import 'services/podcasts.dart';
import 'services/intents.dart';
import 'services/library.dart';
import 'services/radio.dart';
import 'services/stat_widgets.dart';
import 'services/storage.dart';
import 'services/usage_log.dart';
import 'services/volume_keys.dart';

final navigatorKey = GlobalKey<NavigatorState>();

Future<void> main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  // just_audio has no Windows/Linux player of its own; media_kit (libmpv) supplies one.
  JustAudioMediaKit.ensureInitialized();
  await Future.wait([Settings.i.load(), Storage.init(), pdfrxFlutterInitialize()]);
  await Future.wait([Library.i.load(), AudioLibrary.i.load(), Podcasts.i.load(), UsageLog.i.load(), RadioDirectory.i.load(), SearchHistory.i.load()]);
  await AlexandriaAudioHandler.init();
  ApiCache.prune().ignore();
  StatWidgets.i.init();
  AudioLibrary.i.resumeDownloads();
  await IncomingFiles.init(args);
  Ai.ready.ignore();
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  runApp(const AlexandriaApp());
}

class AlexandriaApp extends StatefulWidget {
  const AlexandriaApp({super.key});

  @override
  State<AlexandriaApp> createState() => _AlexandriaAppState();
}

class _AlexandriaAppState extends State<AlexandriaApp> {
  @override
  void initState() {
    super.initState();
    IncomingFiles.onFiles = _open;
    WidgetsBinding.instance.addPostFrameCallback((_) async => _open(await IncomingFiles.initial()));
  }

  /// A file arrived from another app: import it and go straight to reading.
  Future<void> _open(List<({String path, String name})> files) async {
    if (files.isEmpty) return;
    final ctx = navigatorKey.currentContext;
    String? lastId;
    for (final f in files) {
      try {
        final book = await Library.i.importFile(f.path, displayName: f.name);
        lastId = book.id;
      } catch (e) {
        if (ctx != null && ctx.mounted) toast(ctx, '$e');
      }
    }
    final book = lastId == null ? null : Library.i.byId(lastId);
    if (book != null) {
      navigatorKey.currentState?.push(MaterialPageRoute(builder: (_) => ReaderScreen(book: book)));
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Settings.i,
      builder: (context, _) {
        final s = Settings.i;
        return MaterialApp(
          title: 'Alexandria',
          navigatorKey: navigatorKey,
          navigatorObservers: [VolumeKeys.routes],
          debugShowCheckedModeBanner: false,
          // Mouse users can drag chip rows and carousels sideways, as on a phone.
          scrollBehavior: const _DragScroll(),
          themeMode: s.themeMode,
          theme: buildTheme(Brightness.light, s),
          darkTheme: buildTheme(Brightness.dark, s),
          home: const Shell(),
          // Esc steps back a page (or closes a sheet), as on any desktop app.
          // In a text field it just leaves the field.
          builder: (context, child) => Focus(
            canRequestFocus: false,
            skipTraversal: true,
            onKeyEvent: (node, e) {
              if (e is! KeyDownEvent || e.logicalKey != LogicalKeyboardKey.escape) return KeyEventResult.ignored;
              final focus = FocusManager.instance.primaryFocus;
              if (focus?.context?.findAncestorStateOfType<EditableTextState>() != null) {
                focus!.unfocus();
                return KeyEventResult.handled;
              }
              navigatorKey.currentState?.maybePop();
              return KeyEventResult.handled;
            },
            child: NavFrame(navigator: navigatorKey, child: child!),
          ),
        );
      },
    );
  }
}

class _DragScroll extends MaterialScrollBehavior {
  const _DragScroll();

  @override
  Set<PointerDeviceKind> get dragDevices => {...super.dragDevices, PointerDeviceKind.mouse};
}

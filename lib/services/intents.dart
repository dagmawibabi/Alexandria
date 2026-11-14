import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

/// Files handed to Alexandria by other apps ("Open with…" / "Share to…").
/// The native side copies each content:// stream to a cache file.
class IncomingFiles {
  IncomingFiles._();

  static const _channel = MethodChannel('alexandria/intent');

  static void Function(List<({String path, String name})>)? onFiles;

  /// A launch can arrive both ways; each copy is one file to open, once.
  static final _seen = <String>{};

  static List<({String path, String name})> _unseen(List<({String path, String name})> files) => files.where((f) => _seen.add(f.path)).toList();

  /// Command-line arguments from `main`, for desktop "Open with".
  static List<String> _args = const [];

  static Future<void> init([List<String> args = const []]) async {
    _args = args;
    _channel.setMethodCallHandler((call) async {
      final handler = onFiles;
      if (call.method == 'files' && handler != null) handler(_unseen(_decode(call.arguments)));
    });
  }

  /// Files the app was launched with.
  static Future<List<({String path, String name})>> initial() async {
    if (!Platform.isAndroid && !Platform.isIOS) {
      return _unseen([
        for (final a in _args)
          if (File(a).existsSync()) (path: a, name: p.basename(a)),
      ]);
    }
    try {
      return _unseen(_decode(await _channel.invokeMethod('initialFiles')));
    } on MissingPluginException {
      return const [];
    } on PlatformException {
      return const [];
    }
  }

  static List<({String path, String name})> _decode(dynamic raw) => [
        for (final m in (raw as List? ?? const []))
          (path: (m as Map)['path'] as String, name: (m['name'] as String?) ?? (m['path'] as String).split('/').last),
      ];
}

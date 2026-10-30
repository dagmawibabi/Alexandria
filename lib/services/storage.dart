import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// App folders and small JSON persistence helpers.
class Storage {
  Storage._();

  static late Directory root;
  static late Directory books;
  static late Directory covers;
  static late Directory cache;
  static late Directory images;
  static late Directory data;

  static Future<void> init() async {
    final docs = await getApplicationDocumentsDirectory();
    root = Directory(p.join(docs.path, 'alexandria'));
    books = Directory(p.join(root.path, 'books'));
    covers = Directory(p.join(root.path, 'covers'));
    cache = Directory(p.join(root.path, 'cache'));
    images = Directory(p.join(root.path, 'images'));
    data = Directory(p.join(root.path, 'data'));
    for (final d in [root, books, covers, cache, images, data]) {
      await d.create(recursive: true);
    }
  }

  static File _file(String name) => File(p.join(data.path, '$name.json'));

  static Future<dynamic> readJson(String name) async {
    final f = _file(name);
    if (!await f.exists()) return null;
    try {
      return jsonDecode(await f.readAsString());
    } catch (_) {
      return null;
    }
  }

  /// Writes atomically (temp file + rename) so a crash never corrupts data.
  static Future<void> writeJson(String name, Object value) async {
    final f = _file(name);
    final tmp = File('${f.path}.tmp');
    await tmp.writeAsString(jsonEncode(value), flush: true);
    await tmp.rename(f.path);
  }
}

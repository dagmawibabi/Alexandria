import 'dart:convert';
import 'dart:io';

import '../core/search_box.dart';
import '../core/settings.dart';
import 'audio.dart';
import 'library.dart';
import 'podcasts.dart';
import 'radio.dart';
import 'usage_log.dart';

/// What a restore did.
class ImportResult {
  ImportResult({this.books = 0, this.missingBooks = 0, this.audiobooks = 0, this.missingAudiobooks = 0, this.shows = 0, this.episodes = 0, this.notes = 0});
  int books;

  /// Books listed in the backup whose file isn't on this device.
  int missingBooks;
  int audiobooks;
  int missingAudiobooks;
  int shows;
  int episodes;

  /// Highlights and bookmarks added.
  int notes;
}

/// The whole app as one JSON file: everything except the media files and API keys.
class Backup {
  Backup._();

  static const version = 2;

  static Map<String, dynamic> export() => {
        'app': 'alexandria',
        'version': version,
        'exportedAt': DateTime.now().toIso8601String(),
        ...Library.i.exportJson(),
        'audiobooks': AudioLibrary.i.books.map((b) => b.toJson()).toList(),
        'podcasts': Podcasts.i.toJson(),
        'radio': RadioDirectory.i.toJson(),
        'searchHistory': SearchHistory.i.toJson(),
        'settings': Settings.i.exportJson(),
        'usage': UsageLog.i.rows.map((r) => r.toJson()).toList(),
      };

  /// Reads and checks a backup file; throws a readable message if it isn't one.
  static Future<Map<String, dynamic>> read(String path) async {
    final dynamic j;
    try {
      j = jsonDecode(await File(path).readAsString());
    } catch (_) {
      throw 'That file is not valid JSON.';
    }
    if (j is! Map || j['app'] != 'alexandria') throw 'That file is not an Alexandria backup.';
    return Map<String, dynamic>.from(j);
  }

  /// Merges a backup in. Nothing is deleted: new items are added, and where an
  /// item exists on both sides the most recently used copy wins.
  static Future<ImportResult> restore(Map<String, dynamic> j) async {
    final r = ImportResult();
    Library.i.mergeBackup(j, r);
    AudioLibrary.i.mergeBackup(j['audiobooks'], r);
    Podcasts.i.mergeBackup(j['podcasts'], r);
    RadioDirectory.i.mergeBackup(j['radio']);
    SearchHistory.i.mergeBackup(j['searchHistory']);
    UsageLog.i.mergeBackup(j['usage']);
    if (j['settings'] is Map) Settings.i.importJson(Map<String, dynamic>.from(j['settings']));
    return r;
  }
}

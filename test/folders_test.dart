import 'dart:io';

import 'package:alexandria/core/settings.dart';
import 'package:alexandria/models/audiobook.dart';
import 'package:alexandria/models/book.dart';
import 'package:alexandria/models/podcast.dart';
import 'package:alexandria/services/audio.dart';
import 'package:alexandria/services/folders.dart';
import 'package:alexandria/services/library.dart';
import 'package:alexandria/services/podcasts.dart';
import 'package:alexandria/services/storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late Folder f;

  setUp(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    await Settings.i.load();
    Storage.data = Directory.systemTemp.createTempSync('folders');
    Library.i.books.clear();
    Library.i.saved.clear();
    Library.i.folders.clear();
    AudioLibrary.i.books.clear();
    Podcasts.i.subscriptions.clear();
    Podcasts.i.showFolders.clear();
    f = Library.i.addFolder('Philosophy');
    Library.i.books.add(Book(id: 'b', title: 'B', format: BookFormat.epub, path: '', folderIds: [f.id]));
    Library.i.books.add(Book(id: 'loose', title: 'Loose', format: BookFormat.epub, path: ''));
    Library.i.saved.add(SavedBook(key: 's', title: 'S', folderIds: [f.id]));
    AudioLibrary.i.books.add(Audiobook(id: 'a', title: 'A', tracks: const [], folderIds: [f.id]));
    Podcasts.i.subscriptions.add(Podcast(feedUrl: 'https://f', title: 'Show'));
    Podcasts.i.showFolders['https://f'] = [f.id];
  });

  test('each tab counts its own kind of thing in a shared folder', () {
    expect(folderCount(FolderKind.books, f.id), 2); // a library book and a want-to-read book
    expect(folderCount(FolderKind.audio, f.id), 1);
    expect(folderCount(FolderKind.podcasts, f.id), 1);
    expect(folderContents(f), '2 books, 1 audiobook, 1 show');
    expect(unfiledCount(FolderKind.books), 1);
    expect(unfiledCount(FolderKind.audio), 0);
  });

  test('an empty folder says so, and counts read naturally', () {
    final empty = Library.i.addFolder('Empty');
    expect(folderContents(empty), 'Empty');
    expect(countOf(1, FolderKind.podcasts), '1 show');
    expect(countOf(3, FolderKind.audio), '3 audiobooks');
  });

  test('deleting a folder clears it everywhere and deletes nothing else', () {
    Library.i.deleteFolder(f);
    expect(Library.i.folders, isEmpty);
    expect(Library.i.books.every((b) => b.folderIds.isEmpty), isTrue);
    expect(Library.i.saved.single.folderIds, isEmpty);
    expect(AudioLibrary.i.books.single.folderIds, isEmpty);
    expect(Podcasts.i.foldersOf('https://f'), isEmpty);
    expect([Library.i.books.length, Library.i.saved.length, AudioLibrary.i.books.length, Podcasts.i.subscriptions.length], [2, 1, 1, 1]);
  });

  test('an id whose folder is gone counts as unfiled', () {
    Library.i.folders.clear();
    expect(unfiledCount(FolderKind.audio), 1);
  });
}

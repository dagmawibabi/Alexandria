import '../models/book.dart';
import 'audio.dart';
import 'library.dart';
import 'podcasts.dart';
import 'radio.dart';

/// Folders are shared across the app, so "Philosophy" can hold books, audiobooks
/// and shows; each tab manages its own kind of thing in them.
enum FolderKind { books, audio, podcasts, radio }

extension FolderKindNames on FolderKind {
  String get plural => switch (this) { FolderKind.books => 'books', FolderKind.audio => 'audiobooks', FolderKind.podcasts => 'shows', FolderKind.radio => 'stations' };
  String get singular => switch (this) { FolderKind.books => 'book', FolderKind.audio => 'audiobook', FolderKind.podcasts => 'show', FolderKind.radio => 'station' };
  String get title => switch (this) { FolderKind.books => 'Book folders', FolderKind.audio => 'Audiobook folders', FolderKind.podcasts => 'Podcast folders', FolderKind.radio => 'Radio folders' };
}

String countOf(int n, FolderKind k) => '$n ${n == 1 ? k.singular : k.plural}';

/// How many of [kind] are in folder [id].
int folderCount(FolderKind kind, String id) => switch (kind) {
      FolderKind.books => Library.i.books.where((b) => b.folderIds.contains(id)).length + Library.i.saved.where((s) => s.folderIds.contains(id)).length,
      FolderKind.audio => AudioLibrary.i.books.where((b) => b.folderIds.contains(id)).length,
      FolderKind.podcasts => Podcasts.i.subscriptions.where((s) => Podcasts.i.foldersOf(s.feedUrl).contains(id)).length,
      FolderKind.radio => RadioDirectory.i.kept.where((s) => RadioDirectory.i.foldersOf(s.id).contains(id)).length,
    };

/// How many of [kind] exist in total.
int kindTotal(FolderKind kind) => switch (kind) {
      FolderKind.books => Library.i.books.length + Library.i.saved.length,
      FolderKind.audio => AudioLibrary.i.books.length,
      FolderKind.podcasts => Podcasts.i.subscriptions.length,
      FolderKind.radio => RadioDirectory.i.kept.length,
    };

/// How many of [kind] aren't filed anywhere. Ids of folders that no longer exist don't count.
int unfiledCount(FolderKind kind) {
  final live = {for (final f in Library.i.folders) f.id};
  bool none(List<String> ids) => !ids.any(live.contains);
  return switch (kind) {
    FolderKind.books => Library.i.books.where((b) => none(b.folderIds)).length + Library.i.saved.where((s) => none(s.folderIds)).length,
    FolderKind.audio => AudioLibrary.i.books.where((b) => none(b.folderIds)).length,
    FolderKind.podcasts => Podcasts.i.subscriptions.where((s) => none(Podcasts.i.foldersOf(s.feedUrl))).length,
    FolderKind.radio => RadioDirectory.i.kept.where((s) => none(RadioDirectory.i.foldersOf(s.id))).length,
  };
}

/// "2 books, 1 show": everything in a folder, whatever the tab.
String folderContents(Folder f) {
  final parts = [
    for (final k in FolderKind.values)
      if (folderCount(k, f.id) > 0) countOf(folderCount(k, f.id), k),
  ];
  return parts.isEmpty ? 'Empty' : parts.join(', ');
}

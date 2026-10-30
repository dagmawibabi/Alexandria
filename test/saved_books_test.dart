import 'dart:io';

import 'package:alexandria/models/book.dart';
import 'package:alexandria/services/library.dart';
import 'package:alexandria/services/storage.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final lib = Library.i;
  SavedBook fresh() => SavedBook(key: 'k', title: 'T');

  setUp(() {
    Storage.data = Directory.systemTemp.createTempSync('saved');
    lib.saved.clear();
  });

  test('hearting a book does not save it', () {
    final rec = lib.savedOr(fresh());
    rec.mark.favorite = true;
    lib.savedChanged(rec);
    expect(lib.isSaved('k'), isFalse);
    expect(lib.wantToRead, isEmpty);
    expect(lib.savedOr(fresh()).mark.favorite, isTrue); // but the heart is kept
  });

  test('rating or filing does not save it either', () {
    final rec = lib.savedOr(fresh());
    rec.mark.rating = 4;
    lib.savedChanged(rec);
    lib.toggleSavedFolder(lib.savedOr(fresh()), 'folder');
    expect(lib.isSaved('k'), isFalse);
    final kept = lib.savedOr(fresh());
    expect(kept.mark.rating, 4);
    expect(kept.folderIds, ['folder']);
  });

  test('Save works by itself, and leaves your marks alone both ways', () {
    final rec = lib.savedOr(fresh());
    rec.mark.favorite = true;
    lib.savedChanged(rec);

    lib.toggleSaved(fresh());
    expect(lib.isSaved('k'), isTrue);
    expect(lib.savedOr(fresh()).mark.favorite, isTrue);

    lib.toggleSaved(fresh());
    expect(lib.isSaved('k'), isFalse);
    expect(lib.savedOr(fresh()).mark.favorite, isTrue);
  });

  test('an unsaved book with nothing left on it is dropped', () {
    lib.toggleSaved(fresh());
    lib.toggleSaved(fresh());
    expect(lib.saved, isEmpty);

    final rec = lib.savedOr(fresh());
    rec.mark.favorite = true;
    lib.savedChanged(rec);
    rec.mark.favorite = false;
    lib.savedChanged(rec);
    expect(lib.saved, isEmpty);
  });

  test('un-hearting a saved book keeps it saved', () {
    lib.toggleSaved(fresh());
    final rec = lib.savedOr(fresh());
    rec.mark.favorite = true;
    lib.savedChanged(rec);
    rec.mark.favorite = false;
    lib.savedChanged(rec);
    expect(lib.isSaved('k'), isTrue);
  });

  test('books saved before this change stay saved; marked ones survive a round trip', () {
    expect(SavedBook.fromJson({'key': 'old', 'title': 'Old'}).wanted, isTrue);
    final marked = SavedBook(key: 'k', title: 'T', wanted: false, folderIds: ['f']);
    final back = SavedBook.fromJson(marked.toJson());
    expect(back.wanted, isFalse);
    expect(back.folderIds, ['f']);
  });

  test('a folder keeps its cover through saving, and works without one', () {
    final f = Folder.fromJson(Folder(id: 'f', name: 'N', coverPath: '/x.img').toJson());
    expect(f.coverPath, '/x.img');
    expect(Folder.fromJson(Folder(id: 'g', name: 'M').toJson()).coverPath, isNull);
  });
}

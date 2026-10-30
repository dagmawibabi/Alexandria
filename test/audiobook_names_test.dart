import 'package:alexandria/models/audiobook.dart';
import 'package:alexandria/screens/audiobook_create.dart';
import 'package:alexandria/services/free_audio.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('track titles drop numbering, underscores and extensions', () {
    expect(cleanTrackTitle('03 - The_Mirror.mp3'), 'The Mirror');
    expect(cleanTrackTitle('Chapter 12. Into the Woods.m4b'), 'Into the Woods');
    expect(cleanTrackTitle('track01.mp3'), 'track01');
    expect(cleanTrackTitle('07.mp3'), '07');
  });

  test('title guess uses the files\' shared start', () {
    expect(guessTitle(['Dune Part 01.mp3', 'Dune Part 02.mp3', 'Dune Part 10.mp3']), 'Dune');
    expect(guessTitle(['The Hobbit - 01.mp3', 'The Hobbit - 02.mp3']), 'The Hobbit');
    expect(guessTitle(['Project_Hail_Mary.m4b']), 'Project Hail Mary');
    expect(guessTitle(['01 Intro.mp3', '02 Storm.mp3']), 'Intro');
  });

  test('progress follows time when every length is known', () {
    final b = Audiobook(id: 'x', title: 'x', tracks: [AudioTrack(title: 'a', path: 'a', ms: 1000), AudioTrack(title: 'b', path: 'b', ms: 3000)], trackIndex: 1, positionMs: 1000);
    expect(b.progress, closeTo(.5, 1e-9));
    final unknown = Audiobook(id: 'y', title: 'y', tracks: [AudioTrack(title: 'a', path: 'a'), AudioTrack(title: 'b', path: 'b')], trackIndex: 1);
    expect(unknown.progress, closeTo(.5, 1e-9));
  });
}

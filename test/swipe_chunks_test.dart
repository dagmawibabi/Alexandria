import 'package:alexandria/models/doc.dart';
import 'package:alexandria/screens/reader/swipe_view.dart';
import 'package:flutter_test/flutter_test.dart';

String sentences(int n, {String word = 'word'}) => List.generate(n, (i) => '${List.filled(9, word).join(' ')} end$i.').join(' ');

int words(Chunk c) => c.text.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).length;

void main() {
  test('short paragraphs share a card instead of one card each', () {
    final doc = ParsedDoc(toc: const [], blocks: [for (var i = 0; i < 12; i++) Block(BlockType.paragraph, text: sentences(2))]); // 20 words each
    final chunks = buildChunks(doc, 100);
    expect(chunks.length, lessThan(4));
    expect(chunks.first.parts.length, greaterThan(1));
    // Every card but the chapter's tail reaches the target.
    for (final c in chunks.take(chunks.length - 1)) {
      expect(words(c), greaterThanOrEqualTo(100));
    }
    expect(words(chunks.last), greaterThanOrEqualTo(35));
  });

  test('every word lands on exactly one card, in order', () {
    final blocks = [
      const Block(BlockType.heading, text: 'Chapter One', level: 1),
      for (var i = 0; i < 8; i++) Block(i.isEven ? BlockType.paragraph : BlockType.quote, text: sentences(3 + i)),
      const Block(BlockType.heading, text: 'Chapter Two', level: 1),
      Block(BlockType.paragraph, text: sentences(30)),
    ];
    final doc = ParsedDoc(toc: const [], blocks: blocks);
    final chunks = buildChunks(doc, 80);
    final rebuilt = <int, StringBuffer>{};
    var lastBlock = -1, lastEnd = -1;
    for (final c in chunks) {
      for (final p in c.parts) {
        expect(p.block > lastBlock || (p.block == lastBlock && p.start >= lastEnd), isTrue, reason: 'parts out of order');
        expect(p.text, doc.blocks[p.block].text.substring(p.start, p.end));
        (rebuilt[p.block] ??= StringBuffer()).write('${p.text} ');
        lastBlock = p.block;
        lastEnd = p.end;
      }
    }
    for (var i = 0; i < blocks.length; i++) {
      expect(rebuilt[i].toString().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList(), blocks[i].text.split(RegExp(r'\s+')).toList());
    }
  });

  test('headings stand alone and text never crosses a chapter', () {
    final doc = ParsedDoc(toc: const [], blocks: [
      Block(BlockType.paragraph, text: sentences(1)),
      const Block(BlockType.heading, text: 'Two', level: 1),
      Block(BlockType.paragraph, text: sentences(1)),
    ]);
    final chunks = buildChunks(doc, 100);
    expect(chunks.map((c) => c.type).toList(), [BlockType.paragraph, BlockType.heading, BlockType.paragraph]);
  });

  test('a long paragraph splits at sentence ends near the target', () {
    final doc = ParsedDoc(toc: const [], blocks: [Block(BlockType.paragraph, text: sentences(40))]); // 400 words
    final chunks = buildChunks(doc, 100);
    expect(chunks.length, 4);
    for (final c in chunks) {
      expect(c.text.trim().endsWith('.'), isTrue);
    }
  });
}

/// The format-independent text model every reader feature works on.
/// PDF, EPUB and DOCX are all parsed into a list of [Block]s plus a
/// table of contents pointing into that list.
enum BlockType { heading, paragraph, quote, image, rule }

/// What separates words: spaces, and in Ethiopic text the word and sentence
/// marks (፡ ። ፣ ፤ ፥ ፦ ፧ ፨), which often have no space around them.
final wordBreak = RegExp(r'[\s፡-፨]+');

int countWords(String s) => s.split(wordBreak).where((w) => w.isNotEmpty).length;

class Block {
  const Block(this.type, {this.text = '', this.level = 0, this.image, this.page});

  final BlockType type;
  final String text;

  /// Heading level (1..6).
  final int level;

  /// Absolute path to an extracted image.
  final String? image;

  /// Original page (PDF only), 0-based.
  final int? page;

  int get words => countWords(text);

  Map<String, dynamic> toJson() => {
        't': type.index,
        if (text.isNotEmpty) 'x': text,
        if (level != 0) 'l': level,
        if (image != null) 'i': image,
        if (page != null) 'p': page,
      };

  factory Block.fromJson(Map<String, dynamic> j) =>
      Block(BlockType.values[j['t']], text: j['x'] ?? '', level: j['l'] ?? 0, image: j['i'], page: j['p']);
}

class TocEntry {
  const TocEntry(this.title, this.block, {this.depth = 0});

  final String title;
  final int block;
  final int depth;

  Map<String, dynamic> toJson() => {'t': title, 'b': block, 'd': depth};

  factory TocEntry.fromJson(Map<String, dynamic> j) => TocEntry(j['t'], j['b'], depth: j['d'] ?? 0);
}

class ParsedDoc {
  ParsedDoc({
    required this.blocks,
    required this.toc,
    this.title,
    this.author,
    this.description,
    this.publisher,
    this.language,
    this.year,
    this.isbn,
    this.coverBytes,
    this.pageCount = 0,
  });

  final List<Block> blocks;
  final List<TocEntry> toc;
  final String? title;
  final String? author;
  final String? description;
  final String? publisher;
  final String? language;
  final String? year;
  final String? isbn;
  final int pageCount;

  /// Only present right after parsing; not cached.
  final List<int>? coverBytes;

  late final int wordCount = blocks.fold(0, (s, b) => s + b.words);

  /// Running word count before each block, for progress and time-left.
  late final List<int> wordOffsets = () {
    final out = List<int>.filled(blocks.length + 1, 0);
    for (var i = 0; i < blocks.length; i++) {
      out[i + 1] = out[i] + blocks[i].words;
    }
    return out;
  }();

  /// The TOC entry containing [block].
  TocEntry? chapterAt(int block) {
    TocEntry? found;
    for (final e in toc) {
      if (e.block <= block) {
        found = e;
      } else {
        break;
      }
    }
    return found;
  }

  Map<String, dynamic> toJson() => {
        'v': 2,
        'blocks': blocks.map((b) => b.toJson()).toList(),
        'toc': toc.map((e) => e.toJson()).toList(),
        'pageCount': pageCount,
      };

  factory ParsedDoc.fromJson(Map<String, dynamic> j) => ParsedDoc(
        blocks: (j['blocks'] as List).map((e) => Block.fromJson(e)).toList(),
        toc: (j['toc'] as List).map((e) => TocEntry.fromJson(e)).toList(),
        pageCount: j['pageCount'] ?? 0,
      );
}

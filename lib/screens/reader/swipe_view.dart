import 'dart:async';
import 'dart:io';

import 'package:material_ui/material_ui.dart';

import '../../core/settings.dart';
import '../../core/theme.dart';
import '../../core/ui.dart';
import '../../models/annotations.dart';
import '../../models/book.dart';
import '../../models/doc.dart';
import '../../services/library.dart';
import 'block_view.dart';
import 'reader_sheets.dart';

/// A run of one block's text that sits on a card.
class Part {
  const Part(this.block, this.start, this.end, this.text, this.type);
  final int block;
  final int start;
  final int end;
  final String text;
  final BlockType type;
}

/// One swipe card: a heading, an image, or text that may span several paragraphs.
class Chunk {
  const Chunk(this.parts, this.type, {this.image, this.level = 0, this.words = 0});
  final List<Part> parts;
  final BlockType type;
  final String? image;
  final int level;
  final int words;

  int get block => parts.first.block;
  int get start => parts.first.start;
  int get end => parts.last.end;
  String get text => parts.map((p) => p.text).join('\n\n');
  bool get isText => type != BlockType.heading && type != BlockType.image;
}

int _countWords(String s) => s.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).length;

/// Splits the book into cards of about [targetWords], breaking at sentence ends.
/// Consecutive paragraphs share a card; headings and images get their own.
List<Chunk> buildChunks(ParsedDoc doc, int targetWords) {
  final out = <Chunk>[];
  final sentenceEnd = RegExp(r'(?<=[.!?…;:"”’።])\s+');
  var parts = <Part>[];
  var words = 0;

  void flush() {
    if (parts.isEmpty) return;
    final prev = out.isEmpty ? null : out.last;
    // A short tail joins the card before it rather than standing alone.
    if (words < targetWords * .35 && prev != null && prev.isText && prev.words + words <= targetWords * 1.3) {
      out[out.length - 1] = Chunk([...prev.parts, ...parts], BlockType.paragraph, words: prev.words + words);
    } else {
      out.add(Chunk(parts, BlockType.paragraph, words: words));
    }
    parts = [];
    words = 0;
  }

  void add(int block, int a, int b, BlockType type) {
    final text = doc.blocks[block].text;
    if (text.substring(a, b).trim().isEmpty) return;
    final last = parts.isEmpty ? null : parts.last;
    if (last != null && last.block == block) {
      parts[parts.length - 1] = Part(block, last.start, b, text.substring(last.start, b), type);
    } else {
      parts.add(Part(block, a, b, text.substring(a, b), type));
    }
    words += _countWords(text.substring(a, b));
    if (words >= targetWords) flush();
  }

  for (var i = 0; i < doc.blocks.length; i++) {
    final b = doc.blocks[i];
    switch (b.type) {
      case BlockType.rule:
        continue;
      case BlockType.image:
        if (b.image == null) continue;
        flush();
        out.add(Chunk([Part(i, 0, 0, b.text, BlockType.image)], BlockType.image, image: b.image));
        continue;
      case BlockType.heading:
        flush();
        out.add(Chunk([Part(i, 0, b.text.length, b.text, BlockType.heading)], BlockType.heading, level: b.level));
        continue;
      default:
    }
    var cursor = 0;
    for (final m in sentenceEnd.allMatches(b.text)) {
      add(i, cursor, m.start, b.type);
      cursor = m.end;
    }
    if (cursor < b.text.length) add(i, cursor, b.text.length, b.type);
  }
  flush();
  return out;
}

class SwipeReader extends StatefulWidget {
  const SwipeReader({
    super.key,
    required this.book,
    required this.doc,
    required this.style,
    required this.startBlock,
    required this.onBlock,
    required this.onSelection,
    required this.onBookmark,
    required this.onSpeak,
    required this.onTapCenter,
  });

  final Book book;
  final ParsedDoc doc;
  final ReaderStyle style;
  final int startBlock;
  final ValueChanged<int> onBlock;
  final OnSelection onSelection;
  final ValueChanged<int> onBookmark;
  final ValueChanged<String> onSpeak;
  final VoidCallback onTapCenter;

  @override
  State<SwipeReader> createState() => _SwipeReaderState();
}

class _SwipeReaderState extends State<SwipeReader> with SingleTickerProviderStateMixin {
  List<Chunk> _chunks = const [];
  PageController? _pages;
  int _words = 0;
  int _index = 0;
  Timer? _auto;
  bool _holding = false;
  late final AnimationController _burst = AnimationController(vsync: this, duration: const Duration(milliseconds: 650));

  @override
  void initState() {
    super.initState();
    Settings.i.addListener(_schedule);
  }

  /// Words per card: fixed, or as many as fill the screen at the current type size.
  int _targetWords(BuildContext context) {
    final s = Settings.i;
    if (!s.swipeFit) return s.swipeWords;
    final mq = MediaQuery.of(context);
    final st = widget.style;
    final fs = st.body.fontSize! * s.swipeFontScale;
    final lineH = fs * (st.body.height ?? 1.5);
    final w = mq.size.width - (st.margin + 4) - (st.margin + 56);
    final h = mq.size.height - mq.padding.vertical - 64 - 84 - 30;
    final charsPerLine = w / (fs * .5);
    final lines = h / lineH;
    // Paragraph gaps, ragged line ends and finishing the sentence eat room; leave slack.
    final words = charsPerLine * lines / 6 * .78;
    return ((words / 10).round() * 10).clamp(30, 400);
  }

  void _rebuild(int target) {
    final block = _chunks.isEmpty ? widget.startBlock : _chunks[_index].block;
    _words = target;
    _chunks = buildChunks(widget.doc, target);
    _index = _chunks.isEmpty ? 0 : _chunks.lastIndexWhere((c) => c.block <= block).clamp(0, _chunks.length - 1);
    final old = _pages;
    _pages = PageController(initialPage: _index);
    if (old != null) WidgetsBinding.instance.addPostFrameCallback((_) => old.dispose());
    _schedule();
  }

  void _schedule() {
    _auto?.cancel();
    if (!Settings.i.swipeAuto || _chunks.isEmpty) return;
    final words = _countWords(_chunks[_index].text).clamp(3, 1000);
    final ms = (words / Settings.i.swipeWpm * 60000).round() + 400;
    _auto = Timer(Duration(milliseconds: ms), () {
      if (!mounted) return;
      if (_holding) return _schedule();
      if (_index < _chunks.length - 1) _pages?.nextPage(duration: const Duration(milliseconds: 420), curve: Curves.easeOutCubic);
    });
  }

  @override
  void dispose() {
    Settings.i.removeListener(_schedule);
    _auto?.cancel();
    _pages?.dispose();
    _burst.dispose();
    super.dispose();
  }

  bool _liked(Chunk c) {
    if (!c.isText) return false;
    final hls = Library.i.highlights.where((h) => h.bookId == widget.book.id).toList();
    return c.parts.every((p) => hls.any((h) => h.block == p.block && h.start <= p.start && h.end >= p.end));
  }

  void _like(Chunk c) {
    if (!c.isText) return;
    haptic(true);
    if (_liked(c)) {
      for (final p in c.parts) {
        widget.onSelection(SelAction.unmark, p.block, p.start, p.end, p.text);
      }
    } else {
      final hls = Library.i.highlights.where((h) => h.bookId == widget.book.id).toList();
      for (final p in c.parts) {
        if (!hls.any((h) => h.block == p.block && h.start <= p.start && h.end >= p.end)) {
          widget.onSelection(SelAction.highlight, p.block, p.start, p.end, p.text);
        }
      }
      _burst.forward(from: 0);
    }
  }

  void _sizeSheet() {
    showSheet(context, builder: (ctx) => const Padding(padding: EdgeInsets.fromLTRB(20, 4, 20, 24), child: SwipeControls()));
  }

  @override
  Widget build(BuildContext context) {
    final target = _targetWords(context);
    if (target != _words) _rebuild(target);
    final st = widget.style;
    if (_chunks.isEmpty) return Center(child: Text('Nothing to swipe here.', style: st.body));
    final horizontal = Settings.i.swipeHorizontal;
    return Listener(
      onPointerDown: (_) => _holding = true,
      onPointerUp: (_) => _holding = false,
      child: ListenableBuilder(
        listenable: Library.i,
        builder: (context, _) => Stack(children: [
          PageView.builder(
            controller: _pages,
            scrollDirection: horizontal ? Axis.horizontal : Axis.vertical,
            itemCount: _chunks.length,
            onPageChanged: (i) {
              haptic();
              setState(() => _index = i);
              widget.onBlock(_chunks[i].block);
              _schedule();
            },
            itemBuilder: (context, i) => _card(context, _chunks[i]),
          ),
          // like burst
          IgnorePointer(
            child: AnimatedBuilder(
              animation: _burst,
              builder: (context, _) {
                final v = _burst.value;
                if (v == 0 || v == 1) return const SizedBox.shrink();
                return Center(
                  child: Opacity(
                    opacity: (1 - v).clamp(0, 1),
                    child: Transform.scale(
                      scale: .6 + v * .9,
                      child: Transform.rotate(angle: .785, child: Container(width: 90, height: 90, decoration: BoxDecoration(border: Border.all(color: Settings.i.signalOn(widget.style.surface.fg), width: 6)))),
                    ),
                  ),
                );
              },
            ),
          ),
          _rail(context),
          _footer(context),
        ]),
      ),
    );
  }

  Widget _card(BuildContext context, Chunk c) {
    final st = widget.style;
    final chapter = widget.doc.chapterAt(c.block)?.title ?? widget.book.title;
    final scale = Settings.i.swipeFontScale;
    final base = st.body.copyWith(fontSize: st.body.fontSize! * scale, height: st.body.height);

    Widget content;
    if (c.type == BlockType.image && c.image != null) {
      content = Image.file(File(c.image!), fit: BoxFit.contain);
    } else if (c.type == BlockType.heading) {
      content = Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(width: 40, height: 3, color: Settings.i.signalOn(widget.style.surface.fg)),
        const SizedBox(height: 18),
        Text(c.parts.first.text, style: st.heading(1).copyWith(fontSize: st.body.fontSize! * 2.1 * scale, height: 1.08, letterSpacing: -1)),
      ]);
    } else {
      final hls = Library.i.highlightsFor(widget.book.id);
      content = Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        for (var i = 0; i < c.parts.length; i++) ...[
          if (i > 0) SizedBox(height: st.paraGap * scale),
          _PartText(
            part: c.parts[i],
            style: base,
            highlights: hls.where((h) => h.block == c.parts[i].block && h.start < c.parts[i].end && c.parts[i].start < h.end).toList(),
            dark: st.surface.dark,
            onSelection: widget.onSelection,
          ),
        ],
      ]);
    }

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onDoubleTap: () => _like(c),
      onTap: widget.onTapCenter,
      child: SafeArea(
        child: Padding(
          padding: EdgeInsets.fromLTRB(st.margin + 4, 64, st.margin + 56, 84),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Container(width: 6, height: 6, color: Settings.i.signalOn(widget.style.surface.fg)),
              const SizedBox(width: 8),
              Expanded(child: Text(caps(chapter), maxLines: 1, overflow: TextOverflow.ellipsis, style: monoFont(color: st.muted, fontSize: 10, letterSpacing: 1.2))),
            ]),
            Expanded(child: Center(child: SingleChildScrollView(child: content))),
          ]),
        ),
      ),
    );
  }

  Widget _rail(BuildContext context) {
    final st = widget.style;
    final t = Tokens.of(context);
    final c = _chunks[_index];
    final liked = _liked(c);
    final marked = Library.i.bookmarkAt(widget.book.id, c.block) != null;
    Widget btn(IconData i, String label, VoidCallback onTap, {bool on = false}) => GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () {
            haptic();
            onTap();
          },
          child: Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: Column(children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 140),
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: on ? Settings.i.signalOn(widget.style.surface.fg) : st.surface.fg.withValues(alpha: .07),
                  borderRadius: BorderRadius.circular(Settings.i.radius + 4),
                  border: Border.all(color: on ? Settings.i.signalOn(widget.style.surface.fg) : st.surface.fg.withValues(alpha: .15)),
                ),
                child: Icon(i, size: 20, color: on ? t.onAccent : st.surface.fg),
              ),
              const SizedBox(height: 4),
              Text(caps(label), style: monoFont(fontSize: 8, color: st.muted, letterSpacing: .8)),
            ]),
          ),
        );
    return Positioned(
      right: 10,
      bottom: 100,
      child: Column(children: [
        if (c.isText) btn(liked ? Icons.favorite_sharp : Icons.favorite_border_sharp, 'Keep', () => _like(c), on: liked),
        btn(marked ? Icons.bookmark_sharp : Icons.bookmark_border_sharp, 'Mark', () => widget.onBookmark(c.block), on: marked),
        if (c.isText) btn(Icons.auto_awesome_outlined, 'Explain', () => widget.onSelection(SelAction.explain, c.block, c.start, c.end, c.text)),
        if (c.isText) btn(Icons.ios_share_sharp, 'Card', () => widget.onSelection(SelAction.quote, c.block, c.start, c.end, c.text)),
        btn(Icons.graphic_eq_sharp, 'Listen', () => widget.onSpeak(c.text)),
        btn(Icons.format_size_sharp, Settings.i.swipeFit ? 'Fit' : '${Settings.i.swipeWords}w', _sizeSheet),
      ]),
    );
  }

  Widget _footer(BuildContext context) {
    final st = widget.style;
    final total = _chunks.length;
    final remainingInChapter = () {
      final chapter = widget.doc.chapterAt(_chunks[_index].block);
      final next = widget.doc.toc.where((e) => chapter == null ? e.block > _chunks[_index].block : e.block > chapter.block).firstOrNull?.block ?? widget.doc.blocks.length;
      return _chunks.skip(_index + 1).takeWhile((c) => c.block < next).length;
    }();
    return Positioned(
      left: 0,
      right: 0,
      bottom: 0,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: EdgeInsets.fromLTRB(st.margin + 4, 0, st.margin + 4, 14),
          child: Column(children: [
            Row(children: [
              Text('${pad(_index + 1, 4)} / ${pad(total, 4)}', style: monoFont(color: st.muted, fontSize: 10)),
              const Spacer(),
              if (Settings.i.swipeAuto) Text('AUTO ${Settings.i.swipeWpm}WPM  ·  ', style: monoFont(color: Settings.i.signalOn(widget.style.surface.fg), fontSize: 10)),
              Flexible(child: Text('$remainingInChapter LEFT IN CHAPTER', maxLines: 1, overflow: TextOverflow.ellipsis, style: monoFont(color: st.muted, fontSize: 10))),
            ]),
            const SizedBox(height: 8),
            ClipRRect(
              child: LinearProgressIndicator(value: (_index + 1) / total, minHeight: 2, color: Settings.i.signalOn(widget.style.surface.fg), backgroundColor: st.surface.fg.withValues(alpha: .1)),
            ),
          ]),
        ),
      ),
    );
  }
}

class _PartText extends StatelessWidget {
  const _PartText({required this.part, required this.style, required this.highlights, required this.dark, required this.onSelection});
  final Part part;
  final TextStyle style;
  final List<Highlight> highlights;
  final bool dark;
  final OnSelection onSelection;

  @override
  Widget build(BuildContext context) {
    final c = part;
    final quote = c.type == BlockType.quote;
    final spans = <TextSpan>[];
    var pos = 0;
    final marks = highlights.map((h) => ((h.start - c.start).clamp(0, c.text.length), (h.end - c.start).clamp(0, c.text.length), h.color)).toList()..sort((a, b) => a.$1.compareTo(b.$1));
    for (final (a, b, col) in marks) {
      if (b <= pos) continue;
      final s = a < pos ? pos : a;
      if (s > pos) spans.add(TextSpan(text: c.text.substring(pos, s)));
      spans.add(TextSpan(text: c.text.substring(s, b), style: TextStyle(backgroundColor: highlightColor(col).withValues(alpha: dark ? .38 : .55))));
      pos = b;
    }
    if (pos < c.text.length) spans.add(TextSpan(text: c.text.substring(pos)));

    final text = SelectableText.rich(
      TextSpan(style: quote ? style.copyWith(fontStyle: FontStyle.italic) : style, children: spans),
      contextMenuBuilder: (ctx, state) {
        final v = state.textEditingValue;
        final a = v.selection.start.clamp(0, c.text.length);
        final b = v.selection.end.clamp(0, c.text.length);
        final chosen = c.text.substring(a, b).trim();
        final hit = highlights.where((h) => h.start < c.start + b && c.start + a < h.end).firstOrNull;
        return SelectionMenu(
          anchors: state.contextMenuAnchors,
          marked: hit?.color,
          compact: true,
          onAction: (x, {int color = 0}) {
            state.hideToolbar();
            state.userUpdateTextEditingValue(v.copyWith(selection: TextSelection.collapsed(offset: b)), SelectionChangedCause.toolbar);
            if (chosen.isNotEmpty || x == SelAction.unmark) onSelection(x, c.block, c.start + a, c.start + b, chosen, color: color);
          },
        );
      },
    );
    if (!quote) return text;
    return Container(padding: const EdgeInsets.only(left: 16), decoration: BoxDecoration(border: Border(left: BorderSide(color: Settings.i.signalOn(style.color ?? Settings.i.accent), width: 2))), child: text);
  }
}

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:material_ui/material_ui.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../core/color_picker.dart';
import '../core/settings.dart';
import '../core/theme.dart';
import '../core/ui.dart';
import '../models/annotations.dart';
import '../models/book.dart';

enum CardKind { highlight, bookmark, excerpt }

void showQuoteCard(BuildContext context,
    {required Book book, required String text, CardKind kind = CardKind.excerpt, int? color, String note = '', String? chapter, double? progress}) {
  Navigator.of(context).push(MaterialPageRoute(
    fullscreenDialog: true,
    builder: (_) => QuoteStudio(book: book, text: text, kind: kind, color: color, note: note, chapter: chapter, progress: progress ?? book.progress),
  ));
}

void shareHighlight(BuildContext context, Book book, Highlight h, {String? chapter}) =>
    showQuoteCard(context, book: book, text: h.text, kind: CardKind.highlight, color: h.color, note: h.note, chapter: chapter);

void shareBookmark(BuildContext context, Book book, Bookmark b, {String? passage}) => showQuoteCard(context,
    book: book, text: b.excerpt.isNotEmpty ? b.excerpt : (passage ?? b.label), kind: CardKind.bookmark, chapter: b.label, progress: b.progress);

class CardStyle {
  const CardStyle(this.name, this.bg, this.fg, this.font, {this.grid = false, this.cover = false, this.marker = false});
  final String name;
  final Color bg;
  final Color fg;
  final String font;
  final bool grid;
  final bool cover;
  final bool marker;
}

const cardStyles = [
  CardStyle('Spec', Color(0xFFEDEBE6), Color(0xFF151515), 'Space Grotesk'),
  CardStyle('Mono', Color(0xFF000000), Color(0xFFFFFFFF), 'JetBrains Mono'),
  CardStyle('Marker', Color(0xFFFAF9F6), Color(0xFF151515), 'Literata', marker: true),
  CardStyle('Noir', Color(0xFF0E0E0E), Color(0xFFF0EEE8), 'EB Garamond'),
  CardStyle('Signal', Color(0xFFFF5A1F), Color(0xFF141414), 'Space Grotesk'),
  CardStyle('Blueprint', Color(0xFF1D3F8F), Color(0xFFE8EEFF), 'IBM Plex Mono', grid: true),
  CardStyle('Paper', Color(0xFFF1E4C9), Color(0xFF3E3020), 'Crimson Pro'),
  CardStyle('Cover', Color(0xFF111111), Color(0xFFFFFFFF), 'Newsreader', cover: true),
];

/// The order the style picker shows [cardStyles] in: Cover first. The list
/// itself keeps its order, since the chosen style is saved by its position there.
final cardStyleOrder = [
  for (var i = 0; i < cardStyles.length; i++)
    if (cardStyles[i].cover) i,
  for (var i = 0; i < cardStyles.length; i++)
    if (!cardStyles[i].cover) i,
];

const _swatches = <Color>[
  Color(0xFF111111), Color(0xFFFFFFFF), Color(0xFFF1E4C9), Color(0xFF1D3F8F), Color(0xFF2D6BFF), //
  Color(0xFF0F5C4A), Color(0xFF00A86B), Color(0xFF7B61FF), Color(0xFF5A1E3C), Color(0xFFE5243B), Color(0xFFFFC300),
];

/// [st] with your own background, and ink that stays readable on it.
CardStyle cardWithBackground(CardStyle st, Color? bg) {
  if (bg == null) return st;
  return CardStyle('Custom', bg, bg.computeLuminance() > .45 ? const Color(0xFF151515) : const Color(0xFFF4F2EC), st.font, grid: st.grid, marker: st.marker);
}

/// Swatches and a colour mixer for a share card's background.
class CardColorPicker extends StatelessWidget {
  const CardColorPicker({super.key, required this.value, required this.onChanged, this.label = 'Background colour', this.resetLabel = 'Use style colour'});
  final Color? value;
  final ValueChanged<Color?> onChanged;
  final String label;
  final String resetLabel;

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Expanded(child: Label(label)),
        if (value != null) GestureDetector(onTap: () => onChanged(null), child: Label(resetLabel, color: t.accent, weight: FontWeight.w600)),
      ]),
      const SizedBox(height: 8),
      Wrap(spacing: 8, runSpacing: 8, children: [
        for (final c in _swatches)
          GestureDetector(
            onTap: () {
              haptic();
              onChanged(c);
            },
            child: Container(width: 34, height: 34, decoration: BoxDecoration(color: c, borderRadius: t.br, border: Border.all(color: value == c ? t.accent : t.line, width: value == c ? 2.5 : 1))),
          ),
      ]),
      ColorRow(label: 'Custom colour', color: value ?? _swatches[3], onChanged: onChanged),
    ]);
  }
}

class QuoteStudio extends StatefulWidget {
  const QuoteStudio({super.key, required this.book, required this.text, this.kind = CardKind.excerpt, this.color, this.note = '', this.chapter, this.progress = 0});
  final Book book;
  final String text;
  final CardKind kind;
  final int? color;
  final String note;
  final String? chapter;
  final double progress;

  @override
  State<QuoteStudio> createState() => _QuoteStudioState();
}

class _QuoteStudioState extends State<QuoteStudio> {
  final _key = GlobalKey();
  late int _style = (widget.kind == CardKind.highlight && Settings.i.quoteStyle == 0 ? 2 : Settings.i.quoteStyle).clamp(0, cardStyles.length - 1);
  double _aspect = 1;
  bool _showMeta = true;
  bool _showBrand = Settings.i.quoteBrand;
  bool _showNote = true;
  bool _center = false;
  String? _font;
  bool _sharing = false;
  late int _color = widget.color ?? 0;

  /// The book cover above the quote, as a fraction of the card's width. 0 is off.
  double _coverSize = 0;

  Future<void> _share() async {
    setState(() => _sharing = true);
    try {
      final boundary = _key.currentContext!.findRenderObject() as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: 3);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      final dir = await getTemporaryDirectory();
      final f = File(p.join(dir.path, 'alexandria-${widget.kind.name}-${DateTime.now().millisecondsSinceEpoch}.png'));
      await f.writeAsBytes(bytes!.buffer.asUint8List());
      await SharePlus.instance.share(ShareParams(
        files: [XFile(f.path, mimeType: 'image/png')],
        text: '“${widget.text}” — ${widget.book.title}${widget.book.author.isNotEmpty ? ', ${widget.book.author}' : ''}',
      ));
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Tokens.of(context);
    final st = cardWithBackground(cardStyles[_style], Settings.i.cardBg);
    final hasCover = widget.book.coverPath != null && File(widget.book.coverPath!).existsSync();
    return Scaffold(
      appBar: AppBar(title: AppTitle('${widget.kind.name} card'), actions: [
        Padding(
          padding: const EdgeInsets.only(right: 12),
          child: ToolButton(Icons.ios_share_sharp, label: _sharing ? '…' : 'Share', active: true, size: 38, onTap: _sharing ? null : _share),
        ),
      ]),
      body: ListView(padding: const EdgeInsets.fromLTRB(20, 8, 20, 40), children: [
        Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * .55),
            child: AspectRatio(
              aspectRatio: _aspect,
              child: RepaintBoundary(
                key: _key,
                child: _Card(
                  book: widget.book,
                  text: widget.text,
                  kind: widget.kind,
                  style: st,
                  font: _font ?? st.font,
                  meta: _showMeta,
                  brand: _showBrand,
                  note: _showNote ? widget.note : '',
                  chapter: widget.chapter,
                  progress: widget.progress,
                  center: _center,
                  accent: Settings.i.signalOn(st.fg),
                  mark: highlightColor(_color),
                  coverSize: _coverSize,
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 22),
        const Label('Style'),
        const SizedBox(height: 8),
        SizedBox(
          height: 64,
          child: ListView(scrollDirection: Axis.horizontal, children: [
            for (final i in cardStyleOrder)
              GestureDetector(
                onTap: () {
                  haptic();
                  // A style brings its own background, so this clears any custom one.
                  Settings.i.cardBg = null;
                  setState(() {
                    _style = i;
                    _font = null;
                  });
                  Settings.i.quoteStyle = i;
                },
                child: Container(
                  width: 64,
                  margin: const EdgeInsets.only(right: 8),
                  decoration: BoxDecoration(color: cardStyles[i].bg, borderRadius: t.br, border: Border.all(color: i == _style ? t.accent : t.line, width: i == _style ? 2 : 1)),
                  alignment: Alignment.center,
                  child: Text(cardStyles[i].name,
                      style: GoogleFonts.getFont(cardStyles[i].font, color: cardStyles[i].fg, fontSize: 11, fontWeight: FontWeight.w600,
                          backgroundColor: cardStyles[i].marker ? highlightColor(_color) : null)),
                ),
              ),
          ]),
        ),
        const SizedBox(height: 16),
        CardColorPicker(value: Settings.i.cardBg, onChanged: (c) => setState(() => Settings.i.cardBg = c)),
        if (hasCover) SliderRow(label: 'Cover image', value: _coverSize, min: 0, max: .6, format: (v) => v < .02 ? 'Off' : '${(v * 100).round()}%', onChanged: (v) => setState(() => _coverSize = v < .02 ? 0 : v)),
        if (widget.kind == CardKind.highlight) ...[
          const SizedBox(height: 16),
          const Label('Marker colour'),
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (var i = 0; i < highlightColors.length; i++)
              GestureDetector(
                onTap: () => setState(() => _color = i),
                child: Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(color: highlightColors[i], borderRadius: t.br, border: Border.all(color: _color == i ? t.ink : Colors.transparent, width: 2)),
                ),
              ),
          ]),
        ],
        const SizedBox(height: 16),
        const Label('Format'),
        const SizedBox(height: 8),
        Segmented<double>(values: const [1, 4 / 5, 9 / 16], labels: const ['1:1 Post', '4:5 Feed', '9:16 Story'], value: _aspect, onChanged: (v) => setState(() => _aspect = v)),
        const SizedBox(height: 16),
        const Label('Typeface'),
        const SizedBox(height: 8),
        SizedBox(
          height: 36,
          child: ListView(scrollDirection: Axis.horizontal, children: [
            for (final f in readerFonts) Padding(padding: const EdgeInsets.only(right: 6), child: Tag(f, filled: (_font ?? st.font) == f, onTap: () => setState(() => _font = f))),
          ]),
        ),
        const SizedBox(height: 8),
        ToggleRow(label: 'Show title & author', value: _showMeta, onChanged: (v) => setState(() => _showMeta = v)),
        ToggleRow(
          label: 'Show Alexandria label',
          hint: 'The "ALEXANDRIA / ${widget.kind.name.toUpperCase()}" line at the top',
          value: _showBrand,
          onChanged: (v) {
            setState(() => _showBrand = v);
            Settings.i.quoteBrand = v;
          },
        ),
        if (widget.note.isNotEmpty) ToggleRow(label: 'Include my note', value: _showNote, onChanged: (v) => setState(() => _showNote = v)),
        ToggleRow(label: 'Centre text', value: _center, onChanged: (v) => setState(() => _center = v)),
      ]),
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({
    required this.book,
    required this.text,
    required this.kind,
    required this.style,
    required this.font,
    required this.meta,
    required this.brand,
    required this.note,
    required this.chapter,
    required this.progress,
    required this.center,
    required this.accent,
    required this.mark,
    this.coverSize = 0,
  });
  final Book book;
  final String text;
  final CardKind kind;
  final CardStyle style;
  final String font;
  final bool meta;
  final bool brand;
  final String note;
  final String? chapter;
  final double progress;
  final bool center;
  final Color accent;
  final Color mark;
  final double coverSize;

  @override
  Widget build(BuildContext context) {
    final cover = book.coverPath != null && File(book.coverPath!).existsSync() ? book.coverPath : null;
    final signal = style.name == 'Signal';
    final tint = kind == CardKind.highlight ? mark : accent;
    return LayoutBuilder(builder: (context, c) {
      final w = c.maxWidth;
      final len = text.length + note.length ~/ 2;
      final size = (w / (len < 90 ? 13 : len < 200 ? 17 : len < 400 ? 22 : 28)).clamp(9.0, 40.0);
      final small = GoogleFonts.jetBrainsMono(color: style.fg.withValues(alpha: .6), fontSize: w * .024, letterSpacing: 1.2);
      final quoteStyle = GoogleFonts.getFont(font, color: style.fg, fontSize: size, height: 1.34, fontWeight: FontWeight.w500, letterSpacing: -.2);

      Widget quote = Text(
        text,
        textAlign: center ? TextAlign.center : TextAlign.left,
        maxLines: 14,
        overflow: TextOverflow.ellipsis,
        style: style.marker ? quoteStyle.copyWith(backgroundColor: mark.withValues(alpha: .75), color: const Color(0xFF151515)) : quoteStyle,
      );
      if (kind == CardKind.highlight && !style.marker && !center) {
        quote = Container(
          padding: EdgeInsets.only(left: w * .035),
          decoration: BoxDecoration(border: Border(left: BorderSide(color: signal ? style.fg : mark, width: w * .012))),
          child: quote,
        );
      }

      return Container(
        color: style.bg,
        child: Stack(fit: StackFit.expand, children: [
          if (style.cover && cover != null) ...[
            ImageFiltered(imageFilter: ui.ImageFilter.blur(sigmaX: 18, sigmaY: 18), child: Image.file(File(cover), fit: BoxFit.cover)),
            Container(color: Colors.black.withValues(alpha: .55)),
          ],
          if (style.grid) CustomPaint(painter: CardGrid(style.fg.withValues(alpha: .12))),
          // Bookmark ribbon
          if (kind == CardKind.bookmark)
            Positioned(right: w * .1, top: 0, width: w * .07, height: w * .16, child: CustomPaint(painter: _Ribbon(signal ? style.fg : accent))),
          Padding(
            padding: EdgeInsets.all(w * .08),
            child: Column(crossAxisAlignment: center ? CrossAxisAlignment.center : CrossAxisAlignment.start, children: [
              if (brand || kind != CardKind.bookmark)
                Row(children: [
                  if (brand) ...[
                    SizedBox(width: w * .045, height: w * .045, child: CustomPaint(painter: LogoMark(style.fg))),
                    SizedBox(width: w * .025),
                    Flexible(child: Text('ALEXANDRIA / ${kind.name.toUpperCase()}', maxLines: 1, overflow: TextOverflow.clip, style: small)),
                  ],
                  const Spacer(),
                  if (kind != CardKind.bookmark) Text('${(progress * 100).round().toString().padLeft(2, '0')}%', style: small),
                ]),
              // The quote block shrinks to fit rather than overflowing the card.
              Expanded(
                child: Align(
                  alignment: center ? Alignment.center : Alignment.centerLeft,
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: SizedBox(
                      width: w * .84,
                      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: center ? CrossAxisAlignment.center : CrossAxisAlignment.start, children: [
                        if (coverSize > 0 && cover != null) ...[
                          Container(
                            width: w * coverSize,
                            height: w * coverSize * 1.5,
                            clipBehavior: Clip.antiAlias,
                            decoration: BoxDecoration(borderRadius: BorderRadius.circular(w * .015), boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: .3), blurRadius: w * .04, offset: Offset(0, w * .012))]),
                            child: monoImage(Image.file(File(cover), fit: BoxFit.cover)),
                          ),
                          SizedBox(height: w * .04),
                        ],
                        if (kind != CardKind.highlight || style.marker || center)
                          Text(kind == CardKind.bookmark ? '■' : '“',
                              style: GoogleFonts.getFont(font, color: signal ? style.fg : tint, fontSize: kind == CardKind.bookmark ? w * .05 : w * .14, height: kind == CardKind.bookmark ? 2 : .8)),
                        quote,
                        if (note.isNotEmpty) ...[
                          SizedBox(height: w * .045),
                          Text('NOTE', style: small.copyWith(color: signal ? style.fg : tint)),
                          SizedBox(height: w * .01),
                          Text(note,
                              maxLines: 4,
                              overflow: TextOverflow.ellipsis,
                              textAlign: center ? TextAlign.center : TextAlign.left,
                              style: GoogleFonts.getFont(font, color: style.fg.withValues(alpha: .75), fontSize: size * .72, fontStyle: FontStyle.italic, height: 1.35)),
                        ],
                      ]),
                    ),
                  ),
                ),
              ),
              if (meta) ...[
                Container(height: 1, color: style.fg.withValues(alpha: .25)),
                SizedBox(height: w * .03),
                Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                  Expanded(
                    child: Column(crossAxisAlignment: center ? CrossAxisAlignment.center : CrossAxisAlignment.start, children: [
                      Text(book.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: GoogleFonts.spaceGrotesk(color: style.fg, fontSize: w * .038, fontWeight: FontWeight.w700)),
                      if (book.author.isNotEmpty) Text(book.author.toUpperCase(), maxLines: 1, style: small.copyWith(color: style.fg.withValues(alpha: .65))),
                      if (chapter != null && chapter!.isNotEmpty && chapter != book.title)
                        Text(chapter!.toUpperCase(), maxLines: 1, overflow: TextOverflow.ellipsis, style: small.copyWith(fontSize: w * .02)),
                    ]),
                  ),
                  if (kind == CardKind.bookmark) ...[
                    SizedBox(width: w * .03),
                    Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                      Text('${(progress * 100).toStringAsFixed(1)}%', style: GoogleFonts.jetBrainsMono(color: style.fg, fontSize: w * .05, fontWeight: FontWeight.w700)),
                      Text('MARKED', style: small),
                    ]),
                  ],
                ]),
                if (kind == CardKind.bookmark) ...[
                  SizedBox(height: w * .025),
                  // position track
                  Stack(children: [
                    Container(height: w * .006, color: style.fg.withValues(alpha: .2)),
                    FractionallySizedBox(widthFactor: progress.clamp(.01, 1), child: Container(height: w * .006, color: signal ? style.fg : accent)),
                  ]),
                ],
              ],
            ]),
          ),
        ]),
      );
    });
  }
}

/// The Alexandria mark: one plain circle.
class LogoMark extends CustomPainter {
  LogoMark(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final r = size.shortestSide / 2;
    canvas.drawCircle(size.center(Offset.zero), r * .88, Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = r * .24);
  }

  @override
  bool shouldRepaint(LogoMark o) => o.color != color;
}

class _Ribbon extends CustomPainter {
  _Ribbon(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size s) {
    final path = Path()
      ..moveTo(0, 0)
      ..lineTo(s.width, 0)
      ..lineTo(s.width, s.height)
      ..lineTo(s.width / 2, s.height * .78)
      ..lineTo(0, s.height)
      ..close();
    canvas.drawPath(path, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_Ribbon o) => o.color != color;
}

class CardGrid extends CustomPainter {
  CardGrid(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = color
      ..strokeWidth = 1;
    final step = size.width / 16;
    for (double x = 0; x < size.width; x += step) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), p);
    }
    for (double y = 0; y < size.height; y += step) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), p);
    }
  }

  @override
  bool shouldRepaint(CardGrid o) => o.color != color;
}
